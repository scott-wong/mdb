#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

archive="$DISTFILES_DIR/valkey-${VALKEY_VERSION}.tar.gz"
verify_sha256 "$archive" "$VALKEY_SHA256"

source_dir="/tmp/mdb-valkey-${VALKEY_VERSION}"
rm -rf "$source_dir"
mkdir -p "$source_dir"
tar --extract --gzip --file "$archive" \
    --directory "$source_dir" --strip-components 1

cd "$source_dir"
make -j"$(nproc)" \
    BUILD_TLS=yes \
    USE_SYSTEMD=no \
    OPENSSL_PREFIX=/opt/tongsuo \
    PKG_CONFIG_PATH=/opt/tongsuo/lib/pkgconfig \
    LDFLAGS="-Wl,-rpath,/opt/tongsuo/lib"
make install PREFIX=/usr/local

for binary in valkey-server valkey-sentinel valkey-cli valkey-benchmark \
    valkey-check-rdb valkey-check-aof; do
    test -x "/usr/local/bin/$binary" || die "missing installed binary: $binary"
done

ldd /usr/local/bin/valkey-server | grep -F '/opt/tongsuo/lib/libssl.so.3' \
    || die "valkey-server is not linked to the private Tongsuo libssl"
ldd /usr/local/bin/valkey-server | grep -F '/opt/tongsuo/lib/libcrypto.so.3' \
    || die "valkey-server is not linked to the private Tongsuo libcrypto"
ldd /usr/local/bin/valkey-cli | grep -F '/opt/tongsuo/lib/libssl.so.3' \
    || die "valkey-cli is not linked to the private Tongsuo libssl"

/usr/local/bin/valkey-server --version
/usr/local/bin/valkey-cli --version

log "Valkey $VALKEY_VERSION built against /opt/tongsuo"
