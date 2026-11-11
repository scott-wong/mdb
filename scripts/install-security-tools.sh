#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

require_command curl
require_command tar
[ "$(uname -s)" = "Linux" ] || die "security tool binaries are Linux-only"
[ "$(uname -m)" = "x86_64" ] || die "security tool binaries are amd64-only"

tools=("$@")
if [ "${#tools[@]}" -eq 0 ]; then
    tools=(cosign syft trivy crane)
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
install_dir="${INSTALL_DIR:-/usr/local/bin}"
mkdir -p "$install_dir"

install_tool() {
    local source="$1"
    local name="$2"
    if [ -w "$install_dir" ]; then
        install -m 0755 "$source" "$install_dir/$name"
    else
        require_command sudo
        sudo install -m 0755 "$source" "$install_dir/$name"
    fi
}

install_binary() {
    local name="$1"
    local url="$2"
    local sha="$3"
    local archive="$tmpdir/$name.download"
    curl --fail --location --retry 5 --retry-all-errors \
        --output "$archive" "$url"
    verify_sha256 "$archive" "$sha"
    case "$name" in
        syft|trivy|crane)
            mkdir -p "$tmpdir/$name"
            tar --extract --gzip --file "$archive" --directory "$tmpdir/$name"
            install_tool "$tmpdir/$name/$name" "$name"
            ;;
        cosign)
            install_tool "$archive" cosign
            ;;
        *)
            die "unsupported security tool: $name"
            ;;
    esac
}

for tool in "${tools[@]}"; do
    case "$tool" in
        cosign) install_binary cosign "$COSIGN_URL" "$COSIGN_SHA256" ;;
        syft) install_binary syft "$SYFT_URL" "$SYFT_SHA256" ;;
        trivy) install_binary trivy "$TRIVY_URL" "$TRIVY_SHA256" ;;
        crane) install_binary crane "$CRANE_URL" "$CRANE_SHA256" ;;
        *) die "unsupported security tool: $tool" ;;
    esac
    printf '[ok] installed %s\n' "$tool"
done
