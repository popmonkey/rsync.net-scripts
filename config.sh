#!/bin/bash

# This is the central configuration file for the backup and restore scripts.
# All other scripts will source this file to get their variables.

# --- Rsync.net Connection Details ---
REMOTE_USER="ab1234"
REMOTE_HOST="ab1234.rsync.net"
REMOTE_BASE_PATH="backups/myhost"

# --- SSH Key Paths ---
# Path to the rsync.net SSH key on the SERVER BEING BACKED UP
BACKUP_SSH_KEY="/path/to/id_rsync.net"

# Path to the rsync.net SSH key in the LIVE RESTORE ENVIRONMENT
RESTORE_SSH_KEY="/path/to/id_rsyncnet"

# --- File Paths ---
# The ABSOLUTE path to the exclude file for the system backup.
BACKUP_EXCLUDE_FILE_PATH="/path/to/your/exclude.list"

# The ABSOLUTE path to the exclude file for the system restore.
RESTORE_EXCLUDE_FILE_PATH="/path/to/your/restore-exclude.list"

# --- Restore Target Configuration ---
# The mount point for the new system's ROOT partition during restore
RESTORE_TARGET="/mnt"

# The target disk device for a BARE METAL restore
TARGET_DISK_BM="/dev/sdx"

# The target disk device for a VIRTUAL MACHINE restore
TARGET_DISK_VM="/dev/vdx"

# --- LXC Configuration ---
# The base directory where LXC containers are stored
LXC_BASE_DIR="/path/to/lxc"
