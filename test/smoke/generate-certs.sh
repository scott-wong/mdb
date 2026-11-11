#!/usr/bin/env bash
set -euo pipefail

out="${1:?output directory is required}"
openssl="${OPENSSL_BIN:-/opt/tongsuo/bin/openssl}"
test -x "$openssl"

rm -rf "$out"
mkdir -p "$out/standard" "$out/gm"

san="DNS:localhost,DNS:mdb-standard,DNS:mdb-gm,DNS:mdb-node1,DNS:mdb-node2,DNS:mdb-node3,DNS:mdb-node4,DNS:mdb-node5,DNS:mdb-node6,IP:127.0.0.1,IP:172.28.0.10,IP:172.28.0.11,IP:172.28.0.12,IP:172.28.0.13,IP:172.28.0.14,IP:172.28.0.15,IP:172.28.0.16"

cat >"$out/standard-server.ext" <<EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = $san
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat >"$out/standard-client.ext" <<EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = clientAuth,serverAuth
subjectAltName = DNS:mdb-client
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat >"$out/gm-server.ext" <<EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,nonRepudiation
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = $san
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat >"$out/gm-client.ext" <<EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,nonRepudiation
extendedKeyUsage = clientAuth,serverAuth
subjectAltName = DNS:mdb-client
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

make_standard_ca() {
    local dir="$1"
    "$openssl" ecparam -genkey -name prime256v1 -out "$dir/ca.key"
    "$openssl" req -x509 -new -sha256 -key "$dir/ca.key" \
        -subj "/CN=MDB Standard Test CA" -days 30 \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -out "$dir/ca.crt"
}

make_standard_cert() {
    local dir="$1"
    local role="$2"
    local ext="$3"
    "$openssl" ecparam -genkey -name prime256v1 -out "$dir/$role.key"
    "$openssl" req -new -sha256 -key "$dir/$role.key" \
        -subj "/CN=MDB $role" -out "$dir/$role.csr"
    "$openssl" x509 -req -sha256 -in "$dir/$role.csr" \
        -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial \
        -days 30 -extfile "$out/$ext" -out "$dir/$role.crt"
}

make_gm_ca() {
    local dir="$1"
    "$openssl" ecparam -genkey -name SM2 -out "$dir/ca.key"
    "$openssl" req -x509 -new -sm3 -key "$dir/ca.key" \
        -subj "/CN=MDB GM Test CA" -days 30 \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -out "$dir/ca.crt"
}

make_gm_cert() {
    local dir="$1"
    local role="$2"
    local ext="$3"
    "$openssl" ecparam -genkey -name SM2 -out "$dir/$role.key"
    "$openssl" req -new -sm3 -key "$dir/$role.key" \
        -subj "/CN=MDB $role" -out "$dir/$role.csr"
    "$openssl" x509 -req -sm3 -in "$dir/$role.csr" \
        -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial \
        -days 30 -extfile "$out/$ext" -out "$dir/$role.crt"
}

make_standard_ca "$out/standard"
make_standard_cert "$out/standard" server standard-server.ext
make_standard_cert "$out/standard" client standard-client.ext

make_gm_ca "$out/gm"
make_gm_cert "$out/gm" server gm-server.ext
make_gm_cert "$out/gm" client gm-client.ext

"$openssl" verify -CAfile "$out/standard/ca.crt" \
    "$out/standard/server.crt" "$out/standard/client.crt" >/dev/null
"$openssl" verify -CAfile "$out/gm/ca.crt" \
    "$out/gm/server.crt" "$out/gm/client.crt" >/dev/null

"$openssl" x509 -in "$out/gm/server.crt" -noout -text \
    | grep -q 'Signature Algorithm: SM2-with-SM3'
"$openssl" x509 -in "$out/gm/server.crt" -noout -text \
    | grep -q 'ASN1 OID: SM2'

rm -f "$out"/*.ext "$out"/*.srl
printf '[certs] generated standard and GM certificate sets in %s\n' "$out"
