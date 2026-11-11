#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image is required}"
MODE="${2:?mode must be standard or gm}"
case "$MODE" in
    standard|gm) ;;
    *) echo "ERROR: unsupported TLS mode $MODE" >&2; exit 1 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET="mdb-sentinel-net-${MODE}-$$"
TMP="$(mktemp -d)"
PREFIX="mdb-sentinel-${MODE}-$$"
CONFIG="/usr/local/share/mdb/examples/${MODE}.conf"
CIPHER="TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
[ "$MODE" = "gm" ] && CIPHER="TLS_SM4_GCM_SM3"

cleanup() {
    for name in primary replica1 replica2 sentinel1 sentinel2 sentinel3; do
        docker rm -f "${PREFIX}-${name}" >/dev/null 2>&1 || true
        docker volume rm "${PREFIX}-${name}" >/dev/null 2>&1 || true
    done
    docker network rm "$NET" >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

docker network create --subnet 172.28.0.0/16 "$NET" >/dev/null
docker run --rm --entrypoint /bin/bash \
    -v "$TMP:/certs" -v "$ROOT_DIR/test/smoke:/test:ro" \
    "$IMAGE" /test/generate-certs.sh /certs >/dev/null

common=(
    --detach --network "$NET"
    --env "MDB_TLS_MODE=$MODE"
    --mount "type=bind,src=$TMP/$MODE,dst=/etc/mdb/tls,readonly"
)
docker run "${common[@]}" --name "${PREFIX}-primary" --ip 172.28.0.10 \
    --volume "${PREFIX}-primary:/data" "$IMAGE" valkey-server "$CONFIG" >/dev/null
docker run "${common[@]}" --name "${PREFIX}-replica1" --ip 172.28.0.11 \
    --volume "${PREFIX}-replica1:/data" "$IMAGE" valkey-server "$CONFIG" \
    --replicaof 172.28.0.10 6379 --tls-replication yes \
    --tls-client-cert-file /run/mdb/tls/client.crt \
    --tls-client-key-file /run/mdb/tls/client.key >/dev/null
docker run "${common[@]}" --name "${PREFIX}-replica2" --ip 172.28.0.12 \
    --volume "${PREFIX}-replica2:/data" "$IMAGE" valkey-server "$CONFIG" \
    --replicaof 172.28.0.10 6379 --tls-replication yes \
    --tls-client-cert-file /run/mdb/tls/client.crt \
    --tls-client-key-file /run/mdb/tls/client.key >/dev/null

if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.10 6379 90; wait_for_port 172.28.0.11 6379 90; wait_for_port 172.28.0.12 6379 90' "$ROOT_DIR"; then
    docker logs "${PREFIX}-primary" >&2 || true
    echo "ERROR: Sentinel data nodes did not become ready" >&2
    exit 1
fi

mk_sentinel_config() {
    local ip="$1"
    local file="$2"
    cat >"$file" <<EOF
bind * -::*
protected-mode no
port 26379
tls-port 26380
dir /data
logfile ""
sentinel monitor mdb-primary 172.28.0.10 6379 2
sentinel down-after-milliseconds mdb-primary 5000
sentinel failover-timeout mdb-primary 60000
sentinel parallel-syncs mdb-primary 1
tls-cert-file /run/mdb/tls/server.crt
tls-key-file /run/mdb/tls/server.key
tls-ca-cert-file /run/mdb/tls/ca.crt
tls-auth-clients yes
tls-replication yes
tls-client-cert-file /run/mdb/tls/client.crt
tls-client-key-file /run/mdb/tls/client.key
tls-protocols "$([ "$MODE" = gm ] && echo TLSv1.3 || echo 'TLSv1.2 TLSv1.3')"
tls-ciphersuites $([ "$MODE" = gm ] && echo TLS_SM4_GCM_SM3 || echo TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256)
EOF
    chmod 0666 "$file"
}

for i in 1 2 3; do
    ip="172.28.0.2$i"
    mk_sentinel_config "$ip" "$TMP/sentinel$i.conf"
    docker run "${common[@]}" --name "${PREFIX}-sentinel$i" --ip "$ip" \
        --volume "$TMP/sentinel$i.conf:/etc/mdb/sentinel.conf:rw" \
        --volume "${PREFIX}-sentinel$i:/data" \
        "$IMAGE" valkey-server /etc/mdb/sentinel.conf --sentinel >/dev/null
done

if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.20 26380 90; wait_for_port 172.28.0.21 26380 90; wait_for_port 172.28.0.22 26380 90' "$ROOT_DIR"; then
    for i in 1 2 3; do docker logs "${PREFIX}-sentinel$i" >&2 || true; done
    echo "ERROR: Sentinel TLS listeners did not become ready" >&2
    exit 1
fi

sentinel_cli() {
    timeout 30 docker run --rm --network "$NET" \
        --env "OPENSSL_CONF=/usr/local/etc/mdb/openssl-${MODE}.cnf" \
        --entrypoint /usr/local/bin/mdb-cli \
        -v "$TMP/$MODE:/certs:ro" "$IMAGE" \
        --tls --cacert /certs/ca.crt --cert /certs/client.crt --key /certs/client.key \
        --tls-ciphersuites "$CIPHER" -h "$1" -p 26380 "${@:2}"
}

sentinel_cli 172.28.0.20 SENTINEL get-master-addr-by-name mdb-primary \
    | grep -q 172.28.0.10

sentinel_cli 172.28.0.20 SENTINEL SENTINELS mdb-primary | grep -q 172.28.0.21

sentinel_cli 172.28.0.20 SENTINEL FAILOVER mdb-primary | grep -q OK
new_master=""
for _ in $(seq 1 120); do
    new_master="$(sentinel_cli 172.28.0.21 SENTINEL get-master-addr-by-name mdb-primary 2>/dev/null | head -1 || true)"
    [ "$new_master" != "" ] && [ "$new_master" != "172.28.0.10" ] && break
    sleep 1
done
if [ -z "$new_master" ] || [ "$new_master" = "172.28.0.10" ]; then
    for i in 1 2 3; do docker logs "${PREFIX}-sentinel$i" >&2 || true; done
    echo "ERROR: Sentinel did not promote a replica" >&2
    exit 1
fi

value="$(sentinel_cli 172.28.0.21 INFO sentinel 2>/dev/null || true)"
grep -q 'master0:name=mdb-primary' <<<"$value"

printf '[smoke] %s Sentinel TLS passed, promoted %s\n' "$MODE" "$new_master"
