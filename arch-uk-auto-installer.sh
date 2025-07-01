#!/bin/bash
# arch-deepseek-installer.sh
# Automated Arch Linux installation script for DeepSeek-Coder setup with UK localization
# Automatically detects and configures NVMe drives

set -e  # Exit on error

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration with UK defaults
HOSTNAME="jai"
USERNAME="docker"
TIMEZONE="Europe/London"  # UK timezone
LOCALE="en_GB.UTF-8"
KEYMAP="uk"               # UK keyboard layout
NTP_SERVER="uk.pool.ntp.org"

# Default password - change this in production
DEFAULT_PASSWORD="docker"

# LVM configuration
VG_NAME="vg_deepseek"
LV_ROOT_NAME="lv_root"
LV_ROOT_SIZE="80G"  # 80GB for root as requested
LV_LOG_NAME="lv_log"
LV_LOG_SIZE="20G"   # 20GB for logs as requested
LV_DOCKER_NAME="lv_docker"
# Docker will use remaining space (don't specify size)

# Package lists
BASE_PACKAGES="base base-devel linux linux-firmware lvm2"
SYSTEM_PACKAGES="vim git openssh sudo networkmanager curl wget htop tmux zsh neofetch"
NVIDIA_PACKAGES="nvidia nvidia-utils nvidia-settings nvidia-dkms cuda"
DOCKER_PACKAGES="docker docker-compose"

# Function to print colored text
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print section header
print_section() {
    local message=$1
    echo
    print_message "$BLUE" "===================================================="
    print_message "$BLUE" "  $message"
    print_message "$BLUE" "===================================================="
    echo
}

# Function to detect NVMe drives
detect_nvme_drives() {
    print_section "Detecting NVMe drives"
    
    # Get list of NVMe drives
    NVME_DRIVES=($(lsblk -d -p -n -o NAME | grep nvme))
    
    if [ ${#NVME_DRIVES[@]} -eq 0 ]; then
        print_message "$RED" "No NVMe drives detected. Installation cannot continue."
        exit 1
    fi
    
    print_message "$GREEN" "Detected ${#NVME_DRIVES[@]} NVMe drive(s):"
    for drive in "${NVME_DRIVES[@]}"; do
        drive_size=$(lsblk -d -n -o SIZE "$drive")
        print_message "$GREEN" "  $drive ($drive_size)"
    done
    
    # Select first NVMe for installation
    DISK="${NVME_DRIVES[0]}"
    print_message "$YELLOW" "Selected $DISK as installation target"
    
    # If we have a second NVMe, save it for later expansion
    if [ ${#NVME_DRIVES[@]} -gt 1 ]; then
        SECOND_DISK="${NVME_DRIVES[1]}"
        print_message "$YELLOW" "Detected second NVMe drive $SECOND_DISK - will add to LVM configuration"
        SECOND_DISK_AVAILABLE=true
    else
        SECOND_DISK_AVAILABLE=false
    fi
    
    # Confirm selection
    print_message "$YELLOW" "WARNING: This will erase ALL data on $DISK"
    if [ "$SECOND_DISK_AVAILABLE" = true ]; then
        print_message "$YELLOW" "WARNING: This will also erase ALL data on $SECOND_DISK"
    fi
    
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "$RED" "Installation aborted by user"
        exit 1
    fi
}

# Check if running in UEFI mode
check_uefi() {
    if [ -d "/sys/firmware/efi/efivars" ]; then
        print_message "$GREEN" "UEFI mode detected"
        UEFI_BOOT=true
    else
        print_message "$YELLOW" "BIOS mode detected"
        UEFI_BOOT=false
    fi
}

# Check internet connection
check_internet() {
    print_section "Checking internet connection"
    if ping -c 1 archlinux.org &> /dev/null; then
        print_message "$GREEN" "Internet connection is working"
    else
        print_message "$RED" "No internet connection detected - cannot continue"
        exit 1
    fi
}

# Update system clock
update_clock() {
    print_section "Updating system clock"
    timedatectl set-ntp true
    # Update mirrorlist for UK
    print_message "$GREEN" "Updating UK mirrors"
    curl -s "https://archlinux.org/mirrorlist/?country=GB&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' > /etc/pacman.d/mirrorlist
    # Set NTP server to UK pool
    print_message "$GREEN" "Setting UK NTP server"
    timedatectl set-ntp false
    timedatectl set-ntp true
    timedatectl timesync-status
    print_message "$GREEN" "System clock updated"
}

# Prepare disk with LVM
prepare_disk() {
    print_section "Preparing disk and setting up LVM"
    
    # Clear any existing partition table on first drive
    print_message "$YELLOW" "Wiping disk $DISK..."
    sgdisk --zap-all "$DISK"
    
    # If second disk is available, prepare it too
    if [ "$SECOND_DISK_AVAILABLE" = true ]; then
        print_message "$YELLOW" "Wiping disk $SECOND_DISK..."
        sgdisk --zap-all "$SECOND_DISK"
    fi

    # Create new partition table
    if [ "$UEFI_BOOT" = true ]; then
        # GPT partition table for UEFI
        print_message "$GREEN" "Creating GPT partition table for UEFI boot"
        parted -s "$DISK" mklabel gpt
        
        # Create EFI System Partition (ESP)
        print_message "$GREEN" "Creating EFI System Partition"
        parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
        parted -s "$DISK" set 1 boot on
        
        # Create LVM partition
        print_message "$GREEN" "Creating LVM partition"
        parted -s "$DISK" mkpart primary 513MiB 100%
        
        # Define variables for partitions
        EFI_PART="${DISK}p1"
        LVM_PART="${DISK}p2"
    else
        # MBR partition table for BIOS
        print_message "$GREEN" "Creating MBR partition table for BIOS boot"
        parted -s "$DISK" mklabel msdos
        
        # Create boot partition
        print_message "$GREEN" "Creating boot partition"
        parted -s "$DISK" mkpart primary 1MiB 513MiB
        parted -s "$DISK" set 1 boot on
        
        # Create LVM partition
        print_message "$GREEN" "Creating LVM partition"
        parted -s "$DISK" mkpart primary 513MiB 100%
        
        # Define variables for partitions
        BOOT_PART="${DISK}p1"
        LVM_PART="${DISK}p2"
    fi

    # Create physical volume on first drive
    print_message "$GREEN" "Creating LVM physical volume on $DISK"
    pvcreate "$LVM_PART"
    
    # Create physical volume on second drive if available
    if [ "$SECOND_DISK_AVAILABLE" = true ]; then
        print_message "$GREEN" "Creating LVM partition on $SECOND_DISK"
        # Create a single LVM partition on the second disk
        parted -s "$SECOND_DISK" mklabel gpt
        parted -s "$SECOND_DISK" mkpart primary 1MiB 100%
        
        # Define variable for the second disk's LVM partition
        SECOND_LVM_PART="${SECOND_DISK}p1"
        
        print_message "$GREEN" "Creating LVM physical volume on $SECOND_DISK"
        pvcreate "$SECOND_LVM_PART"
    fi
    
    # Create volume group
    if [ "$SECOND_DISK_AVAILABLE" = true ]; then
        # Create volume group with both drives
        print_message "$GREEN" "Creating LVM volume group $VG_NAME with both NVMe drives"
        vgcreate "$VG_NAME" "$LVM_PART" "$SECOND_LVM_PART"
    else
        # Create volume group with just the first drive
        print_message "$GREEN" "Creating LVM volume group $VG_NAME"
        vgcreate "$VG_NAME" "$LVM_PART"
    fi
    
    # Create logical volumes
    print_message "$GREEN" "Creating logical volumes"
    lvcreate -L "$LV_ROOT_SIZE" "$VG_NAME" -n "$LV_ROOT_NAME"
    lvcreate -L "$LV_LOG_SIZE" "$VG_NAME" -n "$LV_LOG_NAME"
    
    # Use remaining space for Docker
    print_message "$GREEN" "Allocating remaining space for Docker volume"
    lvcreate -l 100%FREE "$VG_NAME" -n "$LV_DOCKER_NAME"
    
    # Get allocated sizes
    docker_size=$(lvs --noheadings -o lv_size --unit g "/dev/$VG_NAME/$LV_DOCKER_NAME" | tr -d ' ')
    print_message "$GREEN" "Docker volume size: $docker_size"
    
    # Format partitions
    if [ "$UEFI_BOOT" = true ]; then
        print_message "$GREEN" "Formatting EFI partition"
        mkfs.fat -F32 "$EFI_PART"
    else
        print_message "$GREEN" "Formatting boot partition"
        mkfs.ext4 "$BOOT_PART"
    fi
    
    print_message "$GREEN" "Formatting logical volumes"
    mkfs.ext4 "/dev/$VG_NAME/$LV_ROOT_NAME"
    mkfs.ext4 "/dev/$VG_NAME/$LV_LOG_NAME"
    mkfs.ext4 "/dev/$VG_NAME/$LV_DOCKER_NAME"
    
    # Mount filesystems
    print_message "$GREEN" "Mounting filesystems"
    mount "/dev/$VG_NAME/$LV_ROOT_NAME" /mnt
    
    # Create necessary directories
    mkdir -p /mnt/boot
    mkdir -p /mnt/var/log
    mkdir -p /mnt/var/lib/docker
    
    # Mount other partitions
    if [ "$UEFI_BOOT" = true ]; then
        mkdir -p /mnt/boot/efi
        mount "$EFI_PART" /mnt/boot/efi
    else
        mount "$BOOT_PART" /mnt/boot
    fi
    
    mount "/dev/$VG_NAME/$LV_LOG_NAME" /mnt/var/log
    mount "/dev/$VG_NAME/$LV_DOCKER_NAME" /mnt/var/lib/docker
    
    print_message "$GREEN" "Disk preparation complete!"
}

# Install base system
install_base_system() {
    print_section "Installing base system"
    
    # Install essential packages
    print_message "$GREEN" "Installing base packages"
    pacstrap /mnt $BASE_PACKAGES
    
    # Generate fstab
    print_message "$GREEN" "Generating fstab"
    genfstab -U /mnt >> /mnt/etc/fstab
    
    print_message "$GREEN" "Base system installation complete!"
}

# Configure the system
configure_system() {
    print_section "Configuring system"
    
    # Chroot operations wrapper
    arch_chroot() {
        arch-chroot /mnt /bin/bash -c "$1"
    }
    
    # Set timezone
    print_message "$GREEN" "Setting timezone to $TIMEZONE"
    arch_chroot "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
    arch_chroot "hwclock --systohc"
    
    # Set locale
    print_message "$GREEN" "Setting locale to $LOCALE"
    arch_chroot "sed -i 's/#$LOCALE/$LOCALE/' /etc/locale.gen"
    arch_chroot "locale-gen"
    echo "LANG=$LOCALE" > /mnt/etc/locale.conf
    
    # Set keyboard layout
    print_message "$GREEN" "Setting keymap to $KEYMAP"
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf
    
    # Set hostname
    print_message "$GREEN" "Setting hostname to $HOSTNAME"
    echo "$HOSTNAME" > /mnt/etc/hostname
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF
    
    # Configure mkinitcpio for LVM
    print_message "$GREEN" "Configuring mkinitcpio for LVM"
    arch_chroot "sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf"
    arch_chroot "mkinitcpio -P"
    
    # Install bootloader
    if [ "$UEFI_BOOT" = true ]; then
        print_message "$GREEN" "Installing systemd-boot (UEFI)"
        arch_chroot "bootctl install"
        
        # Create loader entry
        mkdir -p /mnt/boot/loader/entries
        cat > /mnt/boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=/dev/$VG_NAME/$LV_ROOT_NAME rw
EOF
        
        # Set default loader
        cat > /mnt/boot/loader/loader.conf << EOF
default arch
timeout 3
editor  0
EOF
    else
        print_message "$GREEN" "Installing GRUB (BIOS)"
        arch_chroot "pacman -S --noconfirm grub"
        arch_chroot "grub-install --target=i386-pc $DISK"
        arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
    fi
    
    # Install additional packages
    print_message "$GREEN" "Installing additional packages"
    arch_chroot "pacman -S --noconfirm $SYSTEM_PACKAGES $NVIDIA_PACKAGES $DOCKER_PACKAGES"
    
    # Create user with sudo privileges
    print_message "$GREEN" "Creating user $USERNAME with password $DEFAULT_PASSWORD"
    arch_chroot "useradd -m -G wheel -s /bin/bash $USERNAME"
    # Set password non-interactively
    arch_chroot "echo '$USERNAME:$DEFAULT_PASSWORD' | chpasswd"
    
    # Configure sudo
    print_message "$GREEN" "Configuring sudo"
    arch_chroot "sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
    
    # Enable services
    print_message "$GREEN" "Enabling services"
    arch_chroot "systemctl enable NetworkManager"
    arch_chroot "systemctl enable sshd"
    arch_chroot "systemctl enable docker"
    
    # Configure NVIDIA Docker
    print_message "$GREEN" "Configuring NVIDIA Container Toolkit"
    arch_chroot "pacman -S --noconfirm nvidia-container-toolkit"
    
    # Create Docker daemon.json
    mkdir -p /mnt/etc/docker
    cat > /mnt/etc/docker/daemon.json << EOF
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
    
    # Add user to docker group
    arch_chroot "usermod -aG docker $USERNAME"
    
    # Set root password
    print_message "$GREEN" "Setting root password to $DEFAULT_PASSWORD"
    arch_chroot "echo 'root:$DEFAULT_PASSWORD' | chpasswd"
    
    print_message "$GREEN" "System configuration complete!"
}

# Create LVM management guide
create_lvm_guide() {
    print_section "Creating LVM management guide"
    
    mkdir -p /mnt/home/$USERNAME/docs
    
    cat > /mnt/home/$USERNAME/docs/lvm-guide.md << 'EOF'
# LVM Management Guide for DeepSeek-Coder Server

## Current LVM Setup

This server uses Logical Volume Management (LVM) with these volumes:

- **Root Volume** (`/dev/vg_deepseek/lv_root`): 80GB, mounted at `/`
- **Log Volume** (`/dev/vg_deepseek/lv_log`): 20GB, mounted at `/var/log`
- **Docker Volume** (`/dev/vg_deepseek/lv_docker`): Remaining space, mounted at `/var/lib/docker`

## Checking Current LVM Status

To see your current LVM configuration:

```bash
# List all physical volumes
sudo pvs

# List all volume groups
sudo vgs

# List all logical volumes
sudo lvs

# Show detailed information about a specific volume group
sudo vgdisplay vg_deepseek

# Show detailed information about a specific logical volume
sudo lvdisplay /dev/vg_deepseek/lv_docker
```

## Adding a New Drive to Extend Docker Storage

If you need to add more storage for Docker, follow these steps:

### 1. Install the new physical drive

Install the new drive (NVME, SSD, or HDD) in your system.

### 2. Create a physical volume on the new drive

First, identify the new drive:
```bash
lsblk
```

Create a new partition (if needed):
```bash
sudo parted /dev/nvme1n1 mklabel gpt
sudo parted /dev/nvme1n1 mkpart primary 1MiB 100%
```

Initialize it as a physical volume:
```bash
sudo pvcreate /dev/nvme1n1p1
```

### 3. Extend your volume group

Add the new physical volume to your existing volume group:
```bash
sudo vgextend vg_deepseek /dev/nvme1n1p1
```

### 4. Extend the Docker logical volume

Extend the Docker logical volume to use the new space:
```bash
# To add all available space:
sudo lvextend -l +100%FREE /dev/vg_deepseek/lv_docker

# To add a specific amount (e.g., 500GB):
sudo lvextend -L +500G /dev/vg_deepseek/lv_docker
```

### 5. Resize the filesystem

Resize the filesystem to use the new space:
```bash
sudo resize2fs /dev/vg_deepseek/lv_docker
```

### 6. Verify the changes

```bash
df -h /var/lib/docker
sudo lvs
```

## Moving Docker to a Completely New Drive (Alternative Approach)

If you prefer to move Docker to a separate drive instead of extending:

### 1. Prepare the new drive

```bash
sudo pvcreate /dev/nvme1n1p1
sudo vgcreate vg_docker /dev/nvme1n1p1
sudo lvcreate -l 100%FREE vg_docker -n lv_docker
sudo mkfs.ext4 /dev/vg_docker/lv_docker
```

### 2. Stop Docker service

```bash
sudo systemctl stop docker
```

### 3. Move the data

```bash
sudo mkdir /var/lib/docker_new
sudo mount /dev/vg_docker/lv_docker /var/lib/docker_new
sudo rsync -av /var/lib/docker/ /var/lib/docker_new/
```

### 4. Update fstab

Edit /etc/fstab to replace the old Docker mount with the new one:
```bash
sudo nano /etc/fstab
```

Replace the line for `/var/lib/docker` with:
```
/dev/vg_docker/lv_docker /var/lib/docker ext4 defaults 0 0
```

### 5. Apply the changes

```bash
sudo umount /var/lib/docker_new
sudo umount /var/lib/docker
sudo mount /dev/vg_docker/lv_docker /var/lib/docker
sudo systemctl start docker
```

## Additional LVM Operations

### Resize a logical volume

```bash
# Increase the log volume by 10GB
sudo lvextend -L +10G /dev/vg_deepseek/lv_log
sudo resize2fs /dev/vg_deepseek/lv_log
```

### Create a snapshot (for backups)

```bash
# Create a snapshot of the root volume
sudo lvcreate -L 10G -s -n root_snapshot /dev/vg_deepseek/lv_root

# Mount the snapshot
sudo mkdir /mnt/snapshot
sudo mount /dev/vg_deepseek/root_snapshot /mnt/snapshot

# After backing up, remove the snapshot
sudo umount /mnt/snapshot
sudo lvremove /dev/vg_deepseek/root_snapshot
```

### Remove a physical volume (if replacing a drive)

```bash
# Move data off the physical volume
sudo pvmove /dev/old_drive

# Remove the physical volume from the volume group
sudo vgreduce vg_deepseek /dev/old_drive

# Remove the physical volume
sudo pvremove /dev/old_drive
```
EOF
    
    # Change ownership of the guide
    arch_chroot "chown -R $USERNAME:$USERNAME /home/$USERNAME/docs"
    
    print_message "$GREEN" "LVM management guide created at /home/$USERNAME/docs/lvm-guide.md"
}

# Clone DeepSeek-Coder repo and set up environment
setup_deepseek() {
    print_section "Setting up DeepSeek-Coder environment"
    
    # Create DeepSeek directory
    arch_chroot "mkdir -p /home/$USERNAME/deepseek-coder-setup"
    
    # Clone the DeepSeek-Coder repository if URL is provided
    if [ -n "$REPO_URL" ]; then
        print_message "$GREEN" "Cloning DeepSeek-Coder repository from $REPO_URL"
        arch_chroot "git clone $REPO_URL /home/$USERNAME/deepseek-coder-setup"
    fi
    
    # Set proper ownership
    arch_chroot "chown -R $USERNAME:$USERNAME /home/$USERNAME/deepseek-coder-setup"
    
    # Create welcome message
    cat > /mnt/etc/profile.d/deepseek-welcome.sh << 'EOF'
#!/bin/bash
echo ""
echo "Welcome to DeepSeek-Coder Server"
echo "--------------------------------"
echo "To set up your DeepSeek-Coder environment:"
echo "1. Clone your repository or create config files in ~/deepseek-coder-setup"
echo "2. Run 'cd ~/deepseek-coder-setup && docker-compose up -d'"
echo ""
echo "System Status:"
NVIDIA_DRIVER=$(nvidia-smi | grep "Driver Version" | awk '{print $3}' 2>/dev/null || echo "Not loaded")
echo "  NVIDIA Driver: $NVIDIA_DRIVER"
DOCKER_VERSION=$(docker --version | awk '{print $3}' 2>/dev/null || echo "Not running")
echo "  Docker: $DOCKER_VERSION"
GPU_COUNT=$(nvidia-smi --list-gpus | wc -l 2>/dev/null || echo "0")
echo "  Available GPUs: $GPU_COUNT"
echo ""
echo "Storage Information:"
ROOT_SIZE=$(df -h / | awk 'NR==2 {print $2}')
echo "  Root: $ROOT_SIZE"
DOCKER_SIZE=$(df -h /var/lib/docker | awk 'NR==2 {print $2}')
echo "  Docker: $DOCKER_SIZE"
LOG_SIZE=$(df -h /var/log | awk 'NR==2 {print $2}')
echo "  Logs: $LOG_SIZE"
echo ""
echo "LVM Management Guide: ~/docs/lvm-guide.md"
echo ""
echo "IMPORTANT: Default password is '$DEFAULT_PASSWORD' - please change it immediately!"
echo "  sudo passwd root"
echo "  passwd"
echo ""
EOF
    chmod +x /mnt/etc/profile.d/deepseek-welcome.sh
    
    print_message "$GREEN" "DeepSeek-Coder environment setup complete!"
}

# Finalize installation
finalize_installation() {
    print_section "Finalizing installation"
    
    # Create a summary of the installation
    INSTALL_SUMMARY="/mnt/home/$USERNAME/installation-summary.txt"
    
    cat > "$INSTALL_SUMMARY" << EOF
# DeepSeek-Coder Installation Summary
Date: $(date)

## System Information
Hostname: $HOSTNAME
Username: $USERNAME
Default Password: $DEFAULT_PASSWORD (CHANGE THIS IMMEDIATELY!)
Timezone: $TIMEZONE
Locale: $LOCALE
Keyboard: $KEYMAP

## Disk Configuration
Boot Mode: $([ "$UEFI_BOOT" = true ] && echo "UEFI" || echo "BIOS")
Primary Disk: $DISK
$([ "$SECOND_DISK_AVAILABLE" = true ] && echo "Secondary Disk: $SECOND_DISK" || echo "No secondary disk detected")

## LVM Configuration
Volume Group: $VG_NAME
Root Volume: $LV_ROOT_SIZE
Log Volume: $LV_LOG_SIZE
Docker Volume: $(lvs --noheadings -o lv_size --unit g "/dev/$VG_NAME/$LV_DOCKER_NAME" | tr -d ' ')

## Next Steps
1. Change default passwords
2. Run 'sudo pacman -Syu' to update the system
3. Set up your DeepSeek-Coder environment in ~/deepseek-coder-setup

## LVM Management
See ~/docs/lvm-guide.md for details on managing your LVM volumes
EOF
    
    # Change ownership of the summary file
    arch_chroot "chown $USERNAME:$USERNAME /home/$USERNAME/installation-summary.txt"
    
    # Unmount all partitions
    print_message "$GREEN" "Unmounting all partitions"
    umount -R /mnt
    
    print_message "$GREEN" "Installation complete!"
    print_message "$GREEN" "You can now reboot into your new system."
    print_message "$YELLOW" "Default username: $USERNAME"
    print_message "$YELLOW" "Default password: $DEFAULT_PASSWORD (CHANGE THIS IMMEDIATELY!)"
}

# Main installation flow
main() {
    print_section "Starting Arch Linux installation for DeepSeek-Coder"
    
    check_uefi
    check_internet
    update_clock
    detect_nvme_drives
    prepare_disk
    install_base_system
    configure_system
    create_lvm_guide
    setup_deepseek
    finalize_installation
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hostname=*)
        HOSTNAME="${1#*=}"
        shift
        ;;
        --username=*)
        USERNAME="${1#*=}"
        shift
        ;;
        --password=*)
        DEFAULT_PASSWORD="${1#*=}"
        shift
        ;;
        --repo=*)
        REPO_URL="${1#*=}"
        shift
        ;;
        *)
        # Unknown option
        print_message "$RED" "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Run the installation
main
