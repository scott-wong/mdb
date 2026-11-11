#!/usr/bin/env bash
# Select an openEuler 24.03 LTS SP4 RPM mirror. Package signatures are still
# enforced with the key shipped in the base image.
set -euo pipefail

RELEASE="openEuler-24.03-LTS-SP4"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
    arm64) ARCH=aarch64 ;;
esac
GPG_KEY="${GPG_KEY:-/etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler}"
REPO_FILE="${REPO_FILE:-/etc/yum.repos.d/openEuler.repo}"
MIRRORS=(
    "${OPENEULER_MIRROR:-https://mirrors.xtom.de/openeuler}"
    "https://mirror.accum.se/mirror/openeuler.org"
    "https://repo.openeuler.org"
)

test -r "$GPG_KEY" || {
    echo "ERROR: openEuler GPG key missing: $GPG_KEY" >&2
    exit 1
}

selected=""
for mirror in "${MIRRORS[@]}"; do
    mirror="${mirror%/}"
    case "$mirror" in
        https://*) ;;
        *)
            echo "ERROR: openEuler mirror must use HTTPS: $mirror" >&2
            exit 1
            ;;
    esac

    probe="$mirror/$RELEASE/OS/$ARCH/repodata/repomd.xml"
    echo "[repo] probing $mirror"
    if curl --fail --silent --show-error --location \
        --connect-timeout 8 --max-time 20 --output /dev/null "$probe"; then
        selected="$mirror"
        break
    fi
    echo "[repo] unavailable, trying next mirror" >&2
done

test -n "$selected" || {
    echo "ERROR: no usable openEuler RPM mirror" >&2
    exit 1
}

repo_tmp="$(mktemp)"
trap 'rm -f "$repo_tmp"' EXIT
cat >"$repo_tmp" <<EOF
[OS]
name=OS
baseurl=$selected/$RELEASE/OS/$ARCH/
enabled=1
gpgcheck=1
gpgkey=file://$GPG_KEY
metadata_expire=1h
skip_if_unavailable=False

[everything]
name=everything
baseurl=$selected/$RELEASE/everything/$ARCH/
enabled=1
gpgcheck=1
gpgkey=file://$GPG_KEY
metadata_expire=1h
skip_if_unavailable=False

[EPOL]
name=EPOL
baseurl=$selected/$RELEASE/EPOL/main/$ARCH/
enabled=1
gpgcheck=1
gpgkey=file://$GPG_KEY
metadata_expire=1h
skip_if_unavailable=False

[update]
name=update
baseurl=$selected/$RELEASE/update/$ARCH/
enabled=1
gpgcheck=1
gpgkey=file://$GPG_KEY
metadata_expire=1h
skip_if_unavailable=False
EOF

install -m 0644 "$repo_tmp" "$REPO_FILE"
echo "[repo] selected $selected"
