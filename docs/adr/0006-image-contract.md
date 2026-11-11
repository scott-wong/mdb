# ADR 0006: Container runtime contract

## Status

Accepted.

## Decision

- openEuler 24.03 LTS SP4, `linux/amd64`.
- UID/GID 999 for the Valkey process.
- `/data` is `0770`; `/run/mdb` is `0700`.
- `tini` is PID 1 and the entrypoint performs root → 999 demotion.
- Default CMD remains `valkey-server`; a bare invocation receives the MDB
  default config at `/usr/local/etc/mdb/valkey.conf`.
- TLS is opt-in and the default config preserves the container-friendly
  `protected-mode no` behavior without patching Valkey source.
