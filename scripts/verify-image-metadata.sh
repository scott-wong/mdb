#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

version="$(tr -d ' \n' < "$ROOT_DIR/VERSION")"

label() {
    docker image inspect "$IMAGE" --format "{{index .Config.Labels \"$1\"}}"
}

test "$(label org.opencontainers.image.version)" = "$version"
test "$(label io.mdb.valkey.version)" = "$VALKEY_VERSION"
test "$(label io.mdb.tongsuo.version)" = "$TONGSHUO_VERSION"
test "$(label io.mdb.tongsuo.openssl-baseline)" = "$TONGSHUO_OPENSSL_VERSION"
test "$(label io.mdb.tls.rfc8998)" = "true"
test "$(label io.mdb.tls.tlcp)" = "false"
test "$(label io.mdb.runtime-user)" = "$RUNTIME_UID"
test "$(docker image inspect "$IMAGE" --format '{{.Os}}/{{.Architecture}}')" = "linux/amd64"

docker run --rm --entrypoint /bin/bash "$IMAGE" -c '
set -euo pipefail
test -x /opt/tongsuo/bin/openssl
test -x /usr/local/bin/valkey-server
test -x /usr/local/bin/valkey-cli
for tool in server sentinel cli benchmark check-rdb check-aof; do
    test -x "/usr/local/bin/mdb-$tool"
done
test ! -e /usr/local/bin/redis-server
test ! -e /usr/local/bin/redis-cli
test ! -d /opt/tongsuo/include
test -z "$(find /opt/tongsuo -type f \( -name "*.a" -o -name "*.h" \) -print -quit)"
test -f /usr/local/share/mdb/rpm-manifest.txt
ldd /usr/local/bin/valkey-server | grep -F "/opt/tongsuo/lib/libssl.so.3" >/dev/null
ldd /usr/local/bin/valkey-server | grep -F "/opt/tongsuo/lib/libcrypto.so.3" >/dev/null
! command -v gcc >/dev/null 2>&1
! command -v make >/dev/null 2>&1
mdb-cli --version >/dev/null
'

printf '[metadata] %s labels, filesystem and linkage passed\n' "$IMAGE"
