#!/usr/bin/env bash
#
# Build OpenCL-only ethminer suitable for Ampere GPUs on Vast instances.
# This avoids CUDA crashes seen with prebuilt binaries.
#
# Usage (on the Vast instance):
#   chmod +x install-ethminer-opencl.sh
#   ./install-ethminer-opencl.sh
#
# Resulting binary: /root/ethminer-src/build/ethminer/ethminer
# Default log path expected by vast-mining.sh: /root/ethminer.log

set -euo pipefail

ETHMINER_REPO="https://github.com/ethereum-mining/ethminer.git"
ETHMINER_DIR="/root/ethminer-src"
CMAKE_VERSION="3.27.9"
CMAKE_TARBALL="cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${CMAKE_TARBALL}"
CMAKE_DIR="/root/cmake-${CMAKE_VERSION}-linux-x86_64"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Installing prerequisites (OpenCL headers, build tools)..."
apt-get update -qq
apt-get install -y -qq git build-essential ocl-icd-opencl-dev curl

if [ ! -x "${CMAKE_DIR}/bin/cmake" ]; then
  log "Fetching portable CMake ${CMAKE_VERSION}..."
  cd /root
  rm -f "${CMAKE_TARBALL}"
  curl -L -o "${CMAKE_TARBALL}" "${CMAKE_URL}"
  tar xzf "${CMAKE_TARBALL}"
fi

if [ ! -d "${ETHMINER_DIR}" ]; then
  log "Cloning ethminer..."
  git clone --depth 1 "${ETHMINER_REPO}" "${ETHMINER_DIR}"
else
  log "ethminer repo already exists, pulling latest..."
  git -C "${ETHMINER_DIR}" pull --ff-only
fi

cd "${ETHMINER_DIR}"
log "Updating submodules..."
git submodule update --init --recursive

# Hunter Boost mirror: use p0 release to avoid JFrog 409/redirects.
HUNTER_CFG="${ETHMINER_DIR}/cmake/Hunter/config.cmake"
if ! grep -q "Boost VERSION 1.66.0-p0" "${HUNTER_CFG}"; then
  log "Setting Hunter Boost version to 1.66.0-p0..."
  sed -i 's/Boost VERSION 1.66.0/Boost VERSION 1.66.0-p0/' "${HUNTER_CFG}"
fi

log "Configuring ethminer (OpenCL only)..."
mkdir -p build
cd build
"${CMAKE_DIR}/bin/cmake" .. \
  -DETHASHCUDA=OFF \
  -DETHASHCL=ON \
  -DETHASHCPU=OFF \
  -DCMAKE_BUILD_TYPE=Release

log "Building ethminer..."
"${CMAKE_DIR}/bin/cmake" --build . --target ethminer -- -j"$(nproc)"

log "ethminer built at: ${ETHMINER_DIR}/build/ethminer/ethminer"
log "Example run: ${ETHMINER_DIR}/build/ethminer/ethminer -G -P http://127.0.0.1:8545 --HWMON 1 --report-hr --dag-load-mode 1"
