#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command curl
require_command tar
mkdir -p "$DISTFILES_DIR"

fetch() {
    local name="$1"
    local url="$2"
    local sha="$3"
    local output="$DISTFILES_DIR/$name"

    if [ -f "$output" ]; then
        if verify_sha256 "$output" "$sha" 2>/dev/null; then
            log "using cached $name"
            return 0
        fi
        log "cached $name failed verification; replacing"
        rm -f "$output"
    fi

    log "fetching $name"
    curl --fail --location --retry 5 --retry-all-errors \
        --connect-timeout 15 --output "$output" "$url"
    verify_sha256 "$output" "$sha"
}

fetch "valkey-${VALKEY_VERSION}.tar.gz" "$VALKEY_SOURCE_URL" "$VALKEY_SHA256"
fetch "tongsuo-${TONGSHUO_VERSION}.tar.gz" "$TONGSHUO_SOURCE_URL" "$TONGSHUO_SHA256"
fetch "tini-${TINI_VERSION}.tar.gz" "$TINI_SOURCE_URL" "$TINI_SHA256"

log "all source archives verified"
