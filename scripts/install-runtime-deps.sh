#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/configure-openeuler-repo.sh"

dnf -y --setopt=max_parallel_downloads=10 makecache
dnf -y --setopt=install_weak_deps=False \
    --setopt=max_parallel_downloads=10 upgrade --security
dnf -y --setopt=install_weak_deps=False \
    --setopt=max_parallel_downloads=10 install \
    ca-certificates findutils libgcc shadow-utils util-linux
dnf clean all
rm -rf /var/cache/dnf

if command -v gcc >/dev/null 2>&1 || command -v make >/dev/null 2>&1; then
    echo "ERROR: final image leaked compiler/build tools" >&2
    exit 1
fi
