#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

archive="$DISTFILES_DIR/tini-${TINI_VERSION}.tar.gz"
verify_sha256 "$archive" "$TINI_SHA256"

source_dir="/tmp/mdb-tini-${TINI_VERSION}"
build_dir="/tmp/mdb-tini-build"
rm -rf "$source_dir" "$build_dir"
mkdir -p "$source_dir" "$build_dir"

tar --extract --gzip --file "$archive" \
    --directory "$source_dir" --strip-components 1

cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/mdb/tini
cmake --build "$build_dir" -j"$(nproc)"
cmake --install "$build_dir"

test -x /opt/mdb/tini/bin/tini-static
/opt/mdb/tini/bin/tini-static --version
log "tini built"
