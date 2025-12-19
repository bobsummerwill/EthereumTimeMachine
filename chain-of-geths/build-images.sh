#!/bin/bash

# Script to build Docker images for Geth versions
# Run this after creating the Dockerfiles for each version

set -e

# Create Dockerfile for each version
create_dockerfile() {
    local version=$1
    cat > Dockerfile << EOF
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget bzip2 xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Download and install geth binary
EOF
    case $version in
        v1.10.23)
            cat >> Dockerfile << 'EOF'
RUN wget -O /tmp/geth.tar.gz https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.10.23-d901d853.tar.gz && \
    tar -xzf /tmp/geth.tar.gz -C /tmp && \
    mv /tmp/geth-linux-amd64-1.10.23-d901d853/geth /usr/local/bin/geth && \
    rm -rf /tmp/*
EOF
            ;;
        v1.8.27)
            cat >> Dockerfile << 'EOF'
RUN wget -O /tmp/geth.tar.gz https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.8.27-4bcc0a37.tar.gz && \
    tar -xzf /tmp/geth.tar.gz -C /tmp && \
    mv /tmp/geth-linux-amd64-1.8.27-4bcc0a37/geth /usr/local/bin/geth && \
    rm -rf /tmp/*
EOF
            ;;
        v1.6.7)
            cat >> Dockerfile << 'EOF'
RUN wget -O /tmp/geth.tar.gz https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.6.7-ab5646c5.tar.gz && \
    tar -xzf /tmp/geth.tar.gz -C /tmp && \
    mv /tmp/geth-linux-amd64-1.6.7-ab5646c5/geth /usr/local/bin/geth && \
    rm -rf /tmp/*
EOF
            ;;
        v1.3.6)
            cat >> Dockerfile << 'EOF'
RUN wget -O /tmp/geth.tar.bz2 https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2 && \
    tar -xjf /tmp/geth.tar.bz2 -C /tmp && \
    mv /tmp/geth /usr/local/bin/geth && \
    rm -rf /tmp/*
EOF
            ;;
    esac
    cat >> Dockerfile << 'EOF'

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
    "v1.10.23"
    "v1.8.27"
    "v1.6.7"
    "v1.3.6"
)

for version in "${versions[@]}"; do
    echo "Building image for $version using Debian bullseye-slim..."
    create_dockerfile "$version"
    docker build -t ethereumtimemachine/geth:$version .
    rm Dockerfile
done

echo "Image building complete."
