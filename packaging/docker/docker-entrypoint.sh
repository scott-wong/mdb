#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[mdb-entrypoint] %s\n' "$*" >&2
}

die() {
    printf '[mdb-entrypoint] ERROR: %s\n' "$*" >&2
    exit 1
}

mode="${MDB_TLS_MODE:-off}"
case "$mode" in
    off|standard|gm) ;;
    *) die "MDB_TLS_MODE must be off, standard or gm; got: $mode" ;;
esac
export MDB_TLS_MODE="$mode"

# Preserve the official image ergonomics: a bare command, a command beginning
# with '-' and a bare .conf path all mean valkey-server. A bare server command
# gets the MDB default config.
if [ "$#" -eq 0 ]; then
    set -- valkey-server
fi
case "${1#-}" in
    "$1")
        ;;
    *)
        set -- valkey-server "$@"
        ;;
esac
if [ "${1%.conf}" != "$1" ]; then
    set -- valkey-server "$@"
fi
case "$1" in
    mdb-server)
        shift
        set -- valkey-server "$@"
        ;;
esac
if [ "$1" = "valkey-server" ] && [ "$#" -eq 1 ]; then
    set -- valkey-server /usr/local/etc/mdb/valkey.conf
fi

if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0770 -o 999 -g 999 /data
    install -d -m 0700 -o 999 -g 999 /run/mdb
    install -d -m 0750 -o root -g 999 /etc/mdb/tls
fi

config_file=""
for arg in "$@"; do
    case "$arg" in
        *.conf)
            config_file="$arg"
            ;;
    esac
done

if [ "$mode" = "off" ] && [ -n "$config_file" ] && [ -r "$config_file" ]; then
    if grep -Eq '^[[:space:]]*tls-port[[:space:]]+[1-9][0-9]*[[:space:]]*$' "$config_file"; then
        die "TLS is enabled by $config_file but MDB_TLS_MODE is off"
    fi
fi

if [ "$mode" != "off" ]; then
    test -r /etc/mdb/tls/server.crt || die "missing /etc/mdb/tls/server.crt"
    test -r /etc/mdb/tls/server.key || die "missing /etc/mdb/tls/server.key"
    test -r /etc/mdb/tls/ca.crt || die "missing /etc/mdb/tls/ca.crt"

    install -d -m 0700 -o 999 -g 999 /run/mdb/tls
    install -m 0444 -o 999 -g 999 /etc/mdb/tls/server.crt /run/mdb/tls/server.crt
    install -m 0400 -o 999 -g 999 /etc/mdb/tls/server.key /run/mdb/tls/server.key
    install -m 0444 -o 999 -g 999 /etc/mdb/tls/ca.crt /run/mdb/tls/ca.crt
    if [ -r /etc/mdb/tls/client.crt ] || [ -r /etc/mdb/tls/client.key ]; then
        test -r /etc/mdb/tls/client.crt || die "client.crt exists without readable client.key"
        test -r /etc/mdb/tls/client.key || die "client.key exists without readable client.crt"
        install -m 0444 -o 999 -g 999 /etc/mdb/tls/client.crt /run/mdb/tls/client.crt
        install -m 0400 -o 999 -g 999 /etc/mdb/tls/client.key /run/mdb/tls/client.key
    fi

    openssl=/opt/tongsuo/bin/openssl
    test -x "$openssl" || die "Tongsuo openssl is missing"

    "$openssl" x509 -in /run/mdb/tls/server.crt -noout -checkend 0 >/dev/null \
        || die "server certificate is expired or invalid"
    "$openssl" verify -CAfile /run/mdb/tls/ca.crt /run/mdb/tls/server.crt >/dev/null \
        || die "server certificate does not verify against ca.crt"

    cert_pub="$("$openssl" x509 -in /run/mdb/tls/server.crt -pubkey -noout \
        | "$openssl" pkey -pubin -outform DER 2>/dev/null \
        | "$openssl" dgst -sha256)"
    key_pub="$("$openssl" pkey -in /run/mdb/tls/server.key -pubout -outform DER 2>/dev/null \
        | "$openssl" dgst -sha256)"
    test "$cert_pub" = "$key_pub" || die "server certificate and private key do not match"

    if [ -r /run/mdb/tls/client.crt ]; then
        "$openssl" verify -CAfile /run/mdb/tls/ca.crt /run/mdb/tls/client.crt >/dev/null \
            || die "client certificate does not verify against ca.crt"
        client_cert_pub="$("$openssl" x509 -in /run/mdb/tls/client.crt -pubkey -noout \
            | "$openssl" pkey -pubin -outform DER 2>/dev/null \
            | "$openssl" dgst -sha256)"
        client_key_pub="$("$openssl" pkey -in /run/mdb/tls/client.key -pubout -outform DER 2>/dev/null \
            | "$openssl" dgst -sha256)"
        test "$client_cert_pub" = "$client_key_pub" \
            || die "client certificate and private key do not match"
    fi

    server_text="$("$openssl" x509 -in /run/mdb/tls/server.crt -noout -text)"
    if [ "$mode" = "gm" ]; then
        grep -q 'Signature Algorithm: SM2-with-SM3' <<<"$server_text" \
            || die "GM mode requires an SM2-with-SM3 certificate"
        grep -q 'ASN1 OID: SM2' <<<"$server_text" \
            || die "GM mode requires an SM2 public key"
    else
        if grep -q 'SM2-with-SM3' <<<"$server_text"; then
            die "standard mode must not use an SM2 certificate"
        fi
    fi

    if [ -n "$config_file" ] && [ -r "$config_file" ]; then
        if [ "$mode" = "gm" ]; then
            grep -q 'TLS_SM4_GCM_SM3' "$config_file" \
                || die "GM mode config must select TLS_SM4_GCM_SM3"
        elif grep -q 'TLS_SM4_GCM_SM3' "$config_file"; then
            die "standard mode config must not select a GM ciphersuite"
        fi
    fi

    export OPENSSL_CONF="/usr/local/etc/mdb/openssl-${mode}.cnf"
    printf '%s\n' "$mode" > /run/mdb/tls-mode
    chmod 0644 /run/mdb/tls-mode
else
    unset OPENSSL_CONF || true
fi

if [ "$(id -u)" -eq 0 ]; then
    command -v setpriv >/dev/null 2>&1 || die "setpriv is required"
    exec setpriv --reuid=999 --regid=999 --clear-groups -- "$@"
fi

exec "$@"
