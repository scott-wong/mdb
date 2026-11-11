#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image is required}"
MODE="${2:?mode must be standard or gm}"
case "$MODE" in
    standard|gm) ;;
    *) echo "ERROR: unsupported TLS mode $MODE" >&2; exit 1 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="mdb-smoke-${MODE}-$$"
NET="mdb-net-${MODE}-$$"
TMP="$(mktemp -d)"
DATA_VOL="mdb-data-${MODE}-$$"
CONFIG="/usr/local/share/mdb/examples/${MODE}.conf"
CLIENT_CIPHER="TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
if [ "$MODE" = "gm" ]; then
    CLIENT_CIPHER="TLS_SM4_GCM_SM3"
fi

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker volume rm "$DATA_VOL" >/dev/null 2>&1 || true
    timeout 20 docker run --rm --entrypoint /bin/bash -v "$TMP:/certs" \
        "$IMAGE" -c 'rm -rf /certs/*' >/dev/null 2>&1 || true
    rm -rf "$TMP" || true
}
trap cleanup EXIT

docker network create --subnet 172.28.0.0/16 "$NET" >/dev/null
timeout 60 docker run --rm --entrypoint /bin/bash \
    -v "$TMP:/certs" \
    -v "$ROOT_DIR/test/smoke:/test:ro" \
    "$IMAGE" /test/generate-certs.sh /certs >/dev/null

start_args=(
    --detach
    --name "$NAME"
    --network "$NET"
    --ip 172.28.0.10
    --env "MDB_TLS_MODE=$MODE"
    --mount "type=bind,src=$TMP/$MODE,dst=/etc/mdb/tls,readonly"
    --volume "$DATA_VOL:/data"
)
docker run "${start_args[@]}" "$IMAGE" valkey-server "$CONFIG" >/dev/null

if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.10 6379 90' "$ROOT_DIR"; then
    docker logs "$NAME" >&2 || true
    echo "ERROR: Valkey did not become ready" >&2
    exit 1
fi

run_openssl() {
    timeout 12 docker run --rm --network "$NET" \
        --entrypoint /opt/tongsuo/bin/openssl \
        -v "$TMP/$MODE:/certs:ro" \
        "$IMAGE" "$@"
}

if [ "$MODE" = "standard" ]; then
    tls13_output="$(run_openssl s_client \
        -connect 172.28.0.10:6379 -tls1_3 \
        -CAfile /certs/ca.crt -cert /certs/client.crt -key /certs/client.key \
        -verify_return_error -brief -no_ign_eof 2>&1 </dev/null || true)"
    grep -q 'Protocol version: TLSv1.3' <<<"$tls13_output" || {
        echo "$tls13_output" >&2
        echo "ERROR: TLS 1.3 handshake failed for standard mode" >&2
        exit 1
    }
    tls12_output="$(run_openssl s_client \
        -connect 172.28.0.10:6379 -tls1_2 \
        -CAfile /certs/ca.crt -cert /certs/client.crt -key /certs/client.key \
        -verify_return_error -brief -no_ign_eof 2>&1 </dev/null || true)"
    grep -q 'Protocol version: TLSv1.2' <<<"$tls12_output" || {
        echo "$tls12_output" >&2
        echo "ERROR: TLS 1.2 handshake failed for standard mode" >&2
        exit 1
    }
else
    handshake="$(run_openssl s_client \
        -connect 172.28.0.10:6379 -tls1_3 \
        -ciphersuites TLS_SM4_GCM_SM3 -groups SM2 \
        -enable_sm_tls13_strict \
        -CAfile /certs/ca.crt -cert /certs/client.crt -key /certs/client.key \
        -verify_return_error -no_ign_eof 2>&1 </dev/null || true)"
    grep -q 'Cipher is TLS_SM4_GCM_SM3' <<<"$handshake" || {
        echo "$handshake" >&2
        echo "ERROR: GM handshake did not select TLS_SM4_GCM_SM3" >&2
        exit 1
    }
    grep -q 'Peer signature type: sm2sig_sm3' <<<"$handshake" || {
        echo "$handshake" >&2
        echo "ERROR: GM handshake did not use SM2 signatures" >&2
        exit 1
    }
    grep -q 'Peer Temp Key: ECDH, SM2' <<<"$handshake" || {
        echo "$handshake" >&2
        echo "ERROR: GM handshake did not use the SM2 key-exchange group" >&2
        exit 1
    }
fi

cli_args=(
    --tls
    --cacert /certs/ca.crt
    --cert /certs/client.crt
    --key /certs/client.key
    --tls-ciphersuites "$CLIENT_CIPHER"
    -h 172.28.0.10
    -p 6379
)
cli_env=(--env "OPENSSL_CONF=/usr/local/etc/mdb/openssl-${MODE}.cnf")
timeout 30 docker run --rm --network "$NET" "${cli_env[@]}" \
    --entrypoint /usr/local/bin/mdb-cli \
    -v "$TMP/$MODE:/certs:ro" "$IMAGE" "${cli_args[@]}" PING \
    | grep -q PONG

timeout 30 docker run --rm --network "$NET" "${cli_env[@]}" \
    --entrypoint /usr/local/bin/valkey-cli \
    -v "$TMP/$MODE:/certs:ro" "$IMAGE" "${cli_args[@]}" SET mdb-smoke ok \
    | grep -q OK

value="$(timeout 30 docker run --rm --network "$NET" "${cli_env[@]}" \
    --entrypoint /usr/local/bin/mdb-cli \
    -v "$TMP/$MODE:/certs:ro" "$IMAGE" "${cli_args[@]}" GET mdb-smoke)"
test "$value" = "ok"

# Persistence across a restart.
docker exec "$NAME" /opt/tongsuo/bin/openssl version >/dev/null
timeout 30 docker run --rm --network "$NET" "${cli_env[@]}" \
    --entrypoint /usr/local/bin/mdb-cli \
    -v "$TMP/$MODE:/certs:ro" "$IMAGE" "${cli_args[@]}" SAVE | grep -q OK
docker restart "$NAME" >/dev/null
if ! bash -c 'source "$0/scripts/lib.sh"; wait_for_port 172.28.0.10 6379 90' "$ROOT_DIR"; then
    docker logs "$NAME" >&2 || true
    echo "ERROR: Valkey did not restart" >&2
    exit 1
fi
value="$(timeout 30 docker run --rm --network "$NET" "${cli_env[@]}" \
    --entrypoint /usr/local/bin/mdb-cli \
    -v "$TMP/$MODE:/certs:ro" "$IMAGE" "${cli_args[@]}" GET mdb-smoke)"
test "$value" = "ok"

# A plaintext client must not be able to speak to the TLS listener.
if timeout 20 docker run --rm --network "$NET" --entrypoint /usr/local/bin/valkey-cli \
    "$IMAGE" -h 172.28.0.10 -p 6379 PING >/dev/null 2>&1; then
    echo "ERROR: plaintext client succeeded against a TLS-only listener" >&2
    exit 1
fi

# TLS config with mode=off must fail closed.
if timeout 20 docker run --rm --network "$NET" --env MDB_TLS_MODE=off \
    "$IMAGE" valkey-server /usr/local/share/mdb/examples/standard.conf \
    >/dev/null 2>&1; then
    echo "ERROR: TLS config started with MDB_TLS_MODE=off" >&2
    exit 1
fi

docker top "$NAME" -eo pid,user,comm \
    | awk '$3 == "valkey-server" && $2 == "999" { found=1 } END { exit !found }'
if timeout 20 docker run --rm --entrypoint /bin/bash "$IMAGE" -c \
    'command -v gcc || command -v make' >/dev/null 2>&1; then
    echo "ERROR: final image contains a compiler or make" >&2
    exit 1
fi

printf '[smoke] %s standalone TLS passed\n' "$MODE"
