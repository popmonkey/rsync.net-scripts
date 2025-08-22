#!/bin/bash
set -e

# --- Configuration ---
# Find the absolute path of the directory where this script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Load the configuration file
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

# --- Input and Safety Checks ---
if [ -z "$1" ]; then
    echo "Usage: $0 <container-name>"
    exit 1
fi
CONTAINER_NAME=$1

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

DESTINATION_PATH="${LXC_BASE_DIR}/${CONTAINER_NAME}"
if [ -d "$DESTINATION_PATH" ]; then
    echo "⚠️  A container named '${CONTAINER_NAME}' already exists."
    read -p "Overwrite local changes with the backup? (y/N) " CONFIRM
    if [[ "${CONFIRM,,}" != "y"* ]]; then
        echo "Aborting."
        exit 0
    fi
fi

echo "--- Preparing to restore container '${CONTAINER_NAME}' ---"

# --- Restore Process ---
REMOTE_SOURCE_PATH="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE_PATH}${LXC_BASE_DIR}/${CONTAINER_NAME}/"

echo "Restoring from ${REMOTE_SOURCE_PATH} to ${DESTINATION_PATH}/"
mkdir -p "$DESTINATION_PATH"

rsync \
    --archive \
    --acls \
    --xattrs \
    --hard-links \
    --sparse \
    --numeric-ids \
    --delete \
    --human-readable \
    --info=progress2 \
    --verbose \
    -e "ssh -i ${RESTORE_SSH_KEY}" \
    --rsync-path="rsync --fake-super" \
    "${REMOTE_SOURCE_PATH}" \
    "${DESTINATION_PATH}/"

echo
echo "✅ LXC container files restored successfully! ✅"
echo
echo "Review the container config: sudo nano ${DESTINATION_PATH}/config"
echo "Start the container with: sudo lxc-start -n ${CONTAINER_NAME} -F"
