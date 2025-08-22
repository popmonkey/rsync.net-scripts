#!/bin/bash
set -xe

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

LOCK_FILE="/tmp/system-backup.pid"
HELPER_SCRIPT="${SCRIPT_DIR}/rsync-with-ignore-moved.sh"

# --- Lock Handling ---
cleanup() {
    echo "Backup finished. Removing lock file..."
    rm -f "${LOCK_FILE}"
}

if [ -f "${LOCK_FILE}" ]; then
    LOCKED_PID=$(cat "${LOCK_FILE}")
    if kill -0 "${LOCKED_PID}" 2>/dev/null; then
        echo "Backup is already running with PID ${LOCKED_PID}. Skipping."
        exit 0
    else
        echo "Found stale lock file. Removing it."
        rm -f "${LOCK_FILE}"
    fi
fi

echo "$$" > "${LOCK_FILE}"
trap cleanup EXIT INT TERM

# --- Pre-run Safety Check for Uncommitted Changes ---
DRY_RUN_FLAG=""
if [[ -n "$(git -C "${SCRIPT_DIR}" status --porcelain)" ]]; then
    DRY_RUN_FLAG="--dry-run"
    echo "#####################################################################" >&2
    echo "#   !!! WARNING: Uncommitted changes detected in script dir !!!     #" >&2
    echo "#  Forcing a --dry-run to prevent accidental data loss.             #" >&2
    echo "#####################################################################" >&2
fi

# --- Pre-run check for exclude file ---
if [ ! -f "${BACKUP_EXCLUDE_FILE_PATH}" ]; then
    echo "ERROR: Backup exclude file not found at '${BACKUP_EXCLUDE_FILE_PATH}'" >&2
    exit 1
fi


# --- Start Backup ---
echo "Starting backup at $(date)"

/usr/bin/time -v "${HELPER_SCRIPT}" \
    ${DRY_RUN_FLAG} \
    --archive \
    --acls \
    --xattrs \
    --hard-links \
    --sparse \
    --human-readable \
    --verbose \
    --stats \
    --numeric-ids \
    --bwlimit=31250 \
    --delete-after \
    --delete-excluded \
    -e "ssh -i ${BACKUP_SSH_KEY}" \
    --rsync-path="rsync --fake-super" \
    --exclude-from="${BACKUP_EXCLUDE_FILE_PATH}" \
    / \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE_PATH}/"

status=${?}

# --- Finish Backup ---
if [[ -n "${DRY_RUN_FLAG}" ]]; then
    echo "Dry run complete. Forcing non-zero exit status for cron alert." >&2
    status=1
fi

echo "Backup process finished at $(date) with status: ${status}"
exit ${status}
