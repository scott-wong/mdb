#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISTFILES_DIR="${DISTFILES_DIR:-$ROOT_DIR/distfiles}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/artifacts}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[mdb] %s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

source_baseline() {
    # shellcheck disable=SC1091
    source "$ROOT_DIR/scripts/baseline.env"
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual
    test -f "$file" || die "file not found: $file"
    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$file" | awk '{print $1}')"
    else
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    fi
    test "$actual" = "$expected" \
        || die "SHA256 mismatch for $file: expected $expected, got $actual"
}

image_tag() {
    printf '%s:%s-openeuler' "${1:-mdb}" "$(tr -d ' \n' < "$ROOT_DIR/VERSION")"
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local _
    for _ in $(seq 1 "$timeout"); do
        if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
            exec 3>&-
            return 0
        fi
        sleep 1
    done
    return 1
}
