#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image is required}"
MODE="${2:?mode must be standard or gm}"
case "$MODE" in
    standard|gm) ;;
    *) echo "ERROR: unsupported TLS mode $MODE" >&2; exit 1 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="mdb-repl-${MODE}-$$"
NET="mdb-repl-net-${MODE}-$$"
TMP="$(mktemp -d)"
VOL1="mdb-repl-primary-${MODE}-$$"
VOL2="mdb-repl-replica-${MODE}-$$"
CONFIG="/usr/local/share/mdb/examples/${MODE}.conf"
CIPHER="TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
[ "$MODE" = "gm" ] && CIPHER="TLS_SM4_GCM_SM3"

cleanup() {
    docker rm -f "${NAME}-primary" "${NAME}-replica" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker volume rm "$VOL1" "$VOL2" >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

docker network create --subnet 172.28.0.0/16 "$NET" >/dev/null
docker run --rm --entrypoint /bin/bash \
    -v "$TMP:/certs" -v "$ROOT_DIR/test/smoke:/test:ro" \
    "$IMAGE" /test/generate-certs.sh /certs >/dev/null

common_args=(
    --detach --network "$NET"
    --env "MDB_TLS_MODE=$MODE"
    --mount "type=bind,src=$TMP/$MODE,dst=/etc/mdb/tls,readonly"
)
docker run "${common_args[@]}" --name "${NAME}-primary" --ip 172.28.0.10 \
    --volume "$VOL1:/data" "$IMAGE" valkey-server "$CONFIG" >/dev/null
docker run "${common_args[@]}" --name "${NAME}-replica" --ip 172.28.0.11 \
    --volume "$VOL2:/data" "$IMAGE" valkey-server "$CONFIG" \
    --replicaof 172.28.0.10 6379 \
    --tls-replication yes \
    --tls-client-cert-file /run/mdb/tls/client.crt \
    --tls-client-key-file /run/mdb/tls/client.key >/dev/null

if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.10 6379 90; wait_for_port 172.28.0.11 6379 90' "$ROOT_DIR"; then
    docker logs "${NAME}-primary" >&2 || true
    docker logs "${NAME}-replica" >&2 || true
    echo "ERROR: replication nodes did not become ready" >&2
    exit 1
fi

cli() {
    local host="$1"
    shift
    timeout 30 docker run --rm --network "$NET" \
        --env "OPENSSL_CONF=/usr/local/etc/mdb/openssl-${MODE}.cnf" \
        --entrypoint /usr/local/bin/mdb-cli \
        -v "$TMP/$MODE:/certs:ro" "$IMAGE" \
        --tls --cacert /certs/ca.crt --cert /certs/client.crt --key /certs/client.key \
        --tls-ciphersuites "$CIPHER" -h "$host" -p 6379 "$@"
}

cli 172.28.0.10 PING | grep -q PONG
cli 172.28.0.10 SET mdb-repl ok | grep -q OK

value=""
for _ in $(seq 1 60); do
    value="$(cli 172.28.0.11 GET mdb-repl 2>/dev/null || true)"
    [ "$value" = "ok" ] && break
    sleep 1
done
test "$value" = "ok" || {
    cli 172.28.0.11 INFO replication >&2 || true
    echo "ERROR: replica did not receive the key" >&2
    exit 1
}

cli 172.28.0.11 INFO replication | grep -q 'master_link_status:up'
cli 172.28.0.10 INFO replication | grep -q 'connected_slaves:1'

docker restart "${NAME}-replica" >/dev/null
if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.11 6379 90' "$ROOT_DIR"; then
    docker logs "${NAME}-replica" >&2 || true
    echo "ERROR: replica did not restart" >&2
    exit 1
fi
value="$(cli 172.28.0.11 GET mdb-repl)"
test "$value" = "ok"

printf '[smoke] %s replication TLS passed\n' "$MODE"
