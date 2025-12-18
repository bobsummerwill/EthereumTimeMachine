#!/bin/bash

# Script to build Docker images for Geth versions
# Run this after creating the Dockerfiles for each version

set -e

# Create Dockerfile for each version (same for all, just different VERSION)
cat > Dockerfile.template << 'EOF'
FROM ubuntu:24.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set version-specific variables (replace VERSION and ARCH as needed)
ARG VERSION
ARG ARCH=amd64

# Download and install geth binary
RUN case $VERSION in \
        v1.16.7) \
            # Use official image for v1.16.7 \
            exit 1 ;; \
        v1.10.23) \
            wget -O /usr/local/bin/geth https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.10.23-d901d853.tar.gz && \
            tar -xzf geth-linux-amd64-1.10.23-d901d853.tar.gz && \
            mv geth-linux-amd64-1.10.23-d901d853/geth /usr/local/bin/geth ;; \
        v1.8.27) \
            wget -O /usr/local/bin/geth https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.8.27-4bcc0a37.tar.gz && \
            tar -xzf geth-linux-amd64-1.8.27-4bcc0a37.tar.gz && \
            mv geth-linux-amd64-1.8.27-4bcc0a37/geth /usr/local/bin/geth ;; \
        v1.6.7) \
            wget -O /usr/local/bin/geth https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.6.7-ab5646c5.tar.gz && \
            tar -xzf geth-linux-amd64-1.6.7-ab5646c5.tar.gz && \
            mv geth-linux-amd64-1.6.7-ab5646c5/geth /usr/local/bin/geth ;; \
        v1.3.6) \
            wget -O /usr/local/bin/geth https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2 && \
            tar -xjf geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2 && \
            mv geth /usr/local/bin/geth ;; \
        *) \
            echo "Unknown version $VERSION" && exit 1 ;; \
    esac && \
    chmod +x /usr/local/bin/geth

# Create data directory
RUN mkdir -p /data

# Expose ports
EXPOSE 8545 30303

# Set entrypoint
ENTRYPOINT ["geth"]
EOF

# Build images
for version in v1.10.23 v1.8.27 v1.6.7 v1.3.6; do
    echo "Building image for $version..."
    cp Dockerfile.template Dockerfile
    sed -i "s/ARG VERSION/ARG VERSION=$version/" Dockerfile
    docker build -t ethereumtimemachine/geth:$version .
    rm Dockerfile
done

# Clean up
rm Dockerfile.template

echo "Image building complete."