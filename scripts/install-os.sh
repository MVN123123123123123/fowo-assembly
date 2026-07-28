#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

echo "================================================="
echo "        Fowo OS Installation Wizard              "
echo "================================================="
echo "Choose your installation mode:"
echo "1) Normal (FedOwOra) - Standard Fedora dnf-based with systemd"
echo "2) Master (FeOwOra)  - Minimal fowo-based OS"
read -p "Option (1/2): " install_mode

INIT_CHOICE=""
CORE_CHOICE=""

if [ "$install_mode" = "2" ]; then
    echo ""
    echo "Master Mode Configuration:"
    echo "Choose Init System:"
    echo "1) systemd"
    echo "2) openrc"
    echo "3) runit"
    echo "4) diy"
    read -p "Init Option (1-4): " INIT_CHOICE

    echo ""
    echo "Choose core utilities:"
    echo "1) coreutils + bash"
    echo "2) busybox"
    read -p "Core Option (1/2): " CORE_CHOICE
fi

echo ""
read -p "Enter Root Partition (e.g. /dev/sda2): " ROOT_PART
read -p "Enter EFI Partition (e.g. /dev/sda1, leave blank for BIOS): " EFI_PART

read -p "Do you want to format the Root partition with ext4? (y/N): " format_root
if [[ "$format_root" =~ ^[Yy]$ ]]; then
    echo "Formatting $ROOT_PART as ext4..."
    mkfs.ext4 -F "$ROOT_PART"
fi

if [ -n "$EFI_PART" ]; then
    read -p "Do you want to format the EFI partition with FAT32? (y/N): " format_efi
    if [[ "$format_efi" =~ ^[Yy]$ ]]; then
        echo "Formatting $EFI_PART as FAT32..."
        mkfs.fat -F 32 "$EFI_PART"
    fi
fi

NEWROOT="/mnt/newroot"
mkdir -p "$NEWROOT"

cleanup_mounts() {
    echo "Cleaning up mounts..."
    umount "$NEWROOT/run" 2>/dev/null || true
    umount "$NEWROOT/sys" 2>/dev/null || true
    umount "$NEWROOT/proc" 2>/dev/null || true
    umount "$NEWROOT/dev" 2>/dev/null || true
    umount "$NEWROOT/boot/efi" 2>/dev/null || true
    umount "$NEWROOT" 2>/dev/null || true
}
trap cleanup_mounts EXIT

echo "Mounting partitions..."
mount "$ROOT_PART" "$NEWROOT"

if [ -n "$EFI_PART" ]; then
    mkdir -p "$NEWROOT/boot/efi"
    mount "$EFI_PART" "$NEWROOT/boot/efi"
fi

echo "================================================="
echo "Bootstrapping OS..."
echo "================================================="

# Common base packages for both to get a bootable system
# DNF is used here to bootstrap since fowo does not have --installroot
BASE_PKGS="kernel grub2-pc grub2-efi-x64 util-linux passwd nano iproute iputils"

if [ "$install_mode" = "1" ]; then
    echo "Installing Normal (FedOwOra) base..."
    dnf --use-host-config --installroot="$NEWROOT" --releasever=40 install -y \
        @core systemd dnf $BASE_PKGS
    
    # Copy fowo to the new system
    mkdir -p "$NEWROOT/usr/local/bin"
    cp /usr/local/bin/fowo "$NEWROOT/usr/local/bin/"
    
else
    echo "Installing Master (FeOwOra) minimal base..."
    
    # We must install build tools so fowo can build packages in the chroot
    FOWO_DEPS="git gcc make cmake pcre-devel sudo"
    
    if [ "$CORE_CHOICE" = "2" ]; then
        CORE_PKGS="busybox"
    else
        CORE_PKGS="coreutils bash"
    fi
    
    if [ "$INIT_CHOICE" = "1" ]; then
        INIT_PKGS="systemd"
    else
        INIT_PKGS=""
    fi
    
    # Install minimal packages using dnf first
    dnf --use-host-config --installroot="$NEWROOT" --releasever=40 --setopt=install_weak_deps=False install -y \
        $BASE_PKGS $CORE_PKGS $INIT_PKGS $FOWO_DEPS dnf

    # Prepare busybox if chosen
    if [ "$CORE_CHOICE" = "2" ]; then
        chroot "$NEWROOT" /bin/sh -c "busybox --install -s /bin || true"
        if [ ! -e "$NEWROOT/bin/bash" ]; then
            ln -sf /bin/sh "$NEWROOT/bin/bash"
        fi
    fi

    # Copy fowo to the new system
    mkdir -p "$NEWROOT/usr/local/bin"
    cp /usr/local/bin/fowo "$NEWROOT/usr/local/bin/"
    
    echo "Setting up FeOwOra identity..."
    cat > "$NEWROOT/etc/os-release" << 'EOF'
NAME="FeOwOra"
PRETTY_NAME="FeOwOra Linux"
ID=feowora
ID_LIKE=fedora
VERSION_ID="1.0"
HOME_URL="https://github.com/FeOwOra"
EOF

    # Prepare for fowo install
    echo "Mounting virtual filesystems for chroot..."
    mount -o bind /dev "$NEWROOT/dev"
    mount -t proc proc "$NEWROOT/proc"
    mount -t sysfs sysfs "$NEWROOT/sys"
    mount -t tmpfs tmpfs "$NEWROOT/run"
    
    echo "Generating predetermined fowo config from host topology..."
    mkdir -p "$NEWROOT/etc"
    mkdir -p "$NEWROOT/var/lib/fowo/packages"
    echo "# Predetermined dependencies from host" > "$NEWROOT/etc/fowo"
    if [ -d "/var/lib/fowo/packages" ]; then
        for db in /var/lib/fowo/packages/*.db; do
            if [ -f "$db" ]; then
                pkg=$(basename "$db" .db)
                url=$(sed -n 's/^URL=//p' "$db")
                if [ -n "$url" ]; then
                    echo "ALIAS $url = $pkg" >> "$NEWROOT/etc/fowo"
                fi
                cp "$db" "$NEWROOT/var/lib/fowo/packages/"
                sed -i 's/^COMMIT=.*/COMMIT=?/' "$NEWROOT/var/lib/fowo/packages/${pkg}.db"
            fi
        done
    fi
    
    echo "Installing Init System via Fowo..."
    if [ "$INIT_CHOICE" = "2" ]; then
        echo "Installing OpenRC..."
        chroot "$NEWROOT" /bin/sh -c "fowo install --no-edit https://github.com/OpenRC/openrc"
    elif [ "$INIT_CHOICE" = "3" ]; then
        echo "Installing runit..."
        chroot "$NEWROOT" /bin/sh -c "fowo install --no-edit https://github.com/g-pape/runit" # Placeholder for runit git source
    elif [ "$INIT_CHOICE" = "4" ]; then
        echo "Setting up DIY Init..."
        cat > "$NEWROOT/sbin/init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo "Welcome to FeOwOra DIY Init!"
exec /bin/sh
EOF
        chmod +x "$NEWROOT/sbin/init"
    fi

    echo "Removing DNF from Master OS..."
    chroot "$NEWROOT" /bin/sh -c "rpm -e --nodeps dnf dnf-data libdnf yum || true"
    
    umount "$NEWROOT/run"
    umount "$NEWROOT/sys"
    umount "$NEWROOT/proc"
    umount "$NEWROOT/dev"
fi

echo "================================================="
echo "Configuring System..."
echo "================================================="

# Generate fstab
echo "Generating fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
echo "UUID=$ROOT_UUID / ext4 defaults 1 1" > "$NEWROOT/etc/fstab"
if [ -n "$EFI_PART" ]; then
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    echo "UUID=$EFI_UUID /boot/efi vfat umask=0077,shortname=winnt 0 2" >> "$NEWROOT/etc/fstab"
fi

# Set root password
echo "Set password for root:"
chroot "$NEWROOT" passwd root

# Create user
read -p "Enter new username: " NEW_USER
if [ -n "$NEW_USER" ]; then
    chroot "$NEWROOT" useradd -m -G wheel "$NEW_USER"
    echo "Set password for $NEW_USER:"
    chroot "$NEWROOT" passwd "$NEW_USER"
fi

# Install Bootloader
echo "Installing GRUB bootloader..."
mount -o bind /dev "$NEWROOT/dev"
mount -t proc proc "$NEWROOT/proc"
mount -t sysfs sysfs "$NEWROOT/sys"

if [ -n "$EFI_PART" ]; then
    chroot "$NEWROOT" grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=FOWO
else
    # BIOS install (assumes root part is like /dev/sda2, we install to /dev/sda)
    # Handle both /dev/sdXN and /dev/nvme0n1pN partition naming
    if echo "$ROOT_PART" | grep -qE 'nvme|mmcblk'; then
        DISK_DEV=$(echo "$ROOT_PART" | sed 's/p[0-9]*$//')
    else
        DISK_DEV=$(echo "$ROOT_PART" | sed 's/[0-9]*$//')
    fi
    chroot "$NEWROOT" grub2-install "$DISK_DEV"
fi

chroot "$NEWROOT" grub2-mkconfig -o /boot/grub2/grub.cfg

umount "$NEWROOT/sys"
umount "$NEWROOT/proc"
umount "$NEWROOT/dev"

echo "Unmounting partitions..."
if [ -n "$EFI_PART" ]; then
    umount "$NEWROOT/boot/efi"
fi
umount "$NEWROOT"

echo "================================================="
echo "Installation Complete! You can now reboot."
echo "================================================="
