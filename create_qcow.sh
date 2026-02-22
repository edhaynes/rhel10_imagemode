#!/bin/bash

# Create qcow2 image script for RHEL10 bootable container
# This script should be run on the Fedora VM after building the container image

set -e  # Exit on any error

# Define variables (matching the build.sh script)
IMAGE_NAME="quay.io/ehaynes/imagemode:1.0"
BUILD_DIR="/var/home/core/imagemode"
CONFIG_FILE="${BUILD_DIR}/config.json"

# Check if we're running as root (required for podman)
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Check if the config file exists
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: Config file ${CONFIG_FILE} not found!"
    exit 1
fi

# Check if the container image exists
echo "Checking if container image exists: ${IMAGE_NAME}"
if ! podman images | grep -q "$(echo "${IMAGE_NAME}" | cut -d: -f1)"; then
    echo "Error: Container image ${IMAGE_NAME} not found!"
    echo "Please build the container image first using build.sh"
    exit 1
fi

echo "Creating qcow2 image from container: ${IMAGE_NAME}"

# Create output directory if it doesn't exist
mkdir -p "${BUILD_DIR}"

# Run bootc-image-builder to create qcow2 image
podman run --rm \
    --name imagemode-bootc-image-builder \
    --tty \
    --privileged \
    --security-opt label=type:unconfined_t \
    -v "${BUILD_DIR}:/output/" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "${CONFIG_FILE}:/config.json:ro" \
    --label bootc.image.builder=true \
    registry.redhat.io/rhel10/bootc-image-builder:latest \
    "${IMAGE_NAME}" \
    --output /output/ \
    --progress verbose \
    --type qcow2 \
    --target-arch aarch64 \
    --chown 1000:1000

echo "qcow2 image created successfully in ${BUILD_DIR}"