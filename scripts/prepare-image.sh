#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?version is required}"

groupadd -r -g 999 valkey 2>/dev/null || true
useradd -r -u 999 -g valkey -M -d /data -s /sbin/nologin valkey 2>/dev/null || true

install -d -m 0770 -o 999 -g 999 /data
install -d -m 0700 -o 999 -g 999 /run/mdb
install -d -m 0755 -o root -g root /usr/local/share/mdb
install -d -m 0755 -o root -g root /usr/local/share/mdb/licenses
install -d -m 0750 -o root -g 999 /etc/mdb/tls

# mdb-server mdb-sentinel mdb-cli mdb-benchmark mdb-check-rdb mdb-check-aof
for tool in server sentinel cli benchmark check-rdb check-aof; do
    test -e "/usr/local/bin/valkey-$tool" || {
        echo "ERROR: missing valkey-$tool" >&2
        exit 1
    }
    cat > "/usr/local/bin/mdb-$tool" <<EOF
#!/bin/sh
exec /usr/local/bin/valkey-$tool "\$@"
EOF
    chmod 0755 "/usr/local/bin/mdb-$tool"
done

chmod 0755 /usr/local/bin/mdb-entrypoint

rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | LC_ALL=C sort > /usr/local/share/mdb/rpm-manifest.txt
printf 'MDB_VERSION=%s\n' "$VERSION" > /usr/local/share/mdb/version.txt
printf 'VALKEY_VERSION=%s\nTONGSHUO_VERSION=%s\n' \
    "${VALKEY_VERSION:-9.1.3}" "${TONGSHUO_VERSION:-8.5.0}" \
    >> /usr/local/share/mdb/version.txt

test ! -e /usr/local/bin/redis-server
test ! -e /usr/local/bin/redis-cli
