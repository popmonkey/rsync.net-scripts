# Bare Metal & VM rsync.net Backup/Restore System

This suite of scripts provides a robust, configurable system for performing full `rsync` backups of a Debian server and restoring it to either bare metal or a virtual machine. It is designed to be used with rsync.net.

## File Structure

The system is composed of the following files:

-   `config.sh`: The central configuration file. **All user-specific settings go here.**
-   `backup_system.sh`: The main backup script. You run this on the server you want to back up.
-   `restore_system.sh`: The first stage of the restore process. It syncs files from the remote backup.
-   `restore_system_bm.sh`: The second stage for restoring to **bare metal**. Makes the system bootable.
-   `restore_system_vm.sh`: The second stage for restoring to a **virtual machine**.
-   `restore_lxc.sh`: A standalone script to restore an individual LXC container to a running host.
-   `backup-exclude.list`: A file containing a list of paths to **exclude from backups**.
-   `restore-exclude.list`: A file containing a list of paths to **exclude from restores**.

---

## 1. Initial Setup & Configuration

Before running any scripts, you must configure the system.

### Step 1: Configure `config.sh`

Open `config.sh` and edit all the variables to match your environment. Pay close attention to:

-   `REMOTE_USER`, `REMOTE_HOST`, `REMOTE_BASE_PATH`: Your rsync.net (or other remote) details.
-   `BACKUP_SSH_KEY`: The **absolute path** to the SSH key on the server you are backing up.
-   `RESTORE_SSH_KEY`: The **absolute path** to the SSH key you will use in the live restore environment. This key must be copied to your live USB stick.
-   `BACKUP_EXCLUDE_FILE_PATH`: The **absolute path** to your `exclude.list` file.
-   `RESTORE_EXCLUDE_FILE_PATH`: The **absolute path** to your `restore-exclude.list` file.
-   `TARGET_DISK_BM` & `TARGET_DISK_VM`: The device names for your target disks (e.g., `/dev/sda`, `/dev/vda`).

### Step 2: Create Exclude Lists

You must create the two exclude list files specified in `config.sh`.

1.  **`backup-exclude.list`**: This file tells `backup_system.sh` what *not* to back up. It's good practice to exclude temporary files and caches.
    ```
    # Example exclude.list
    /tmp/*
    /var/cache/*
    /proc/*
    /sys/*
    /dev/*
    /run/*
    /mnt/*
    /media/*
    lost+found
    ```

2.  **`restore-exclude.list`**: This file tells `restore_system.sh` what *not* to restore from the backup. This is primarily used to avoid restoring large application data (like LXC containers) when you only want the base OS.
    ```
    # Example restore-exclude.list
    # Exclude all LXC containers from the base system restore
    /home/lxc/
    ```

---

## 2. Performing a Backup

To back up your server, run the `backup_system.sh` script as root.

```bash
sudo ./backup_system.sh
```

It is highly recommended to set this up as a cron job to run automatically. For example, to run it every night at 3:00 AM, edit the root crontab (`sudo crontab -e`) and add:

```crontab
0 3 * * * /path/to/your/scripts/backup_system.sh
```

---

## 3. Setting Up Passwordless Cron Jobs (Optional)

If you want to run the backup script from a non-root user's crontab, you need to grant that user passwordless `sudo` access **specifically for that script**. This is much safer than giving the user full passwordless sudo.

### Step 1: Secure the Script Files (CRITICAL)

Before editing the `sudoers` file, you **must** ensure that the user running the cron job cannot modify the backup script or its configuration. Otherwise, they could edit the script to run any command as root.

Set the ownership of the scripts to `root` and remove write permissions for anyone else.

```bash
# Set ownership to root user and group
sudo chown root:root /path/to/your/scripts/backup_system.sh
sudo chown root:root /path/to/your/scripts/config.sh

# Set permissions: owner (root) can read/write/execute, others can only read/execute
sudo chmod 755 /path/to/your/scripts/backup_system.sh
# Set permissions: owner (root) can read/write, others can only read
sudo chmod 644 /path/to/your/scripts/config.sh
```

### Step 2: Edit the Sudoers File

The safest way to edit the sudoers configuration is with the `visudo` command, which validates the syntax before saving. Run this command as root:

```bash
sudo visudo
```

### Step 3: Add the Sudoers Rule

Scroll to the bottom of the file and add the following line. Replace `your_username` with the user who will be running the cron job, and make sure the path to `backup_system.sh` is correct.

```
# Allow your_username to run the backup script without a password
your_username ALL=(ALL) NOPASSWD: /path/to/your/scripts/backup_system.sh
```

Save and exit the editor.

### Step 4: Update the User's Crontab

Now, you can edit the crontab for that specific user (`crontab -e` while logged in as them) and add the command using `sudo`:

```crontab
0 3 * * * sudo /path/to/your/scripts/backup_system.sh
```

This setup ensures the cron job can run with the necessary root privileges without requiring a password, while limiting the scope of those privileges to only the backup script.

---

## 4. Restricting SSH Access with `authorized_keys` (Advanced)

For enhanced security, you can configure your remote backup server (e.g., rsync.net) to only allow your SSH key to execute the specific `rsync` command needed for the backup, and nothing else.

The `backup_system.sh` script includes a helper option to facilitate this. To see the exact command the script will execute, run it with the `ssh_command` argument:

```bash
sudo ./backup_system.sh ssh_command
```

This will print a single line, which is the full `rsync` command that this script runs on your server to initiate the backup.

**Important:** The output of `ssh_command` is the **client-side** command. The command you need for the `authorized_keys` file on the **remote server** is different. You can use this output as a reference, but the remote command must typically start with `rsync --server`.

You should consult your remote provider's documentation for the exact syntax. For many providers, the entry in your remote `~/.ssh/authorized_keys` file will look something like this:

```
command="rsync --server --sender --fake-super -vlogDtprxS . \"/path/on/remote/server/\"",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa AAAA... your-key-comment
```

This ensures that even if the SSH key were compromised, the attacker could only use it to run the intended backup command.

---

## 5. Full System Restore

Restoring a full system is a multi-step process performed from a live Linux environment (like a Debian installer USB).

### Step 1: Prepare the Live Environment

1.  Boot the new bare metal server or VM from a live Linux ISO/USB.
2.  Copy your entire scripts directory (including `config.sh` and your SSH key) to the live environment.
3.  Ensure you have an internet connection.

### Step 2: Partition and Mount the Target Drive

Use tools like `fdisk`, `gparted`, or `cfdisk` to partition your new hard drive. Then, format the root partition and mount it.

```bash
# Example for a simple setup
mkfs.ext4 /dev/sda1
mount /dev/sda1 /mnt
```

**Note:** Ensure the `RESTORE_TARGET` in `config.sh` matches your mount point (`/mnt`).

### Step 3: Run the Restore Scripts

1.  Navigate to your scripts directory.
2.  Run the first stage restore script. This will sync the files.

    ```bash
    sudo ./restore_system.sh
    ```

3.  Once the file sync is complete, run the appropriate finalization script.
    -   **For Bare Metal:**
        ```bash
        sudo ./restore_system_bm.sh
        ```
    -   **For a Virtual Machine:**
        ```bash
        sudo ./restore_system_vm.sh
        ```
    These scripts will guide you through checking `fstab` and will install the bootloader.

### Step 4: Reboot

After the finalization script completes successfully, you can unmount the partition and reboot the machine.

```bash
umount /mnt
reboot
```

Your system should now boot from the restored disk.

---

## 6. Restoring a Single LXC Container

After you have a running host system (either the original or a newly restored one), you can restore individual LXC containers.

Run the `restore_lxc.sh` script as root, providing the name of the container as an argument.

```bash
# Example: Restore the 'webserver' container
sudo ./restore_lxc.sh webserver
```

The script will pull the container's files from the backup and place them in the correct directory on the host.
