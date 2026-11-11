# ADR 0004: Zero Valkey source patches in v1

## Status

Accepted.

## Decision

V1 keeps Valkey source unchanged. Tongsuo is selected at compile/link time;
standard and GM behavior is selected through PEM certificates, Valkey config,
and a dedicated `openssl.cnf`.

The GM config uses Tongsuo's SSL_CONF support to set:

```text
MinProtocol = TLSv1.3
MaxProtocol = TLSv1.3
Ciphersuites = TLS_SM4_GCM_SM3
Groups = SM2
SignatureAlgorithms = sm2sig_sm3
Enable_sm_tls13_strict = on
```

If a real handshake demonstrates that Valkey cannot honor one of these settings,
the fallback is a small reviewed patch rather than silently weakening the claim.
