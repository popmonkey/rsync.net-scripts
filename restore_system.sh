#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

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

# Path to the exclusion file, located in the same directory as the script
EXCLUDE_FILE="${SCRIPT_DIR}/restore-exclude.list"

# --- Graceful Exit on CTRL-C ---
trap 'echo -e "\n\nCTRL-C detected. Aborting restore."; exit 130;' SIGINT

# --- Safety Checks ---
echo "--- Restore Script Safety Checks ---"

# 1. Must be run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please use sudo." 
   exit 1
fi

# 2. Advanced SSH Key and Auth Handling
USE_RETRY_LOOP=false
SSH_COMMAND_ARGS="-i ${RESTORE_SSH_KEY}"

if [ -f "$RESTORE_SSH_KEY" ]; then
    echo "SSH key found. Testing connection..."
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -i "${RESTORE_SSH_KEY}" "${REMOTE_USER}@${REMOTE_HOST}" "echo 'SSH key test successful.'" > /dev/null; then
        echo "✅ SSH key is valid. Automatic retries will be enabled."
        USE_RETRY_LOOP=true
    else
        echo "❌ ERROR: SSH key at '${RESTORE_SSH_KEY}' is not valid or the host is unreachable."
        exit 1
    fi
else
    echo "⚠️  WARNING: SSH key not found at ${RESTORE_SSH_KEY}."
    echo "The script can proceed using password authentication, but automatic retries on failure will be DISABLED."
    read -p "Type 'PASSWORD' in all caps to continue without a key: " CONFIRMATION
    if [[ "$CONFIRMATION" != "PASSWORD" ]]; then
        echo "Confirmation not received. Aborting."
        exit 1
    fi
    SSH_COMMAND_ARGS=""
fi

SSH_COMMAND_ARGS="-e \"ssh -o ServerAliveInterval=60 ${SSH_COMMAND_ARGS}\""

# 3. Target directory must be a mount point
if ! mountpoint -q "${RESTORE_TARGET}"; then
    echo "ERROR: The restore target '${RESTORE_TARGET}' is NOT a mount point."
    exit 1
fi

# 4. Check for the exclusion file
if [ ! -f "${EXCLUDE_FILE}" ]; then
    echo "ERROR: The exclusion file is missing at '${EXCLUDE_FILE}'."
    exit 1
fi

# 5. Final user confirmation
echo
echo "WARNING: This script will restore a full system backup to '${RESTORE_TARGET}'."
read -p "Type 'RESTORE' in all caps to continue: " CONFIRMATION
if [[ "$CONFIRMATION" != "RESTORE" ]]; then
    echo "Confirmation not received. Aborting."
    exit 0
fi
echo "--- Checks passed. Starting restore... ---"

# --- Restore Process ---
REMOTE_SOURCE_PATH="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE_PATH}/"
echo "Restoring from ${REMOTE_SOURCE_PATH} to ${RESTORE_TARGET}..."

RSYNC_BASE_COMMAND="rsync \
    --archive \
    --acls \
    --xattrs \
    --hard-links \
    --sparse \
    --numeric-ids \
    --delete \
    --human-readable \
    --info=progress \
    --verbose \
    --partial \
    --append-verify \
    --exclude-from='${EXCLUDE_FILE}' \
    --rsync-path=\"rsync --fake-super\""

if [ "$USE_RETRY_LOOP" = true ]; then
    echo "Starting rsync with automatic retry loop..."
    until eval "${RSYNC_BASE_COMMAND} ${SSH_COMMAND_ARGS} '${REMOTE_SOURCE_PATH}' '${RESTORE_TARGET}'"; do
        echo "Rsync failed with exit code $?. Retrying in 15 seconds..."
        sleep 15
    done
else
    echo "Starting rsync in single-run mode (no automatic retries)..."
    eval "${RSYNC_BASE_COMMAND} ${SSH_COMMAND_ARGS} '${REMOTE_SOURCE_PATH}' '${RESTORE_TARGET}'"
fi

echo "--- rsync finished. Re-creating essential system directories... ---"
mkdir -p ${RESTORE_TARGET}/{dev,proc,sys,run,tmp,mnt,media}
chmod 755 ${RESTORE_TARGET}/run
chmod 1777 ${RESTORE_TARGET}/tmp

echo
echo "✅ FILE RESTORE COMPLETE! ✅"
echo
echo "Next, run one of the finalization scripts to make the system bootable:"
echo "  - For physical hardware: ./restore_system_bm.sh"
echo "  - For a virtual machine:  ./restore_system_vm.sh"
echo
