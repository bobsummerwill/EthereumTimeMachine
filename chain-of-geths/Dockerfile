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
    && git checkout v1.0.2

# Build logs for debugging/reproducibility
RUN echo "[build] go version: $(go version)" \
    && echo "[build] git rev:   $(git rev-parse --short HEAD)" \
    && echo "[build] git tag:   v1.0.2"

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
