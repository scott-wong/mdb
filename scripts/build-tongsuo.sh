#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

archive="$DISTFILES_DIR/tongsuo-${TONGSHUO_VERSION}.tar.gz"
verify_sha256 "$archive" "$TONGSHUO_SHA256"

prefix="/opt/tongsuo"
source_dir="/tmp/mdb-tongsuo-${TONGSHUO_VERSION}"
rm -rf "$source_dir" "$prefix"
mkdir -p "$source_dir" "$prefix"

tar --extract --gzip --file "$archive" \
    --directory "$source_dir" --strip-components 1

cd "$source_dir"
./config \
    shared \
    --prefix="$prefix" \
    --openssldir="$prefix/etc/ssl" \
    --libdir="$prefix/lib" \
    -Wl,-rpath,"$prefix/lib"

make -j"$(nproc)"
make install_sw install_ssldirs

mkdir -p "$prefix/share/licenses/tongsuo"
cp "$source_dir/LICENSE.txt" "$prefix/share/licenses/tongsuo/LICENSE.txt"

"$prefix/bin/openssl" version | grep -q '^Tongsuo: Tongsuo 8.5.0 ' \
    || die "unexpected Tongsuo version output"

test -s "$prefix/lib/libssl.so.3"
test -s "$prefix/lib/libcrypto.so.3"

"$prefix/bin/openssl" ciphers -v -tls1_3 \
    -ciphersuites TLS_SM4_GCM_SM3 \
    | grep -q 'TLSv1.3'
"$prefix/bin/openssl" ciphers -v -tls1_3 \
    -ciphersuites TLS_SM4_CCM_SM3 \
    | grep -q 'TLSv1.3'

log "Tongsuo built at $prefix (RFC 8998 suites available, NTLS not enabled)"
