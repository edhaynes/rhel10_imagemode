#!/bin/bash

# Build script for RHEL10 bootable container image
# This script should be run on the Fedora VM where files are copied

set -e  # Exit on any error

# Define variables
IMAGE_NAME="quay.io/ehaynes/imagemode:1.0"
BUILD_DIR="/var/home/core/imagemode"
SECRET_FILE="${BUILD_DIR}/password.txt"

# Check if secret file exists
if [[ ! -f "${SECRET_FILE}" ]]; then
    echo "Error: Secret file ${SECRET_FILE} not found!"
    exit 1
fi

# Build the container image using podman
echo "Building container image: ${IMAGE_NAME}"
podman build \
    --secret id=redhat-password,src="${SECRET_FILE}" \
    -t "${IMAGE_NAME}" \
    -f "${BUILD_DIR}/Containerfile" \
    "${BUILD_DIR}"

echo "Image built successfully: ${IMAGE_NAME}"

# Optional: Push to registry if needed
podman push "${IMAGE_NAME}"

echo "Build completed successfully"
