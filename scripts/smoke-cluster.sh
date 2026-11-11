#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image is required}"
MODE="${2:?mode must be standard or gm}"
case "$MODE" in
    standard|gm) ;;
    *) echo "ERROR: unsupported TLS mode $MODE" >&2; exit 1 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET="mdb-cluster-net-${MODE}-$$"
TMP="$(mktemp -d)"
PREFIX="mdb-cluster-${MODE}-$$"
CONFIG="/usr/local/share/mdb/examples/cluster-${MODE}.conf"
CIPHER="TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
[ "$MODE" = "gm" ] && CIPHER="TLS_SM4_GCM_SM3"

cleanup() {
    for i in 1 2 3 4 5 6; do
        docker rm -f "${PREFIX}-node$i" >/dev/null 2>&1 || true
        docker volume rm "${PREFIX}-node$i" >/dev/null 2>&1 || true
    done
    docker network rm "$NET" >/dev/null 2>&1 || true
    timeout 20 docker run --rm --entrypoint /bin/bash -v "$TMP:/certs" \
        "$IMAGE" -c 'rm -rf /certs/*' >/dev/null 2>&1 || true
    rm -rf "$TMP" || true
}
trap cleanup EXIT

docker network create --subnet 172.28.0.0/16 "$NET" >/dev/null
docker run --rm --entrypoint /bin/bash \
    -v "$TMP:/certs" -v "$ROOT_DIR/test/smoke:/test:ro" \
    "$IMAGE" /test/generate-certs.sh /certs >/dev/null

for i in 1 2 3 4 5 6; do
    ip="172.28.0.$((9 + i))"
    docker run --detach --name "${PREFIX}-node$i" --network "$NET" --ip "$ip" \
        --env "MDB_TLS_MODE=$MODE" \
        --mount "type=bind,src=$TMP/$MODE,dst=/etc/mdb/tls,readonly" \
        --volume "${PREFIX}-node$i:/data" \
        "$IMAGE" valkey-server "$CONFIG" \
        --cluster-announce-ip "$ip" \
        --cluster-announce-port 0 \
        --cluster-announce-tls-port 6379 \
        --cluster-announce-bus-port 16379 >/dev/null
done

cluster_cli() {
    timeout 30 docker run --rm --network "$NET" \
        --env "OPENSSL_CONF=/usr/local/etc/mdb/openssl-${MODE}.cnf" \
        --entrypoint /usr/local/bin/mdb-cli \
        -v "$TMP/$MODE:/certs:ro" "$IMAGE" \
        --tls --cacert /certs/ca.crt --cert /certs/client.crt --key /certs/client.key \
        --tls-ciphersuites "$CIPHER" "$@"
}

wait_for_node() {
    local index="$1"
    local _
    for _ in $(seq 1 120); do
        if timeout 10 docker exec \
            -e "OPENSSL_CONF=/usr/local/etc/mdb/openssl-${MODE}.cnf" \
            "${PREFIX}-node$index" \
            /usr/local/bin/mdb-cli \
            --tls --cacert /run/mdb/tls/ca.crt --cert /run/mdb/tls/client.crt \
            --key /run/mdb/tls/client.key --tls-ciphersuites "$CIPHER" \
            -h 127.0.0.1 -p 6379 PING 2>/dev/null | grep -q PONG; then
            return 0
        fi
        sleep 1
    done
    return 1
}

for index in 1 2 3 4 5 6; do
    ip="172.28.0.1$index"
    if ! wait_for_node "$index"; then
        for i in 1 2 3 4 5 6; do docker logs "${PREFIX}-node$i" >&2 || true; done
        echo "ERROR: cluster node $ip did not become ready" >&2
        exit 1
    fi
done

cluster_cli --cluster create \
    172.28.0.10:6379 172.28.0.11:6379 172.28.0.12:6379 \
    172.28.0.13:6379 172.28.0.14:6379 172.28.0.15:6379 \
    --cluster-replicas 1 --cluster-yes >/dev/null

state=""
for _ in $(seq 1 60); do
    state="$(cluster_cli -c -h 172.28.0.10 -p 6379 CLUSTER INFO 2>/dev/null || true)"
    grep -q 'cluster_state:ok' <<<"$state" && break
    sleep 1
done
grep -q 'cluster_state:ok' <<<"$state" || {
    echo "$state" >&2
    echo "ERROR: cluster did not reach cluster_state:ok" >&2
    exit 1
}

cluster_cli -c -h 172.28.0.10 -p 6379 SET mdb-cluster ok | grep -q OK
value="$(cluster_cli -c -h 172.28.0.10 -p 6379 GET mdb-cluster)"
test "$value" = "ok"

docker restart "${PREFIX}-node4" >/dev/null
if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.13 6379 120' "$ROOT_DIR"; then
    docker logs "${PREFIX}-node4" >&2 || true
    echo "ERROR: cluster node did not restart" >&2
    exit 1
fi

for _ in $(seq 1 60); do
    state="$(cluster_cli -c -h 172.28.0.10 -p 6379 CLUSTER INFO 2>/dev/null || true)"
    grep -q 'cluster_state:ok' <<<"$state" && break
    sleep 1
done
grep -q 'cluster_state:ok' <<<"$state" || {
    echo "$state" >&2
    echo "ERROR: cluster did not recover after node restart" >&2
    exit 1
}

value="$(cluster_cli -c -h 172.28.0.10 -p 6379 GET mdb-cluster)"
test "$value" = "ok"

printf '[smoke] %s Cluster + cluster-bus TLS passed\n' "$MODE"
