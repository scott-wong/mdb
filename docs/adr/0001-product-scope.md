# ADR 0001: Product scope

## Status

Accepted.

## Decision

MDB is a Valkey core distribution, not a new storage engine. It packages the
upstream Valkey server with a private Tongsuo runtime, openEuler base, hardened
container defaults, and verifiable releases.

## Non-goals

- Valkey Search, JSON, Bloom or other modules.
- A proxy, control plane, Operator, Helm chart or managed-service API.
- A long-lived fork of Valkey source.
- RPM/DEB or standalone binary delivery.
