#!/bin/bash

# ==============================================================================
# Filesystem Inventory Script
#
# Description:
#   This script scans a given directory to provide a summary of disk usage.
#   It identifies:
#   1. Directories with a total size greater than a specified threshold.
#   2. Individual files larger than a specified threshold.
#   3. Directories containing more than a specified number of files.
#
#   It will stop immediately if a "Permission denied" error is encountered
#   and advise the user to run with sudo.
#
# Usage:
#   ./inventory.sh /path/to/scan /path/to/output_file.txt
#   For complete results on a full system scan, run with sudo.
#
# Author:
#   popmonkey & Gemini
# ==============================================================================

# --- Configuration ---
# Set the size threshold in Gigabytes (GB) for directories and files.
SIZE_THRESHOLD_GB=1
# Set the threshold for the number of files in a single directory.
FILE_COUNT_THRESHOLD=1000

# --- ANSI Color Codes ---
# Use these for styled output on the terminal.
CYAN='\033[0;36m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# Prints a formatted progress message to stderr.
# Arguments:
#   $1: The message string to display.
function progress_message() {
    echo -e "${CYAN}==> $1...${NC}" >&2
}

# This function reads from stdin (which will be connected to the stderr of
# a command) and watches for permission errors. If one is found, it prints
# a warning and terminates the entire script.
function error_handler() {
    while IFS= read -r line; do
        if [[ "$line" == *"Permission denied"* ]]; then
            # A permission error was found.
            echo -e "\n${RED}--- ERROR ---${NC}" >&2
            echo -e "${RED}A permission error was encountered. Stopping scan.${NC}" >&2
            echo -e "${RED}For a complete and accurate inventory, please run this script as root or with 'sudo'.${NC}" >&2
            # Terminate the main script process and all its children.
            # Check if pkill exists before using it.
            if command -v pkill >/dev/null; then
                pkill -P $$
            fi
            exit 1
        fi
    done
}
# Export the function so it's available to subshells created by process substitution.
export -f error_handler

# --- Main Inventory Logic ---
function run_inventory() {
    # 2. Find Large Directories
    progress_message "Searching for directories larger than ${SIZE_THRESHOLD_GB}GB"
    echo -e "${GREEN}--- Directories with total size > ${SIZE_THRESHOLD_GB}GB (sorted largest to smallest) ---${NC}"

    # 'du' command's stderr is piped to the error_handler function.
    { du -ak "$START_DIR" 2> >(error_handler); } | \
        awk -v threshold="$SIZE_THRESHOLD_KB" '$1 > threshold' | \
        sort -nr | \
        awk -v white="$WHITE" -v nc="$NC" '{
            size_kb = $1;
            path_start_index = index($0, $2);
            path = substr($0, path_start_index);
            gigs = size_kb / (1024*1024);
            printf "%s%.2f GB\t%s%s\n", white, gigs, path, nc;
        }'
    echo ""


    # 3. Find Large Individual Files
    progress_message "Searching for individual files larger than ${SIZE_THRESHOLD_GB}GB"
    echo -e "${GREEN}--- Individual files > ${SIZE_THRESHOLD_GB}GB (sorted largest to smallest) ---${NC}"

    # 'find' command's stderr is piped to the error_handler function.
    { find "$START_DIR" -type f -size "+${SIZE_THRESHOLD_GB}G" -printf '%s %p\n' 2> >(error_handler); } | \
        sort -nr | \
        awk -v white="$WHITE" -v nc="$NC" '{
            size_bytes = $1;
            path_start_index = index($0, " ") + 1;
            path = substr($0, path_start_index);
            gigs = size_bytes / (1024*1024*1024);
            printf "%s%.2f GB\t%s%s\n", white, gigs, path, nc;
        }'
    echo ""


    # 4. Find Directories with Many Files (Optimized)
    progress_message "Counting files in all directories (this may take a while)..."
    echo -e "${GREEN}--- Directories with > $FILE_COUNT_THRESHOLD files (direct children only) ---${NC}"

    # This 'find' command's stderr is also piped to the error_handler.
    { find "$START_DIR" -type f -printf '%h\n' 2> >(error_handler); } | \
        sort | \
        uniq -c | \
        awk -v threshold="$FILE_COUNT_THRESHOLD" -v white="$WHITE" -v nc="$NC" '
        $1 >= threshold {
            path_start_index = index($0, $2);
            path = substr($0, path_start_index);
            printf "%s%s files\t- %s%s\n", white, $1, path, nc;
        }' | \
        sort -nr
    echo ""


    progress_message "Inventory complete!"
}


# --- Script Entry Point ---

# 1. Validate Input
if [ "$#" -ne 2 ]; then
    echo "Error: Incorrect number of arguments." >&2
    echo "Usage: $0 <directory_to_scan> <output_file>" >&2
    exit 1
fi

START_DIR="$1"
OUTPUT_FILE="$2"

if [ ! -d "$START_DIR" ]; then
    echo "Error: Directory '$START_DIR' not found." >&2
    exit 1
fi

# Convert the GB threshold to Kilobytes for the 'du' command.
SIZE_THRESHOLD_KB=$((SIZE_THRESHOLD_GB * 1024 * 1024))

clear
echo -e "${CYAN}=====================================================${NC}" >&2
echo -e "${CYAN}     Starting Filesystem Inventory for '$START_DIR'     ${NC}" >&2
echo -e "${CYAN}=====================================================${NC}" >&2
echo "This process may take a very long time depending on the size of the drive." >&2
echo "" >&2

# Execute the inventory.
progress_message "Saving summary to '$OUTPUT_FILE' and displaying on screen"
# This revised pipeline is more robust when running under sudo.
# It uses 'tee' to send colored output directly to the terminal (/dev/tty).
# The original colored output is then piped to 'sed' to be stripped of
# color codes before being redirected to the final output file.
run_inventory | tee /dev/tty | sed -r 's/\x1b\[[0-9;]*m//g' > "$OUTPUT_FILE"
