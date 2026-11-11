SHELL := /bin/bash

VERSION := $(shell tr -d ' \n' < VERSION)
UPSTREAM_VERSION := $(firstword $(subst -, ,$(VERSION)))
IMAGE ?= mdb:$(VERSION)-openeuler
PLATFORM ?= linux/amd64
DOCKER ?= docker
CACHE ?= 0
CACHE_REF ?= ghcr.io/scott-wong/mdb:buildcache
CACHE_ARGS :=
ifeq ($(CACHE),1)
CACHE_ARGS := --cache-from type=registry,ref=$(CACHE_REF) --cache-to type=registry,ref=$(CACHE_REF),mode=max
endif

.PHONY: help verify fetch build candidate smoke smoke-standard smoke-gm \
        smoke-replication smoke-sentinel smoke-cluster full-matrix \
        verify-metadata print-build-args release-manifest clean

help:
	@printf 'MDB %s\n' '$(VERSION)'
	@printf '%s\n' \
		'  verify            Run static checks' \
		'  fetch             Download and verify pinned source archives' \
		'  build             Build the local linux/amd64 image' \
		'  candidate         Build and push a candidate image' \
		'  smoke             Standard + GM standalone TLS smoke tests' \
		'  smoke-standard    Standard TLS standalone smoke test' \
		'  smoke-gm          GM standalone smoke test' \
		'  smoke-replication Replication TLS smoke tests' \
		'  smoke-sentinel    Sentinel TLS smoke tests' \
		'  smoke-cluster     Cluster + cluster-bus TLS smoke tests' \
		'  full-matrix       Run every smoke test for both TLS modes' \
		'  verify-metadata   Verify image labels, filesystem and linkage' \
		'  print-build-args  Print immutable Docker build arguments' \
		'  release-manifest  Generate a release manifest for IMAGE' \
		'  clean             Remove downloaded/build artifacts'

verify:
	bash scripts/static-checks.sh

fetch:
	bash scripts/fetch-sources.sh

build: fetch verify
	@set -euo pipefail; \
		source scripts/baseline.env; \
		$(DOCKER) buildx build \
			--platform $(PLATFORM) \
			--build-arg OPENEULER_BASE="$${OPENEULER_BASE}" \
			--build-arg OPENEULER_BASE_DIGEST="$${OPENEULER_BASE_INDEX_DIGEST}" \
			--build-arg MDB_VALKEY_VERSION="$${VALKEY_VERSION}" \
			--build-arg MDB_TONGSHUO_VERSION="$${TONGSHUO_VERSION}" \
			--build-arg MDB_TONGSHUO_OPENSSL_VERSION="$${TONGSHUO_OPENSSL_VERSION}" \
			--build-arg MDB_VERSION="$(VERSION)" \
			$(CACHE_ARGS) \
			--load \
			-t "$(IMAGE)" \
			-f packaging/docker/Dockerfile .

candidate: build
	@set -euo pipefail; \
		$(DOCKER) push "$(IMAGE)"

smoke: smoke-standard smoke-gm

smoke-standard: 
	bash scripts/smoke-standalone.sh "$(IMAGE)" standard

smoke-gm:
	bash scripts/smoke-standalone.sh "$(IMAGE)" gm

smoke-replication:
	bash scripts/smoke-replication.sh "$(IMAGE)" standard
	bash scripts/smoke-replication.sh "$(IMAGE)" gm

smoke-sentinel:
	bash scripts/smoke-sentinel.sh "$(IMAGE)" standard
	bash scripts/smoke-sentinel.sh "$(IMAGE)" gm

smoke-cluster:
	bash scripts/smoke-cluster.sh "$(IMAGE)" standard
	bash scripts/smoke-cluster.sh "$(IMAGE)" gm

full-matrix: smoke smoke-replication smoke-sentinel smoke-cluster

verify-metadata:
	test -n "$(IMAGE)"
	bash scripts/verify-image-metadata.sh "$(IMAGE)"

print-build-args:
	@set -euo pipefail; \
		source scripts/baseline.env; \
		printf 'OPENEULER_BASE=%s\nMDB_VERSION=%s\n' "$${OPENEULER_BASE}" "$(VERSION)"

release-manifest:
	test -n "$(IMAGE)"
	bash scripts/generate-release-manifest.sh "$(IMAGE)"

clean:
	rm -rf distfiles/*.tar.gz artifacts out test/certs/*
