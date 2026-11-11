# ADR 0007: Sentinel TLS boundary

## Status

Accepted.

## Decision

Upstream Sentinel exposes its client control port as plaintext and uses TLS for
outbound links to monitored Valkey instances when `tls-replication yes` is set.
MDB tests that outbound TLS path and documents it explicitly.

MDB does not claim an encrypted Sentinel control API. Deployments that require
one must use an external TLS terminator or a separately reviewed Sentinels
implementation.
