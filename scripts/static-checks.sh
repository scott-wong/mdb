#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_baseline

version="$(tr -d ' \n' < "$ROOT_DIR/VERSION")"
[[ "$version" =~ ^${VALKEY_VERSION}-mdb\.[0-9]+$ ]] \
    || die "VERSION must be ${VALKEY_VERSION}-mdb.<N>, got: $version"

[[ "$TONGSHUO_VERSION" == "8.5.0" ]] \
    || die "TONGSHUO_VERSION must be the reviewed 8.5.0 baseline"
[[ "$TONGSHUO_OPENSSL_VERSION" == "3.5.4" ]] \
    || die "TONGSHUO_OPENSSL_VERSION must match Tongsuo 8.5.0"
[[ "$OPENEULER_BASE" == *"@$OPENEULER_BASE_INDEX_DIGEST" ]] \
    || die "openEuler tag and digest disagree"

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

while IFS= read -r -d '' script; do
    bash -n "$script"
    case "$script" in
        */docker-entrypoint.sh) ;;
        *)
            [ -x "$script" ] || die "script is not executable: ${script#"$ROOT_DIR"/}"
            ;;
    esac
    printf '[ok] bash %s\n' "${script#"$ROOT_DIR"/}"
done < <(find "$ROOT_DIR/scripts" "$ROOT_DIR/test" "$ROOT_DIR/packaging" \
    -type f -name '*.sh' -print0)

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in root.rglob("*.py"):
    if "distfiles" in path.parts:
        continue
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
    print(f"[ok] python {path.relative_to(root)}")
PY

dockerfile="$ROOT_DIR/packaging/docker/Dockerfile"
[ -f "$dockerfile" ] || die "Dockerfile missing"
grep -q '^CMD \["valkey-server"\]$' "$dockerfile" \
    || die "Dockerfile must preserve the valkey-server CMD"
grep -q '^ENTRYPOINT \["/usr/bin/tini"' "$dockerfile" \
    || die "Dockerfile must use tini as PID 1"
grep -q 'io.mdb.tls.rfc8998="true"' "$dockerfile" \
    || die "Dockerfile must advertise RFC 8998"
grep -q 'io.mdb.tls.tlcp="false"' "$dockerfile" \
    || die "Dockerfile must explicitly exclude TLCP"
! grep -q '^HEALTHCHECK' "$dockerfile" \
    || die "MDB must not define a built-in HEALTHCHECK"
! grep -q 'enable-ntls' "$ROOT_DIR/scripts/build-tongsuo.sh" \
    || die "Tongsuo must not enable NTLS/TLCP"
! grep -q 'enable-weak-ssl-ciphers\|enable-rc5' "$ROOT_DIR/scripts/build-tongsuo.sh" \
    || die "Tongsuo must not enable legacy weak cipher surface"

for alias in server sentinel cli benchmark check-rdb check-aof; do
    grep -q "mdb-$alias" "$ROOT_DIR/scripts/prepare-image.sh" \
        || die "missing mdb-$alias alias"
done

grep -q '^protected-mode no$' "$ROOT_DIR/packaging/config/valkey.conf" \
    || die "default config must preserve the container protected-mode contract"
grep -q '^tls-auth-clients yes$' "$ROOT_DIR/examples/standard.conf" \
    || die "standard TLS must default to mTLS"
grep -q '^tls-auth-clients yes$' "$ROOT_DIR/examples/gm.conf" \
    || die "GM TLS must default to mTLS"

if grep -RInE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*["'\''])' \
    "$ROOT_DIR/README.md" \
    "$ROOT_DIR/examples" \
    "$ROOT_DIR/scripts" \
    "$ROOT_DIR/packaging" \
    "$ROOT_DIR/test" \
    "$ROOT_DIR/docs" 2>/dev/null; then
    die "possible secret material found in tracked project files"
fi

printf 'Static checks passed for MDB %s\n' "$version"
