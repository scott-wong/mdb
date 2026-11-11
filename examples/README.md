# MDB examples

All examples use `/run/mdb/tls` because the entrypoint stages read-only
`/etc/mdb/tls` material into a process-readable directory owned by UID/GID 999.

- `standard.conf`: standard TLS 1.2/1.3, mTLS required.
- `standard-server-auth.conf`: standard TLS, client certificates optional.
- `gm.conf`: RFC 8998 TLS 1.3, SM2 certificate, mTLS required.
- `cluster-*.conf`: cluster and cluster-bus TLS settings.
- `sentinel-*.conf`: Sentinel TLS skeletons.

The image does not generate certificates or private keys. Generate them in your
PKI or test environment and mount them read-only at `/etc/mdb/tls`.
