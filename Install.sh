#!/bin/bash

# Auto NTFS Fix System for Arch Linux
# Automatically detects and repairs NTFS drives when plugged in
# Similar to Windows "scan and repair" functionality

set -euo pipefail

# Configuration
LOG_FILE="/var/log/ntfs-autofix.log"
LOCK_FILE="/var/run/ntfs-autofix.lock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        pacman -Sy --noconfirm ntfs-3g
        
        if command -v ntfsfix &> /dev/null; then
            log "ntfs-3g installed successfully"
            echo -e "${GREEN}ntfs-3g installed successfully${NC}"
        else
            log "ERROR: Failed to install ntfs-3g"
            echo -e "${RED}Failed to install ntfs-3g${NC}"
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
            log "WARNING: Could not unmount $device"
            echo -e "${YELLOW}Warning: Could not unmount $device${NC}"
        }
    fi
    
    # Run ntfsfix
    if ntfsfix "$device"; then
        log "NTFS repair completed successfully for $device"
        echo -e "${GREEN}NTFS repair completed successfully for $device${NC}"
        
        # Send notification to user session
        send_notification "NTFS Repair Complete" "Successfully repaired $device" "dialog-information"
        
        return 0
    else
        log "ERROR: NTFS repair failed for $device"
        echo -e "${RED}NTFS repair failed for $device${NC}"
        
        # Send error notification
        send_notification "NTFS Repair Failed" "Failed to repair $device" "dialog-error"
        
        return 1
    fi
}

# Send notification to user session
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-dialog-information}"
    
    # Find active user session
    local user_session
    user_session=$(who | grep "(:0)" | head -n1 | awk '{print $1}' || echo "")
    
    if [[ -n "$user_session" ]]; then
        # Send notification via notify-send as the logged-in user
        sudo -u "$user_session" DISPLAY=:0 notify-send "$title" "$message" --icon="$icon" 2>/dev/null || true
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
    trap "rm -f '$device_lock'" EXIT
    
    log "Processing device: $device"
    
    # Wait a moment for device to settle
    sleep 2
    
    # Check if device exists and is accessible
    if [[ ! -b "$device" ]]; then
        log "Device $device is not a block device or not accessible"
        return 1
    fi
    
    # Check if it's NTFS
    if ! is_ntfs "$device"; then
        log "Device $device is not NTFS, skipping"
        return 0
    fi
    
    log "NTFS filesystem detected on $device"
    echo -e "${BLUE}NTFS filesystem detected on $device${NC}"
    
    # Get potential mount point
    local mount_point="/mnt/$(basename "$device")"
    
    # Check if filesystem is dirty
    if is_dirty "$device"; then
        log "Dirty NTFS filesystem detected on $device"
        echo -e "${YELLOW}Dirty NTFS filesystem detected on $device${NC}"
        
        # Send notification about starting repair
        send_notification "NTFS Check" "Dirty filesystem detected on $device. Starting repair..." "dialog-warning"
        
        # Repair the filesystem
        repair_ntfs "$device" "$mount_point"
    else
        log "NTFS filesystem on $device is clean"
        echo -e "${GREEN}NTFS filesystem on $device is clean${NC}"
        
        # Send notification that filesystem is clean
        send_notification "NTFS Check" "Filesystem on $device is clean" "dialog-information"
    fi
    
    rm -f "$device_lock"
    trap - EXIT
}

# Main function for udev rule
main() {
    # Ensure we have a lock to prevent multiple instances
    if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        log "Another instance is already running"
        exit 0
    fi
    
    echo $$ > "$LOCK_FILE"
    trap "rm -f '$LOCK_FILE'" EXIT
    
    # Check if running as root
    check_root
    
    # Install ntfs-3g if needed
    install_ntfs3g
    
    # Process device from environment variable (set by udev)
    if [[ -n "${DEVNAME:-}" ]]; then
        process_device "$DEVNAME"
    else
        # Manual mode - process all connected USB devices
        log "Manual mode: scanning all USB devices"
        echo -e "${BLUE}Scanning all connected USB devices for NTFS filesystems...${NC}"
        
        # Find all USB storage devices
        for device in /dev/sd[a-z][0-9]*; do
            if [[ -b "$device" ]] && [[ -n "$(udevadm info --query=path --name="$device" | grep usb)" ]]; then
                process_device "$device"
            fi
        done
    fi
    
    rm -f "$LOCK_FILE"
    trap - EXIT
}

# If script is called with 'install' argument, set up the udev rule
if [[ "${1:-}" == "install" ]]; then
    check_root
    
    echo -e "${BLUE}Installing NTFS Auto-Fix system...${NC}"
    
    # Create the main script in /usr/local/bin
    cp "$0" /usr/local/bin/ntfs-autofix
    chmod +x /usr/local/bin/ntfs-autofix
    
    # Create udev rule
    cat > /etc/udev/rules.d/99-ntfs-autofix.rules << 'EOF'
# Auto-fix NTFS filesystems when USB devices are plugged in
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="ntfs", RUN+="/usr/local/bin/ntfs-autofix"
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ATTRS{removable}=="1", RUN+="/usr/local/bin/ntfs-autofix"
EOF
    
    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger
    
    # Create log file with proper permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    echo -e "${GREEN}NTFS Auto-Fix system installed successfully!${NC}"
    echo -e "${YELLOW}The system will now automatically check and repair NTFS drives when plugged in.${NC}"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    echo -e "${BLUE}To manually scan current devices: sudo ntfs-autofix${NC}"
    echo -e "${BLUE}To uninstall: sudo rm /usr/local/bin/ntfs-autofix /etc/udev/rules.d/99-ntfs-autofix.rules && sudo udevadm control --reload-rules${NC}"
    
elif [[ "${1:-}" == "uninstall" ]]; then
    check_root
    
    echo -e "${BLUE}Uninstalling NTFS Auto-Fix system...${NC}"
    
    # Remove files
    rm -f /usr/local/bin/ntfs-autofix
    rm -f /etc/udev/rules.d/99-ntfs-autofix.rules
    
    # Reload udev rules
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
    
    if [[ -f "$LOG_FILE" ]]; then
        echo "Log file: $LOG_FILE"
        echo "Recent entries:"
        tail -n 5 "$LOG_FILE" 2>/dev/null || echo "No recent entries"
    fi
    
else
    # Normal operation
    main
fi
