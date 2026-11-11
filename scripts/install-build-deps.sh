#!/usr/bin/env bash
# Install only build-stage packages. The final image cannot contain any of the
# compilers or headers installed here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/configure-openeuler-repo.sh"

dnf -y --setopt=max_parallel_downloads=10 makecache
dnf -y --setopt=install_weak_deps=False \
    --setopt=max_parallel_downloads=10 install \
    binutils bzip2 ca-certificates cmake curl diffutils findutils gawk gcc gcc-c++ \
    git gzip make patch perl perl-Digest-SHA perl-FindBin perl-IPC-Cmd perl-Pod-Html \
    pkgconf procps-ng tar which xz zlib-devel
dnf clean all
rm -rf /var/cache/dnf

for command in gcc g++ make perl cmake tar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "ERROR: missing build command: $command" >&2
        exit 1
    }
done
