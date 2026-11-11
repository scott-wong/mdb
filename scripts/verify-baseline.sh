#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

version="$(tr -d ' \n' < "$ROOT_DIR/VERSION")"
[[ "$version" =~ ^${VALKEY_VERSION}-mdb\.[0-9]+$ ]] \
    || die "VERSION must be ${VALKEY_VERSION}-mdb.<N>, got: $version"

[[ "$OPENEULER_BASE" == *"@$OPENEULER_BASE_INDEX_DIGEST" ]] \
    || die "openEuler base reference and index digest disagree"
[[ "$OPENEULER_BASE_INDEX_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || die "invalid openEuler index digest"
[[ "$OPENEULER_BASE_AMD64_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || die "invalid openEuler amd64 digest"

for variable in VALKEY_SHA256 TONGSHUO_SHA256 TINI_SHA256 \
    SYFT_SHA256 TRIVY_SHA256 COSIGN_SHA256 CRANE_SHA256; do
    value="${!variable}"
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] \
        || die "$variable must be a lowercase SHA256"
done

for variable in VALKEY_COMMIT TONGSHUO_COMMIT TINI_COMMIT; do
    value="${!variable}"
    [[ "$value" =~ ^[0-9a-f]{40}$ ]] \
        || die "$variable must be a lowercase git commit"
done

[[ "$TONGSHUO_VERSION" == "8.5.0" ]] \
    || die "TONGSHUO_VERSION must be the reviewed 8.5.0 baseline"
[[ "$TONGSHUO_OPENSSL_VERSION" == "3.5.4" ]] \
    || die "TONGSHUO_OPENSSL_VERSION must match Tongsuo 8.5.0"

mkdir -p "$DISTFILES_DIR"
for pair in \
    "valkey-${VALKEY_VERSION}.tar.gz:$VALKEY_SHA256" \
    "tongsuo-${TONGSHUO_VERSION}.tar.gz:$TONGSHUO_SHA256" \
    "tini-${TINI_VERSION}.tar.gz:$TINI_SHA256"; do
    file="${pair%%:*}"
    sha="${pair#*:}"
    if [ -f "$DISTFILES_DIR/$file" ]; then
        verify_sha256 "$DISTFILES_DIR/$file" "$sha"
    else
        log "source not downloaded yet: $file (run make fetch)"
    fi
done

log "baseline verified for $version"
