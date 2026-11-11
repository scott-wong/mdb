# ADR 0003: One certificate identity per Valkey listener

## Status

Accepted.

## Context

Valkey loads one server certificate and one private key into its TLS context.
Unlike APISIX/OpenResty, it has no SNI certificate callback or dual identity
configuration.

## Decision

The image supports two mutually exclusive TLS profiles. It does not patch Valkey
to add a certificate callback. Deployments that need standard and SM2 clients
simultaneously run two processes/ports or terminate TLS outside MDB.
