# syntax=docker/dockerfile:1.7
#
# MDB is a single openEuler/amd64 image: Valkey core built against a private
# Tongsuo runtime, with standard TLS and RFC 8998 TLS 1.3 national-cryptography
# profiles. TLCP/NTLS is intentionally not built.

ARG OPENEULER_BASE=quay.io/openeuler/openeuler:24.03-lts-sp4@sha256:17c15554be2a5bc46023acb6e04d609d77642b8c20e236e88deb18e41ae4558e

FROM ${OPENEULER_BASE} AS builder

ENV DISTRO=openeuler
WORKDIR /opt/mdb

COPY scripts/ /opt/mdb/scripts/
COPY distfiles/ /opt/mdb/distfiles/

RUN bash /opt/mdb/scripts/install-build-deps.sh
RUN bash /opt/mdb/scripts/build-tongsuo.sh
RUN bash /opt/mdb/scripts/build-valkey.sh
RUN bash /opt/mdb/scripts/build-tini.sh

FROM ${OPENEULER_BASE} AS final

ARG MDB_VERSION=9.1.3-mdb.1

LABEL org.opencontainers.image.title="MDB" \
      org.opencontainers.image.description="MDB, an openEuler Valkey distribution with Tongsuo RFC 8998 TLS" \
      org.opencontainers.image.version="${MDB_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0 AND BSD-3-Clause" \
      org.opencontainers.image.source="https://github.com/scott-wong/mdb" \
      org.opencontainers.image.base.name="quay.io/openeuler/openeuler:24.03-lts-sp4" \
      org.opencontainers.image.base.digest="sha256:17c15554be2a5bc46023acb6e04d609d77642b8c20e236e88deb18e41ae4558e" \
      org.opencontainers.image.vendor="MDB" \
      io.mdb.valkey.version="9.1.3" \
      io.mdb.tongsuo.version="8.5.0" \
      io.mdb.tongsuo.openssl-baseline="3.5.4" \
      io.mdb.tls.rfc8998="true" \
      io.mdb.tls.tlcp="false" \
      io.mdb.tls.modes="standard,gm" \
      io.mdb.runtime-user="999"

ENV PATH=/opt/tongsuo/bin:/usr/local/bin:$PATH \
    MDB_TLS_MODE=off

WORKDIR /data

COPY scripts/install-runtime-deps.sh scripts/configure-openeuler-repo.sh /opt/mdb/scripts/
COPY scripts/prepare-image.sh /opt/mdb/scripts/
COPY packaging/docker/docker-entrypoint.sh /usr/local/bin/mdb-entrypoint
COPY packaging/config/ /usr/local/etc/mdb/
COPY packaging/openssl/standard.cnf /usr/local/etc/mdb/openssl-standard.cnf
COPY packaging/openssl/gm.cnf /usr/local/etc/mdb/openssl-gm.cnf
COPY examples/ /usr/local/share/mdb/examples/
COPY LICENSE /usr/local/share/mdb/licenses/LICENSE
COPY THIRD_PARTY_NOTICES.md /usr/local/share/mdb/licenses/THIRD_PARTY_NOTICES.md
COPY licenses/ /usr/local/share/mdb/licenses/
RUN bash /opt/mdb/scripts/install-runtime-deps.sh

COPY --from=builder /opt/tongsuo /opt/tongsuo
COPY --from=builder /usr/local/bin/valkey-server /usr/local/bin/valkey-server
COPY --from=builder /usr/local/bin/valkey-sentinel /usr/local/bin/valkey-sentinel
COPY --from=builder /usr/local/bin/valkey-cli /usr/local/bin/valkey-cli
COPY --from=builder /usr/local/bin/valkey-benchmark /usr/local/bin/valkey-benchmark
COPY --from=builder /usr/local/bin/valkey-check-rdb /usr/local/bin/valkey-check-rdb
COPY --from=builder /usr/local/bin/valkey-check-aof /usr/local/bin/valkey-check-aof
COPY --from=builder /opt/mdb/tini/bin/tini-static /usr/bin/tini

RUN find /opt/tongsuo -type f \( -name '*.h' -o -name '*.a' -o -name '*.pc' \) -delete \
    && rm -rf /opt/tongsuo/include /opt/tongsuo/share/man /opt/tongsuo/share/doc \
    && VALKEY_VERSION=9.1.3 TONGSHUO_VERSION=8.5.0 \
       bash /opt/mdb/scripts/prepare-image.sh "$MDB_VERSION" \
    && rm -rf /opt/mdb

EXPOSE 6379
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/mdb-entrypoint"]
CMD ["valkey-server"]
