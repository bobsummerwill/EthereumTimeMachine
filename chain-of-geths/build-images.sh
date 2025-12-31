#!/bin/bash

# Script to build Docker images for Geth versions
# Run this after creating the Dockerfiles for each version

set -e

# Create Dockerfile for each version
create_dockerfile() {
    local version=$1
    local out_file=$2

    cat > "$out_file" << EOF
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget bzip2 xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Download and install geth binary
EOF
	case $version in
		v1.0.0|v1.0.1|v1.0.2|v1.0.3)
	            # Build from source: no maintained prebuilt Linux binaries for these very early releases.
	            # We compile using a downloaded Go 1.4.x toolchain (DockerHub no longer serves schema1 images like golang:1.4).
	            cat > "$out_file" << 'EOF'
# Use an older Debian toolchain for compatibility with the Go 1.4 CGO toolchain.
# Newer GCC/binutils combinations can emit DWARF that Go 1.4 fails to parse.
FROM debian:jessie-slim AS build

# Debian jessie is EOL; use the Debian archive.
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list \
    && sed -i 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list \
    && sed -i '/jessie-updates/d' /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until \
    && echo 'Acquire::AllowInsecureRepositories "true";' > /etc/apt/apt.conf.d/99allow-insecure \
    && echo 'Acquire::AllowDowngradeToInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99allow-insecure

RUN apt-get update \
    && apt-get install -y --no-install-recommends --allow-unauthenticated ca-certificates curl git make gcc g++ libc6-dev m4 bzip2 libgmp-dev \
    && rm -rf /var/lib/apt/lists/*

# Install a Go 1.4 toolchain from upstream tarball.
# Pick a version that was already stable by July 2015.
# Note: Go 1.4 era Docker images are schema1 and cannot be pulled on modern Docker.
ARG GO_VERSION=1.4.2
RUN curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm -f /tmp/go.tgz

ENV PATH=/usr/local/go/bin:$PATH
ENV GOPATH=/go

WORKDIR /go/src/github.com/ethereum/go-ethereum
RUN git clone https://github.com/ethereum/go-ethereum.git . \
    && git checkout __GETH_TAG__

# Build logs for debugging/reproducibility
RUN echo "[build] go version: $(go version)" \
    && echo "[build] git rev:   $(git rev-parse --short HEAD)" \
    && echo "[build] git tag:   __GETH_TAG__"

# IMPORTANT: Go 1.4's cgo DWARF parser is brittle with modern GCC output.
# Use an older distro toolchain (jessie, GCC 4.9) and keep DWARFv2.
RUN env \
      CGO_CFLAGS="-O2 -g -gdwarf-2" \
      make geth \
    && mkdir -p /out \
    && install -m 0755 build/bin/geth /out/geth \
    && /out/geth version || true

FROM debian:bullseye-slim

RUN apt-get update \
    # Include curl so the self-watchdog can query JSON-RPC even on very old geth builds.
    && apt-get install -y --no-install-recommends ca-certificates libgmp10 curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/geth /usr/local/bin/geth
RUN chmod +x /usr/local/bin/geth

RUN mkdir -p /data

EXPOSE 8545 30303

ENTRYPOINT ["geth"]
EOF
	            # Substitute the requested tag into the Dockerfile template.
	            sed -i "s/__GETH_TAG__/${version}/g" "$out_file"
			;;
		v1.11.6)
            cat >> "$out_file" << 'EOF'
RUN wget -O /tmp/geth.tar.gz https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.11.6-ea9e62ca.tar.gz && \
    tar -xzf /tmp/geth.tar.gz -C /tmp && \
    mv /tmp/geth-linux-amd64-1.11.6-ea9e62ca/geth /usr/local/bin/geth && \
    rm -rf /tmp/*
EOF
			;;
		v1.10.8)
			# Build from source with a small patch to disable hardcoded trusted checkpoints.
			# See: ./patches/geth-v1.10.8-disable-trusted-checkpoints.patch
			cat > "$out_file" << 'EOF'
FROM golang:1.16-bullseye AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git make gcc g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/go-ethereum
RUN git clone https://github.com/ethereum/go-ethereum.git . \
    && git checkout v1.10.8

# Apply our local patch (copied from the build context).
COPY patches/geth-v1.10.8-disable-trusted-checkpoints.patch /patches/disable-trusted-checkpoints.patch
RUN git apply /patches/disable-trusted-checkpoints.patch

# Build logs for debugging/reproducibility
RUN echo "[build] go version: $(go version)" \
    && echo "[build] git rev:   $(git rev-parse --short HEAD)" \
    && echo "[build] git tag:   v1.10.8"

RUN make geth \
    && mkdir -p /out \
    && install -m 0755 build/bin/geth /out/geth \
    && /out/geth version || true

FROM debian:bullseye-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgmp10 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/geth /usr/local/bin/geth
RUN chmod +x /usr/local/bin/geth

RUN mkdir -p /data

EXPOSE 8545 30303

ENTRYPOINT ["geth"]
EOF
			return 0
			;;
		v1.9.25)
            cat >> "$out_file" << 'EOF'
RUN wget -O /tmp/geth.tar.gz https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.9.25-e7872729.tar.gz && \
    tar -xzf /tmp/geth.tar.gz -C /tmp && \
    mv /tmp/geth-linux-amd64-1.9.25-e7872729/geth /usr/local/bin/geth && \
    rm -rf /tmp/*
EOF
			;;
		v1.3.6)
			cat >> "$out_file" << 'EOF'
RUN wget -O /tmp/geth.tar https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2 && \
	# GitHub release assets for very old tags can sometimes be served with an unexpected
	# content-encoding (or the file may not actually be bzip2-compressed). Detect and extract
	# using a small set of fallbacks instead of hardcoding `tar -xjf`.
	if bzip2 -t /tmp/geth.tar >/dev/null 2>&1; then \
	    tar -xjf /tmp/geth.tar -C /tmp; \
	elif tar -xzf /tmp/geth.tar -C /tmp >/dev/null 2>&1; then \
	    true; \
	else \
	    tar -xf /tmp/geth.tar -C /tmp; \
	fi && \
	GETH_BIN=$(find /tmp -maxdepth 2 -type f -name geth | head -n 1) && \
	test -n "$GETH_BIN" && \
	mv "$GETH_BIN" /usr/local/bin/geth && \
	rm -rf /tmp/*
EOF
			;;
	esac

    # v1.0.x has a fully-defined multi-stage Dockerfile already.
    if [[ "$version" == v1.0.* ]]; then
        return 0
    fi

    cat >> "$out_file" << 'EOF'

RUN chmod +x /usr/local/bin/geth

# Create data directory
RUN mkdir -p /data

# Expose ports
EXPOSE 8545 30303

# Set entrypoint
ENTRYPOINT ["geth"]
EOF
}

# Build images
versions=(
	"v1.11.6"
	"v1.10.8"
	"v1.9.25"
	"v1.3.6"
	"v1.0.0"
	"v1.0.1"
	"v1.0.2"
	"v1.0.3"
)

# Optional: build only a single version (faster iteration).
# Example: ONLY_VERSION=v1.0.3 ./build-images.sh
if [[ -n "${ONLY_VERSION:-}" ]]; then
    versions=("$ONLY_VERSION")
fi

for version in "${versions[@]}"; do
    echo "Building image for $version using Debian bullseye-slim..."
    tmp_dockerfile="Dockerfile.${version}.tmp"
    create_dockerfile "$version" "$tmp_dockerfile"
    docker build -f "$tmp_dockerfile" -t ethereumtimemachine/geth:$version .
    rm -f "$tmp_dockerfile"
done

echo "Image building complete."
