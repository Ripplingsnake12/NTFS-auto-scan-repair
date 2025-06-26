# NTFS Auto-Fix for Arch Linux

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=fff)](#)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?logo=gnu-bash&logoColor=white)](#)

> **Automated NTFS filesystem repair system for Arch Linux - Windows-style "scan and repair" functionality for external drives**

## 🔧 What It Does

This system automatically detects when external NTFS drives are connected and performs filesystem checks and repairs, similar to Windows' built-in "scan and repair" functionality. It eliminates the need to manually run filesystem checks on external drives and prevents data corruption issues.

### Key Features

- **🚀 Automatic Detection**: Instantly detects when USB/external NTFS drives are plugged in
- **🔍 Smart Scanning**: Checks for filesystem corruption and "dirty" flags
- **⚡ Auto Repair**: Automatically runs `ntfsfix` to repair corrupted filesystems
- **📱 Desktop Notifications**: Real-time notifications about scan and repair progress
- **📊 Comprehensive Logging**: Detailed logs of all operations and repairs
- **🛡️ Safe Operation**: Uses read-only checks first, only repairs when necessary
- **🎯 Zero Configuration**: Works out of the box after installation

## 📋 Prerequisites

- Arch Linux (or Arch-based distribution)
- Root/sudo access for installation
- External NTFS drives to repair

## 🚀 Quick Start

### Installation

1. **Download and make executable:**
   ```bash
   chmod +x install.sh
   ```

2. **Install the system:**
   ```bash
   sudo ./install.sh install
   ```

3. **Verify installation:**
   ```bash
   sudo ./install.sh status
   ```

That's it! The system is now active and will automatically check external NTFS drives when you plug them in.

## 📖 Usage

### Automatic Operation
Once installed, the system works automatically:
- Plug in any external NTFS drive
- System automatically detects the drive
- Performs filesystem check
- Repairs if corruption is found
- Shows desktop notification with results

### Manual Operations

**Check current connected drives:**
```bash
sudo ntfs-autofix
```

**View system status:**
```bash
sudo ./install.sh status
```

**View recent logs:**
```bash
sudo tail -f /var/log/ntfs-autofix.log
```

**Uninstall system:**
```bash
sudo ./install.sh uninstall
```

## 🔧 How It Works

### Technical Overview

1. **udev Integration**: Uses udev rules to detect USB storage device connections
2. **Filesystem Detection**: Identifies NTFS filesystems using `blkid`
3. **Dirty Flag Check**: Uses `ntfsfix -n` to check for corruption without making changes
4. **Safe Repair**: Unmounts drive and runs `ntfsfix` to repair corruption
5. **User Notification**: Sends desktop notifications via `notify-send`
6. **Comprehensive Logging**: Records all operations with timestamps

### File Structure
```
/usr/local/bin/ntfs-autofix          # Main executable script
/etc/udev/rules.d/99-ntfs-autofix.rules  # udev rules for auto-detection
/var/log/ntfs-autofix.log            # Operation logs
```

### Dependencies
- `ntfs-3g` - Automatically installed if not present
- `udev` - For device detection (standard on Arch)
- `notify-send` - For desktop notifications (usually pre-installed)

## 🎯 Use Cases

### Perfect For:
- **Dual-boot systems** - Automatically repair NTFS drives that Windows marked as dirty
- **External storage** - Keep USB drives and external HDDs healthy
- **Data recovery** - Prevent minor corruption from becoming major data loss
- **Shared drives** - Maintain drives used between Windows and Linux systems
- **Workstation environments** - Automated maintenance for professional workflows

### Common Scenarios:
- Windows didn't shut down properly, marking NTFS drives as "dirty"
- External drive was unplugged without safely ejecting
- Power loss during write operations
- Minor filesystem corruption from normal use

## 📊 Example Output

### Successful Repair
```bash
2024-06-26 14:30:15 - NTFS filesystem detected on /dev/sdb1
2024-06-26 14:30:16 - Dirty NTFS filesystem detected on /dev/sdb1
2024-06-26 14:30:16 - Starting NTFS repair for /dev/sdb1
2024-06-26 14:30:18 - NTFS repair completed successfully for /dev/sdb1
```

### Clean Filesystem
```bash
2024-06-26 14:32:20 - NTFS filesystem detected on /dev/sdc1
2024-06-26 14:32:21 - NTFS filesystem on /dev/sdc1 is clean
```

## 🔒 Security & Safety

- **Read-only checks first** - Never modifies data without confirming corruption
- **Proper unmounting** - Ensures drive is safely unmounted before repair
- **Locking mechanism** - Prevents concurrent operations on the same device
- **Comprehensive logging** - Full audit trail of all operations
- **Non-destructive** - Only performs same repairs Windows would do automatically

## 🛠️ Troubleshooting

### Common Issues

**Script won't run:**
```bash
# Make sure it's executable
chmod +x install.sh
```

**No notifications appearing:**
```bash
# Check if notify-send is installed
which notify-send

# Install if missing
sudo pacman -S libnotify
```

**Drives not being detected:**
```bash
# Check udev rules are loaded
sudo udevadm control --reload-rules
sudo udevadm trigger

# Check if rules file exists
ls -la /etc/udev/rules.d/99-ntfs-autofix.rules
```

**Permission errors:**
```bash
# Installation requires root
sudo ./install.sh install
```

### Debug Mode
View real-time log output:
```bash
sudo tail -f /var/log/ntfs-autofix.log
```

Check what devices are being detected:
```bash
udevadm monitor --environment --udev
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup
```bash
git clone https://github.com/yourusername/ntfs-autofix-arch.git
cd ntfs-autofix-arch
chmod +x install.sh
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Support

If this project helped you, please consider giving it a star ⭐

## 📞 Support & Issues

- **Bug Reports**: Please use [GitHub Issues](../../issues)
- **Feature Requests**: Open an issue with the `enhancement` label
- **Questions**: Check existing issues or open a new one

---

**Made with ❤️ for the Arch Linux community**
