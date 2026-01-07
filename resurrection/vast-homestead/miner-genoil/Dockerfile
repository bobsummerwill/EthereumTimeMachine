# Genoil cpp-ethereum ethminer container
#
# This builds Genoil's ethminer from source on an **Ubuntu 14.04 (2014/2015-era)** build image
# (to match the historical toolchain expectations), then copies the resulting binary into a
# modern CUDA runtime image for execution on Vast.
#
# NOTE: Genoil/cpp-ethereum is unmaintained and the build can be fragile.
# We keep this as a separate container so you can iterate on the toolchain without
# touching the geth container.

FROM ubuntu:14.04 AS build

SHELL ["/bin/bash", "-lc"]

ARG DEBIAN_FRONTEND=noninteractive
ARG GENOIL_REPO=https://github.com/Genoil/cpp-ethereum.git
ARG GENOIL_REF=master

RUN sed -i 's|http://archive.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list \
  && sed -i 's|http://security.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git \
    software-properties-common \
    cmake build-essential pkg-config \
    libboost-all-dev \
    libjsoncpp-dev \
    libjson-rpc-cpp-dev \
    libcrypto++-dev \
    libleveldb-dev \
    libgmp-dev \
    libreadline-dev \
    libcurl4-gnutls-dev \
    ocl-icd-libopencl1 opencl-headers \
    mesa-common-dev \
    libmicrohttpd-dev \
  && rm -rf /var/lib/apt/lists/*

# Build ethminer (Genoil).
RUN set -euo pipefail; \
  git clone --depth 1 --branch "$GENOIL_REF" "$GENOIL_REPO" /src/cpp-ethereum; \
  mkdir -p /src/cpp-ethereum/build /out; \
  cd /src/cpp-ethereum/build; \
  cmake -DBUNDLE=miner ..; \
  make -j"$(nproc)"; \
  install -m 0755 /src/cpp-ethereum/build/ethminer/ethminer /out/ethminer; \
  rm -rf /src/cpp-ethereum

FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

SHELL ["/bin/bash", "-lc"]

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates python3 tini procps \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/ethminer /usr/local/bin/ethminer
RUN chmod +x /usr/local/bin/ethminer

COPY mining_controller.py /usr/local/bin/mining_controller.py
COPY miner-genoil/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV GETH_RPC_URL=http://geth:8545
# Default: pause after each mined block so the next block has a large timestamp delta.
# This helps crash difficulty on Homestead when you have time and want to minimize GPU-hours.
ENV PAUSE_BETWEEN_BLOCKS_SECONDS=0

# Default miner args:
# -G OpenCL
# -F getwork endpoint
ENV ETHMINER_ARGS=-G\ -F\ http://geth:8545

# Health check: verify ethminer process is running
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD pgrep -x ethminer > /dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
