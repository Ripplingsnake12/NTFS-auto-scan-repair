#!/bin/bash

# Auto NTFS Fix System for Arch Linux
# Automatically detects and repairs NTFS drives when plugged in
# Similar to Windows "scan and repair" functionality
#
# WARNING: This is a basic implementation that may need adjustment
# Test thoroughly before relying on it for important data

set -euo pipefail

# Configuration
LOG_FILE="/var/log/ntfs-autofix.log"
LOCK_FILE="/var/run/ntfs-autofix.lock"
NOTIFICATION_TIMEOUT=5000 # Notification display duration in milliseconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Utility Functions ---

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Install ntfs-3g if not present
install_ntfs3g() {
    if ! command -v ntfsfix &> /dev/null; then
        log "ntfs-3g not found, installing..."
        echo -e "${YELLOW}Installing ntfs-3g...${NC}"

        # Update package database and install
        if pacman -Sy --noconfirm ntfs-3g; then
            log "ntfs-3g installed successfully"
            echo -e "${GREEN}ntfs-3g installed successfully${NC}"
        else
            log "ERROR: Failed to install ntfs-3g. Please install it manually."
            echo -e "${RED}Failed to install ntfs-3g. Please install it manually.${NC}"
            exit 1
        fi
    else
        log "ntfs-3g is already installed"
    fi
}

# Check if device is NTFS
is_ntfs() {
    local device="$1"
    local fstype
    fstype=$(blkid -o value -s TYPE "$device" 2>/dev/null || echo "unknown")
    [[ "$fstype" == "ntfs" ]]
}

# Check if NTFS filesystem is dirty
is_dirty() {
    local device="$1"
    # Use ntfsfix with -n (no changes) to check if filesystem is dirty
    ntfsfix -n "$device" 2>&1 | grep -q "is dirty"
}

# --- Notification Function ---

# Send notification to user session
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-dialog-information}"

    log "Attempting to send notification: Title='$title', Message='$message', Icon='$icon'"

    local graphical_user=""
    local display=""
    local xauthority=""
    local runtime_path=""

    # Find the active graphical session user and their environment
    # Iterate through sessions to find the active graphical one
    while IFS= read -r session_id; do
        if loginctl show-session "$session_id" -p Type | grep -q "Type=x11\\|Type=wayland"; then
            graphical_user=$(loginctl show-session "$session_id" -p User | cut -d'=' -f2)
            display=$(loginctl show-session "$session_id" -p Display | cut -d'=' -f2)
            xauthority=$(loginctl show-session "$session_id" -p XAuthority | cut -d'=' -f2)
            runtime_path=$(loginctl show-session "$session_id" -p RuntimePath | cut -d'=' -f2)

            if [[ -z "$xauthority" ]] && [[ -n "$runtime_path" ]]; then
                xauthority="$runtime_path/xauthority"
            fi
            break # Found an active graphical session, stop
        fi
    done < <(loginctl list-sessions --no-legend | awk '{print $1}')

    if command -v notify-send &> /dev/null && [[ -n "$graphical_user" ]] && [[ -n "$display" ]] && [[ -n "$xauthority" ]]; then
        log "Sending notification via notify-send to user '$graphical_user' on display '$display'"
        # Use sudo -u to run notify-send as the graphical user
        # Set DISPLAY, XAUTHORITY, and DBUS_SESSION_BUS_ADDRESS (if available)
        local dbus_address
        dbus_address=$(sudo -u "$graphical_user" printenv DBUS_SESSION_BUS_ADDRESS 2>/dev/null)

        if [[ -n "$dbus_address" ]]; then
            sudo -u "$graphical_user" env DISPLAY="$display" XAUTHORITY="$xauthority" DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
                notify-send --expire-time="$NOTIFICATION_TIMEOUT" "$title" "$message" --icon="$icon" 2>/dev/null
        else
            sudo -u "$graphical_user" env DISPLAY="$display" XAUTHORITY="$xauthority" \
                notify-send --expire-time="$NOTIFICATION_TIMEOUT" "$title" "$message" --icon="$icon" 2>/dev/null
        fi

        if [[ $? -ne 0 ]]; then
            log "WARNING: notify-send command failed. It might not be installed for the user or the session environment is not correctly set."
            # Fallback to wall if notify-send fails for some reason
            log "Falling back to 'wall' for notification."
            echo -e "${YELLOW}Notification: $title - $message${NC}" | wall -n || log "WARNING: 'wall' command also failed."
        fi
    else
        log "WARNING: notify-send not available or active graphical session not found. Falling back to 'wall'."
        echo -e "${YELLOW}Notification: $title - $message${NC}" | wall -n || log "WARNING: 'wall' command also failed."
    fi
}


# --- Core Logic Functions ---

# Repair NTFS filesystem
repair_ntfs() {
    local device="$1"
    local mount_point="$2"

    log "Starting NTFS repair for $device"
    echo -e "${BLUE}Repairing NTFS filesystem on $device...${NC}"

    # Unmount if mounted
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log "Unmounting $device from $mount_point"
        umount "$device" || {
            log "WARNING: Could not unmount $device. Attempting repair while mounted (may fail)."
            echo -e "${YELLOW}Warning: Could not unmount $device. Repair might fail if in use.${NC}"
        }
    fi

    # Run ntfsfix
    if ntfsfix "$device"; then
        log "NTFS repair completed successfully for $device"
        echo -e "${GREEN}NTFS repair completed successfully for $device${NC}"

        # Send notification to user session
        send_notification "NTFS Repair Complete" "Successfully repaired $device." "drive-removable-media" # Using a more relevant icon

        return 0
    else
        log "ERROR: NTFS repair failed for $device"
        echo -e "${RED}NTFS repair failed for $device${NC}"

        # Send error notification
        send_notification "NTFS Repair Failed" "Failed to repair $device. Check log for details." "dialog-error"

        return 1
    fi
}

# Process a single device
process_device() {
    local device="$1"

    # Prevent concurrent processing of the same device
    local device_lock="/var/run/ntfs-autofix-$(basename "$device").lock"

    if [[ -f "$device_lock" ]]; then
        log "Device $device is already being processed, skipping"
        return 0
    fi

    touch "$device_lock"
    # Ensure lock file is removed on script exit, even if errors occur
    trap "rm -f '$device_lock'; trap - EXIT" EXIT

    log "Processing device: $device"

    # Wait a moment for device to settle - crucial for udev events
    sleep 3

    # Check if device exists and is accessible
    if [[ ! -b "$device" ]]; then
        log "Device $device is not a block device or not accessible (it might have been removed or renamed)."
        return 1
    fi

    # Check if it's NTFS
    if ! is_ntfs "$device"; then
        log "Device $device is not NTFS, skipping"
        return 0
    fi

    log "NTFS filesystem detected on $device"
    echo -e "${BLUE}NTFS filesystem detected on $device${NC}"

    # Get potential mount point (if it's already mounted by system)
    local mount_point
    mount_point=$(findmnt -n -o TARGET --source "$device" 2>/dev/null || echo "/mnt/$(basename "$device")") # Fallback if not mounted

    # Check if filesystem is dirty
    if is_dirty "$device"; then
        log "Dirty NTFS filesystem detected on $device"
        echo -e "${YELLOW}Dirty NTFS filesystem detected on $device!${NC}"

        # Send notification about starting repair
        send_notification "NTFS Scan & Repair" "Dirty filesystem detected on $device. Starting repair process..." "drive-harddisk-usb"

        # Repair the filesystem
        repair_ntfs "$device" "$mount_point"
    else
        log "NTFS filesystem on $device is clean"
        echo -e "${GREEN}NTFS filesystem on $device is clean.${NC}"

        # Send notification that filesystem is clean
        send_notification "NTFS Check Complete" "Filesystem on $device is clean." "drive-removable-media"
    fi

    # Clean up device lock file
    rm -f "$device_lock"
    trap - EXIT # Reset trap for this process_device call
}

# --- Main Script Execution ---

main() {
    # Ensure we have a global lock to prevent multiple main instances
    if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        log "Another main instance is already running (PID: $(cat "$LOCK_FILE")), exiting."
        exit 0
    fi

    echo $$ > "$LOCK_FILE"
    # Ensure global lock file is removed on script exit
    trap "rm -f '$LOCK_FILE'" EXIT

    # Check if running as root
    check_root

    # Install ntfs-3g if needed
    install_ntfs3g

    # Process device from environment variable (set by udev)
    if [[ -n "${DEVNAME:-}" ]]; then
        log "Running from udev for device: $DEVNAME"
        process_device "$DEVNAME"
    else
        # Manual mode - process all connected USB devices
        log "Manual mode: scanning all USB devices."
        echo -e "${BLUE}Scanning all connected USB devices for NTFS filesystems...${NC}"

        local found_devices=0
        # Find all USB storage devices that are actual block devices and have a partition
        for device_path in /sys/block/sd*/device; do
            if [[ -d "$device_path" ]]; then
                local dev_name=$(basename "$(readlink -f "$device_path")")
                if udevadm info --query=property --name="/dev/$dev_name" | grep -q "ID_BUS=usb"; then
                    # Now look for partitions on this USB device
                    for partition in /dev/"$dev_name"[0-9]*; do
                        if [[ -b "$partition" ]]; then
                            log "Found potential USB partition: $partition"
                            process_device "$partition"
                            found_devices=$((found_devices + 1))
                        fi
                    done
                fi
            fi
        done

        if [[ "$found_devices" -eq 0 ]]; then
            echo -e "${YELLOW}No NTFS USB devices found to scan in manual mode.${NC}"
            log "No NTFS USB devices found to scan in manual mode."
        else
            echo -e "${GREEN}Manual scan complete. Check log for details: $LOG_FILE${NC}"
        fi
    fi

    # Remove global lock file
    rm -f "$LOCK_FILE"
    trap - EXIT # Reset trap for main function
}

# --- Script Arguments Handling ---

if [[ "${1:-}" == "install" ]]; then
    check_root

    echo -e "${BLUE}Installing NTFS Auto-Fix system...${NC}"

    # Check for notify-send installation
    if ! command -v notify-send &> /dev/null; then
        echo -e "${YELLOW}Warning: 'notify-send' command not found. Desktop notifications might not work.${NC}"
        echo -e "${YELLOW}Consider installing 'libnotify' or 'gnome-shell' (for notify-send) for full notification functionality.${NC}"
        sleep 3 # Give user time to read warning
    fi

    # Create the main script in /usr/local/bin
    cp "$0" /usr/local/bin/ntfs-autofix
    chmod +x /usr/local/bin/ntfs-autofix

    # Create udev rule
    cat > /etc/udev/rules.d/99-ntfs-autofix.rules << 'EOF'
# Auto-fix NTFS filesystems when USB devices are plugged in
# This rule triggers the script for new block devices that are USB and NTFS.
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="ntfs", KERNEL=="sd[a-z][0-9]*", RUN+="/usr/local/bin/ntfs-autofix"
# A more generic rule for removable USB devices, with a slight delay
# This catches devices where ID_FS_TYPE might not be immediately available or for general scanning.
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ATTRS{removable}=="1", KERNEL=="sd[a-z][0-9]*", ENV{DEVNAME}!="", RUN+="/bin/bash -c 'sleep 5 && /usr/local/bin/ntfs-autofix'"
EOF

    # Reload udev rules
    echo -e "${BLUE}Reloading udev rules...${NC}"
    udevadm control --reload-rules
    udevadm trigger --action=add --subsystem=block # Trigger add events for existing devices (optional, for testing)

    # Create log file with proper permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    echo -e "${GREEN}NTFS Auto-Fix system installed successfully!${NC}"
    echo -e "${YELLOW}The system will now automatically check and repair NTFS drives when plugged in.${NC}"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    echo -e "${BLUE}To manually scan current devices: ${NC}sudo ntfs-autofix"
    echo -e "${BLUE}To uninstall: ${NC}sudo ntfs-autofix uninstall"
    echo -e "${BLUE}To check status: ${NC}sudo ntfs-autofix status"

elif [[ "${1:-}" == "uninstall" ]]; then
    check_root

    echo -e "${BLUE}Uninstalling NTFS Auto-Fix system...${NC}"

    # Remove files
    rm -f /usr/local/bin/ntfs-autofix
    rm -f /etc/udev/rules.d/99-ntfs-autofix.rules
    rm -f "$LOG_FILE"
    rm -f "$LOCK_FILE" # Remove any lingering lock file

    # Reload udev rules
    echo -e "${BLUE}Reloading udev rules...${NC}"
    udevadm control --reload-rules
    udevadm trigger

    echo -e "${GREEN}NTFS Auto-Fix system uninstalled successfully!${NC}"

elif [[ "${1:-}" == "status" ]]; then
    echo -e "${BLUE}NTFS Auto-Fix System Status${NC}"
    echo "================================"

    if [[ -f /usr/local/bin/ntfs-autofix ]] && [[ -f /etc/udev/rules.d/99-ntfs-autofix.rules ]]; then
        echo -e "Status: ${GREEN}Installed${NC}"
    else
        echo -e "Status: ${RED}Not Installed${NC}"
    fi

    if command -v ntfsfix &> /dev/null; then
        echo -e "ntfs-3g: ${GREEN}Installed${NC}"
    else
        echo -e "ntfs-3g: ${RED}Not Installed${NC}"
    fi

    if command -v notify-send &> /dev/null; then
        echo -e "notify-send: ${GREEN}Installed${NC} (for desktop notifications)"
    else
        echo -e "notify-send: ${YELLOW}Not Installed${NC} (desktop notifications might not work)"
    fi

    echo "Log file: $LOG_FILE"
    if [[ -f "$LOG_FILE" ]]; then
        echo "Recent entries:"
        tail -n 10 "$LOG_FILE" 2>/dev/null || echo "No recent entries in log."
    else
        echo "${YELLOW}Log file does not exist yet.${NC}"
    fi

    if [[ -f "$LOCK_FILE" ]]; then
        echo -e "Lock file: ${YELLOW}Active (${LOCK_FILE} by PID $(cat "$LOCK_FILE"))${NC}"
    else
        echo -e "Lock file: ${GREEN}Not active${NC}"
    fi

else
    # Normal operation
    main
fi
