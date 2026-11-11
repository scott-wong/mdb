#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

mkdir -p "$ARTIFACTS_DIR"
image_id="$(docker image inspect "$IMAGE" --format '{{.Id}}')"
created="$(docker image inspect "$IMAGE" --format '{{.Created}}')"
source_commit="${GITHUB_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf unknown)}"
sbom="${SBOM_PATH:-}"
trivy="${TRIVY_PATH:-}"

python3 - "$ARTIFACTS_DIR/release-manifest.json" \
    "$(tr -d ' \n' < "$ROOT_DIR/VERSION")" "$VALKEY_VERSION" \
    "$TONGSHUO_VERSION" "$TONGSHUO_OPENSSL_VERSION" \
    "$OPENEULER_BASE" "$image_id" "$created" "$source_commit" "$sbom" "$trivy" <<'PY'
import json
import pathlib
import sys

(
    output,
    version,
    valkey_version,
    tongsuo_version,
    tongsuo_openssl,
    base,
    image_id,
    created,
    source_commit,
    sbom,
    trivy,
) = sys.argv[1:]

data = {
    "product": "MDB",
    "version": version,
    "upstream": {
        "valkey": valkey_version,
        "tongsuo": tongsuo_version,
        "tongsuo_openssl_baseline": tongsuo_openssl,
    },
    "base_image": base,
    "image_id": image_id,
    "created": created,
    "source_commit": source_commit,
    "sbom": sbom or None,
    "trivy": trivy or None,
    "platform": "linux/amd64",
    "tls": {
        "standard": "TLSv1.2+TLSv1.3",
        "gm": "RFC8998 TLSv1.3 SM2/SM3/SM4-GCM",
        "tlcp": False,
    },
}
pathlib.Path(output).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

printf '[ok] wrote %s\n' "$ARTIFACTS_DIR/release-manifest.json"
