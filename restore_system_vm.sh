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

# --- Safety Checks ---
echo "--- Virtual Machine Finalization Script ---"

# 1. Must be run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please use sudo." 
   exit 1
fi

# 2. Check that the target looks like a restored system
if [ ! -d "${RESTORE_TARGET}/etc" ] || [ ! -d "${RESTORE_TARGET}/boot" ]; then
    echo "ERROR: '${RESTORE_TARGET}' does not look like a restored Linux root."
    exit 1
fi

# 3. Final confirmation
echo
echo "This script will make the system at '${RESTORE_TARGET}' bootable on '${TARGET_DISK_VM}'."
read -p "Type 'FINALIZE' in all caps to continue: " CONFIRMATION
if [[ "$CONFIRMATION" != "FINALIZE" ]]; then
    echo "Confirmation not received. Aborting."
    exit 0
fi
echo "--- Checks passed. Entering chroot environment... ---"

# --- Chroot and Finalize ---
mount --bind /dev ${RESTORE_TARGET}/dev
mount --bind /dev/pts ${RESTORE_TARGET}/dev/pts
mount --bind /proc ${RESTORE_TARGET}/proc
mount --bind /sys ${RESTORE_TARGET}/sys

chroot "${RESTORE_TARGET}" /bin/bash << EOF
set -e
echo "--- Inside chroot ---"

echo "Step 1/4: Verifying /etc/fstab..."
echo "Please review your /etc/fstab. Use 'blkid' in another terminal to verify UUIDs."
echo "Press Enter to open fstab in vi..."
read
vi /etc/fstab

echo "Step 2/4: Re-installing GRUB..."
grub-install ${TARGET_DISK_VM}

echo "Step 3/4: Updating GRUB configuration..."
update-grub

echo "Step 4/4: Rebuilding the initramfs..."
update-initramfs -u -k all

echo "--- Exiting chroot ---"
EOF

umount ${RESTORE_TARGET}/dev/pts
umount ${RESTORE_TARGET}/dev
umount ${RESTORE_TARGET}/proc
umount ${RESTORE_TARGET}/sys

echo
echo "✅ VM FINALIZATION COMPLETE! ✅"
echo
echo "The system should now be bootable."
