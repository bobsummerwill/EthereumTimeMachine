# Vast.ai single-node Homestead (pre-DAO) chain extender.
#
# This image:
# - runs geth v1.3.6 (Homestead-era)
# - runs ethminer (CUDA) against geth's JSON-RPC getwork API
# - optionally bootstraps the geth datadir from a provided tarball
#
# Notes:
# - Base image includes NVIDIA CUDA tooling; run with `--gpus all`.
# - We intentionally keep this self-contained (no docker-compose required on Vast).

FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

SHELL ["/bin/bash", "-lc"]

ARG DEBIAN_FRONTEND=noninteractive
ARG GETH_VERSION=v1.3.6
ARG ETHMINER_REF=v0.19.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl wget \
    bzip2 xz-utils \
    python3 \
    libfaketime \
    tini \
  && rm -rf /var/lib/apt/lists/*

# --- Install geth v1.3.6 (prebuilt binary from historical GitHub release asset) ---
RUN set -euo pipefail; \
  tmpdir="$(mktemp -d)"; \
  cd "$tmpdir"; \
  wget -O geth.tar "https://github.com/ethereum/go-ethereum/releases/download/${GETH_VERSION}/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2"; \
  # Historical assets sometimes vary in content-encoding; attempt a few extraction strategies.
  if bzip2 -t geth.tar >/dev/null 2>&1; then \
    tar -xjf geth.tar; \
  elif tar -xzf geth.tar >/dev/null 2>&1; then \
    true; \
  else \
    tar -xf geth.tar; \
  fi; \
  GETH_BIN="$(find . -maxdepth 3 -type f -name geth | head -n 1)"; \
  test -n "$GETH_BIN"; \
  install -m 0755 "$GETH_BIN" /usr/local/bin/geth; \
  rm -rf "$tmpdir"; \
  geth version || true

## NOTE: We do NOT embed a GPU miner binary.
##
## Reason: the classic open-source Ethash miner (`ethminer`) is archived and its
## build system relies on Hunter/Boost downloads from Bintray, which is defunct.
##
## Instead, this image runs geth v1.3.6 and executes a user-supplied miner command
## (mounted into the container) that supports JSON-RPC "getwork".

RUN mkdir -p /data /input

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY mining_controller.py /usr/local/bin/mining_controller.py
COPY geth_time_stepper.py /usr/local/bin/geth_time_stepper.py
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV GETH_RPC_ADDR=0.0.0.0
ENV GETH_RPC_PORT=8545
ENV GETH_P2P_PORT=30303
ENV GETH_NETWORK_ID=1
ENV GETH_CACHE=2048

# Optional: "lie" about wall-clock time so geth proposes large timestamp deltas
# without real waiting. This affects the timestamp placed into the work package.
ENV USE_FAKETIME=1
ENV FAKETIME_MODE=step
ENV FAKETIME_STEP_SECONDS=1200
ENV FAKETIME="@0"
ENV FAKETIME_NO_CACHE=1

# If provided, container will extract this tar into /data on first boot.
# Expected: tar contains the geth datadir root (e.g. includes `chaindata/` for v1.3.6).
ENV CHAIN_DATA_TAR=/input/chaindata.tar

# If unset, the entrypoint will create an account on first run.
ENV ETHERBASE=
ENV ACCOUNT_PASSWORD=dev

# Miner launcher (you provide the binary/command).
# Example (if you mount an ethminer binary into /input/ethminer):
#   MINER_CMD='/input/ethminer -U -F http://127.0.0.1:8545'
ENV MINER_CMD=

# If set (>0), pause mining after each found block to maximize timestamp delta and
# accelerate the Homestead difficulty drop (delta >= ~1000s triggers max downward adjustment).
ENV PAUSE_BETWEEN_BLOCKS_SECONDS=0

EXPOSE 8545 30303

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
