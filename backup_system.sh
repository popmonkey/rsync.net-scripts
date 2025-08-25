#!/bin/bash
set -xe

# --- Configuration ---
# Find the absolute path of the directory where this script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Load the configuration file
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=config.sh
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

LOCK_FILE="/tmp/system-backup.pid"

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

# --- rsync Command Configuration ---
# All rsync arguments are defined in this array for readability.
# They will be combined into a single command for execution.
rsync_args=(
    --archive
    --acls
    --xattrs
    --hard-links
    --sparse
    --human-readable
    --verbose
    --stats
    --numeric-ids
    --bwlimit=31250
    --delete-after
    --delete-excluded
    -e "ssh -i ${BACKUP_SSH_KEY}"
    --rsync-path="rsync --fake-super"
    --exclude-from="${BACKUP_EXCLUDE_FILE_PATH}"
)

# Add dry-run flag if there are uncommitted changes
if [[ -n "${DRY_RUN_FLAG}" ]]; then
    rsync_args+=("--dry-run")
fi

# Source and Destination paths
SOURCE_PATH="/"
DEST_PATH="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE_PATH}/"

# --- Argument Handling ---
# If the first argument is "ssh_command", print the command and exit.
# This is useful for setting up restricted SSH keys.
if [[ "$1" == "ssh_command" ]]; then
    # Build the command string with single spaces between arguments.
    COMMAND_STRING="/usr/bin/rsync"
    for arg in "${rsync_args[@]}"; do
        COMMAND_STRING+=" ${arg}"
    done
    COMMAND_STRING+=" ${SOURCE_PATH}"
    COMMAND_STRING+=" ${DEST_PATH}"

    echo "${COMMAND_STRING}"
    exit 0
fi

# --- rsync Execution Function ---
# This function wraps the rsync call to filter out "file vanished" errors,
# which can occur during backups of a live system. This logic was previously
# in the rsync-run.sh helper script.
run_rsync_with_filter() {
    local status
    local IGNOREEXIT=24
    local IGNOREOUT='^(file has vanished: |rsync warning: some files vanished before they could be transferred)'

    # The magic redirection below filters stderr from rsync without touching stdout.
    set -o pipefail
    { /usr/bin/rsync "$@" 2>&1 1>&3 3>&- | grep -E -v "$IGNOREOUT"; status=${PIPESTATUS[0]}; } 3>&1 1>&2
    set +o pipefail

    if [[ $status == $IGNOREEXIT ]]; then
        echo "INFO: rsync exited with status ${IGNOREEXIT} (files vanished), treating as success."
        return 0
    fi

    return $status
}

# --- Start Backup ---
echo "Starting backup at $(date)"

# We wrap the call to our function with /usr/bin/time to get performance stats.
/usr/bin/time -v run_rsync_with_filter "${rsync_args[@]}" "${SOURCE_PATH}" "${DEST_PATH}"
status=${?}

# --- Finish Backup ---
if [[ -n "${DRY_RUN_FLAG}" ]]; then
    echo "Dry run complete. Forcing non-zero exit status for cron alert." >&2
    status=1
fi

echo "Backup process finished at $(date) with status: ${status}"
exit ${status}
