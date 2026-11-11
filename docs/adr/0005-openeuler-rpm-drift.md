# ADR 0005: openEuler RPM drift

## Status

Accepted.

## Decision

The base image is pinned by index digest, but RPMs are resolved from signed
openEuler repositories at build time and `dnf upgrade --security` is applied.
Consequently, rebuilding the same git commit on different dates is not
byte-for-byte reproducible.

Every release records the actual RPM set in the SBOM and
`/usr/local/share/mdb/rpm-manifest.txt`. Byte-level reproducibility is not
claimed.
