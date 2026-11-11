#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command git
require_command curl

check_tag() {
    local repo="$1"
    local tag="$2"
    local expected="$3"
    local actual
    actual="$(git ls-remote "$repo" "refs/tags/$tag" | awk '{print $1}')"
    test -n "$actual" || die "tag not found: $repo $tag"
    test "$actual" = "$expected" \
        || die "tag drift for $repo $tag: expected $expected, got $actual"
    printf '[ok] %s %s\n' "$repo" "$tag"
}

check_tag "https://github.com/valkey-io/valkey.git" "$VALKEY_TAG" "$VALKEY_COMMIT"
check_tag "https://github.com/Tongsuo-Project/Tongsuo.git" "$TONGSHUO_VERSION" "$TONGSHUO_COMMIT"
check_tag "https://github.com/krallin/tini.git" "$TINI_TAG" "$TINI_COMMIT"

if command -v crane >/dev/null 2>&1; then
    actual="$(crane digest "$OPENEULER_BASE")"
    test "$actual" = "$OPENEULER_BASE_INDEX_DIGEST" \
        || die "openEuler digest drift: expected $OPENEULER_BASE_INDEX_DIGEST, got $actual"
    printf '[ok] openEuler base digest\n'
else
    printf '[skip] crane unavailable; base digest checked by Docker pull/build\n'
fi
