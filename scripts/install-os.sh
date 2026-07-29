#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

echo "================================================="
echo "        Fowo OS Installation Wizard              "
echo "================================================="
while true; do
    echo "Choose your installation mode:"
    echo "1) Normal (FedOwOra) - Standard Fedora dnf-based with systemd"
    echo "2) Master (FeOwOra)  - Minimal fowo-based OS"
    read -p "Option (1/2): " install_mode
    case "$install_mode" in
        1|2) break ;;
        *) echo "Invalid option '$install_mode'. Please enter 1 or 2." ;;
    esac
done

INIT_CHOICE=""
CORE_CHOICE=""

if [ "$install_mode" = "2" ]; then
    echo ""
    echo "Master Mode Configuration:"
    while true; do
        echo "Choose Init System:"
        echo "1) systemd"
        echo "2) openrc"
        echo "3) runit"
        echo "4) diy"
        read -p "Init Option (1-4): " INIT_CHOICE
        case "$INIT_CHOICE" in
            1|2|3|4) break ;;
            *) echo "Invalid option '$INIT_CHOICE'. Please enter 1, 2, 3, or 4." ;;
        esac
    done

    echo ""
    while true; do
        echo "Choose core utilities:"
        echo "1) coreutils + bash"
        echo "2) busybox"
        read -p "Core Option (1/2): " CORE_CHOICE
        case "$CORE_CHOICE" in
            1|2) break ;;
            *) echo "Invalid option '$CORE_CHOICE'. Please enter 1 or 2." ;;
        esac
    done
fi

echo ""
read -p "Do you want to run a disk partitioning/formatting application (cfdisk/fdisk/parted)? (y/N): " run_disk_tool
if [[ "$run_disk_tool" =~ ^[Yy]$ ]]; then
    while true; do
        echo ""
        echo "Select disk tool:"
        echo "1) cfdisk (recommended)"
        echo "2) fdisk"
        echo "3) parted"
        echo "4) Skip / Cancel"
        read -p "Option (1-4): " tool_choice
        case "$tool_choice" in
            1|2|3|4) break ;;
            *) echo "Invalid option '$tool_choice'. Please enter 1, 2, 3, or 4." ;;
        esac
    done

    if [ "$tool_choice" != "4" ]; then
        read -p "Enter target device (e.g. /dev/sda or /dev/nvme0n1, leave blank for default): " DISK_DEV_CHOICE
        case "$tool_choice" in
            1)
                if [ -n "$DISK_DEV_CHOICE" ]; then
                    cfdisk "$DISK_DEV_CHOICE" || true
                else
                    cfdisk || true
                fi
                ;;
            2)
                if [ -n "$DISK_DEV_CHOICE" ]; then
                    fdisk "$DISK_DEV_CHOICE" || true
                else
                    fdisk -l || true
                    read -p "Enter target device for fdisk (e.g. /dev/sda): " FDISK_DEV
                    if [ -n "$FDISK_DEV" ]; then
                        fdisk "$FDISK_DEV" || true
                    fi
                fi
                ;;
            3)
                if [ -n "$DISK_DEV_CHOICE" ]; then
                    parted "$DISK_DEV_CHOICE" || true
                else
                    parted -l || true
                    read -p "Enter target device for parted (e.g. /dev/sda): " PARTED_DEV
                    if [ -n "$PARTED_DEV" ]; then
                        parted "$PARTED_DEV" || true
                    fi
                fi
                ;;
        esac
    fi
fi

echo ""
read -p "Enter Root Partition (e.g. /dev/sda2): " ROOT_PART
read -p "Enter EFI Partition (e.g. /dev/sda1, leave blank for BIOS): " EFI_PART

read -p "Do you want to format the Root partition? (y/N): " format_root
if [[ "$format_root" =~ ^[Yy]$ ]]; then
    while true; do
        echo "Select filesystem for $ROOT_PART:"
        echo "1) ext4 (default)"
        echo "2) xfs"
        read -p "Filesystem option (1/2): " fs_choice
        case "$fs_choice" in
            1)
                echo "Formatting $ROOT_PART as ext4..."
                mkfs.ext4 -F "$ROOT_PART"
                break
                ;;
            2)
                echo "Formatting $ROOT_PART as xfs..."
                mkfs.xfs -f "$ROOT_PART"
                break
                ;;
            *)
                echo "Invalid option '$fs_choice'. Please enter 1 or 2."
                ;;
        esac
    done
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
BASE_PKGS="kernel grub2-pc grub2-efi-x64 util-linux passwd nano iproute iputils e2fsprogs dosfstools parted xfsprogs"

if [ "$install_mode" = "1" ]; then
    echo "Installing Normal (FedOwOra) base..."
    dnf --use-host-config --installroot="$NEWROOT" --releasever=40 install -y \
        @core systemd dnf $BASE_PKGS
    
    # Copy fowo to the new system
    mkdir -p "$NEWROOT/usr/local/bin"
    cp /usr/local/bin/fowo "$NEWROOT/usr/local/bin/"
    
else
    echo "Installing Master (FeOwOra) minimal base..."
    
    # Pre-configure Fowo for master build
    mkdir -p /etc/fowo
    cat > /etc/fowo/config << 'EOF'
FLAGS_util-linux=-Dbuild-python=disabled
ALIAS https://git.savannah.gnu.org/git/patch.git = patch
ALIAS https://github.com/autotools-mirror/m4.git = m4
ALIAS https://git.savannah.gnu.org/git/autoconf.git = autoconf
ALIAS https://git.savannah.gnu.org/git/automake.git = automake
ALIAS https://git.savannah.gnu.org/git/libtool.git = libtool
ALIAS https://gitlab.freedesktop.org/pkg-config/pkg-config.git = pkg-config
EOF

    # Define predetermined Fowo packages map
    declare -A FOWO_REPOS=(
        ["kernel"]="https://github.com/torvalds/linux.git"
        ["grub2"]="https://git.savannah.gnu.org/git/grub.git"
        ["util-linux"]="https://github.com/util-linux/util-linux.git"
        ["passwd"]="https://github.com/shadow-maint/shadow.git"
        ["nano"]="https://git.savannah.gnu.org/git/nano.git"
        ["iproute"]="https://git.kernel.org/pub/scm/network/iproute2/iproute2.git"
        ["iputils"]="https://github.com/iputils/iputils.git"
        ["e2fsprogs"]="https://git.kernel.org/pub/scm/fs/ext2/e2fsprogs.git"
        ["dosfstools"]="https://github.com/dosfstools/dosfstools.git"
        ["parted"]="https://git.savannah.gnu.org/git/parted.git"
        ["xfsprogs"]="https://git.kernel.org/pub/scm/fs/xfs/xfsprogs-dev.git"
        ["bash"]="https://git.savannah.gnu.org/git/bash.git"
        ["coreutils"]="https://git.savannah.gnu.org/git/coreutils.git"
        ["busybox"]="https://git.busybox.net/busybox.git"
        ["systemd"]="https://github.com/systemd/systemd.git"
        ["openrc"]="https://github.com/OpenRC/openrc.git"
        ["runit"]="https://github.com/g-pape/runit.git"
        ["m4"]="https://github.com/autotools-mirror/m4.git"
        ["autoconf"]="https://git.savannah.gnu.org/git/autoconf.git"
        ["automake"]="https://git.savannah.gnu.org/git/automake.git"
        ["patch"]="https://git.savannah.gnu.org/git/patch.git"
        ["libtool"]="https://git.savannah.gnu.org/git/libtool.git"
        ["pkg-config"]="https://gitlab.freedesktop.org/pkg-config/pkg-config.git"
    )

    # Determine which packages to install
    SELECTED_PKGS=("m4" "autoconf" "automake" "patch" "libtool" "pkg-config" "kernel" "grub2" "util-linux" "passwd" "nano" "iproute" "iputils" "e2fsprogs" "dosfstools" "parted" "xfsprogs")
    
    if [ "$CORE_CHOICE" = "2" ]; then
        SELECTED_PKGS+=("busybox")
    else
        SELECTED_PKGS+=("bash" "coreutils")
    fi
    
    if [ "$INIT_CHOICE" = "1" ]; then
        SELECTED_PKGS+=("systemd")
    elif [ "$INIT_CHOICE" = "2" ]; then
        SELECTED_PKGS+=("openrc")
    elif [ "$INIT_CHOICE" = "3" ]; then
        SELECTED_PKGS+=("runit")
    fi
    
    export FOWO_ROOT="$NEWROOT"
    export PATH="$NEWROOT/usr/local/bin:$NEWROOT/usr/bin:$NEWROOT/bin:$PATH"
    for pkg in "${SELECTED_PKGS[@]}"; do
        echo "Fowo installing $pkg from ${FOWO_REPOS[$pkg]} ..."
        fowo install --no-edit "${FOWO_REPOS[$pkg]}" || {
            echo "Error: Failed to install $pkg via fowo"
            exit 1
        }
    done

    # Clean up temporary build workspace
    rm -rf "$NEWROOT/tmp/fowo_build" "$NEWROOT/tmp/fowo_dest_stage" /tmp/fowo_build /tmp/fowo_dest_stage 2>/dev/null || true

    echo "Setting up FeOwOra identity..."
    mkdir -p "$NEWROOT/etc"
    cat > "$NEWROOT/etc/os-release" << 'EOF'
NAME="FeOwOra"
PRETTY_NAME="FeOwOra Linux"
ID=feowora
ID_LIKE=fedora
VERSION_ID="1.0"
HOME_URL="https://github.com/FeOwOra"
EOF

    # Copy Fowo databases to the target so Fowo knows what is installed
    mkdir -p "$NEWROOT/var/lib/fowo/packages"
    if [ -d "/var/lib/fowo/packages" ]; then
        cp -a /var/lib/fowo/packages/* "$NEWROOT/var/lib/fowo/packages/" 2>/dev/null || true
    fi

    # DIY Init fallback (doesn't need repo)
    if [ "$INIT_CHOICE" = "4" ]; then
        echo "Setting up DIY Init..."
        mkdir -p "$NEWROOT/sbin"
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

# Mount virtual filesystems for chroot
echo "Mounting virtual filesystems for chroot..."
mount -o bind /dev "$NEWROOT/dev"
mount -t proc proc "$NEWROOT/proc"
mount -t sysfs sysfs "$NEWROOT/sys"
mount -t tmpfs tmpfs "$NEWROOT/run"

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
