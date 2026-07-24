#!/bin/sh
# install-tcl-fowo.sh - Installs Tiny Core Linux x64 + Fowo to disk (UEFI/GPT)
set -e

# Keep terminal open on exit so user can see what happened
finish() {
    echo ""
    echo "[Installer Exited. Press ENTER to close this window.]"
    read -r _
}
trap finish EXIT

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

TARGET_DEV="$1"

if [ -z "$TARGET_DEV" ]; then
    echo "================================================="
    echo "   Tiny Core Linux x64 + Fowo Disk Installer   "
    echo "================================================="
    echo ""
    echo "Available disk devices:"
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -d -n -o NAME,SIZE,TYPE | grep disk || true
    else
        fdisk -l 2>/dev/null | grep "Disk /dev/" || true
    fi
    echo ""
    printf "Enter target device (e.g. /dev/sda or /dev/vda): "
    read TARGET_DEV
fi

if [ -z "$TARGET_DEV" ] || [ ! -b "$TARGET_DEV" ]; then
    echo "Error: Invalid device '$TARGET_DEV'."
    exit 1
fi

echo ""
echo "WARNING: ALL DATA ON $TARGET_DEV WILL BE ERASED!"
printf "Are you sure you want to continue? (y/N): "
read CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Installation cancelled."
    exit 0
fi

echo "[1/6] Unmounting existing partitions on $TARGET_DEV..."
umount ${TARGET_DEV}* 2>/dev/null || true

echo "[2/6] Partitioning $TARGET_DEV with GPT..."
# Clear beginning of disk
dd if=/dev/zero of="$TARGET_DEV" bs=1M count=10 status=none || true

if ! command -v parted >/dev/null 2>&1; then
    echo "Error: parted not found. Make sure parted.tcz is installed."
    exit 1
fi

parted -s "$TARGET_DEV" mklabel gpt
# Partition 1: EFI System Partition (256MB)
parted -s "$TARGET_DEV" mkpart ESP fat32 1MiB 257MiB
parted -s "$TARGET_DEV" set 1 boot on
parted -s "$TARGET_DEV" set 1 esp on
# Partition 2: Root (ext4)
parted -s "$TARGET_DEV" mkpart primary ext4 257MiB 100%

# Detect partition names (e.g. /dev/sda1 or /dev/nvme0n1p1)
if [ -b "${TARGET_DEV}p1" ]; then
    ESP_DEV="${TARGET_DEV}p1"
    ROOT_DEV="${TARGET_DEV}p2"
else
    ESP_DEV="${TARGET_DEV}1"
    ROOT_DEV="${TARGET_DEV}2"
fi

# Wait for kernel to register partitions
sleep 2

echo "[3/6] Formatting partitions..."
if ! command -v mkfs.vfat >/dev/null 2>&1; then
    echo "Error: mkfs.vfat not found (install dosfstools.tcz)."
    exit 1
fi
if ! command -v mkfs.ext4 >/dev/null 2>&1; then
    echo "Error: mkfs.ext4 not found (install e2fsprogs.tcz)."
    exit 1
fi

mkfs.vfat -F32 "$ESP_DEV"
mkfs.ext4 -F "$ROOT_DEV"

MNT_DIR="/tmp/tcl_install_target"
mkdir -p "$MNT_DIR"

echo "[4/6] Mounting $ROOT_DEV to $MNT_DIR..."
mount "$ROOT_DEV" "$MNT_DIR"
mkdir -p "$MNT_DIR/boot/efi"
mount "$ESP_DEV" "$MNT_DIR/boot/efi"

# Cleanup trap (runs before finish trap)
cleanup() {
    umount "$MNT_DIR/boot/efi" 2>/dev/null || true
    umount "$MNT_DIR" 2>/dev/null || true
    rmdir "$MNT_DIR" 2>/dev/null || true
}
# We need to prepend cleanup to the existing EXIT trap
trap 'cleanup; finish' EXIT

echo "[5/6] Copying system files & fowo extensions..."
mkdir -p "$MNT_DIR/tce/optional"

# Locate kernel and corepure64 initrd
VMLINUZ=""
COREGZ=""

for path in /boot/vmlinuz64 /mnt/cdrom/boot/vmlinuz64 /mnt/sr0/boot/vmlinuz64 /cde/boot/vmlinuz64 /tmp/iso_mount/boot/vmlinuz64; do
    if [ -f "$path" ]; then
        VMLINUZ="$path"
        break
    fi
done

for path in /boot/corepure64.gz /mnt/cdrom/boot/corepure64.gz /mnt/sr0/boot/corepure64.gz /cde/boot/corepure64.gz /tmp/iso_mount/boot/corepure64.gz; do
    if [ -f "$path" ]; then
        COREGZ="$path"
        break
    fi
done

if [ -n "$VMLINUZ" ] && [ -n "$COREGZ" ]; then
    cp "$VMLINUZ" "$MNT_DIR/boot/vmlinuz64"
    cp "$COREGZ" "$MNT_DIR/boot/corepure64.gz"
else
    echo "Warning: Could not find kernel/initrd directly in standard paths. Searching..."
    find / -name "vmlinuz64" 2>/dev/null | head -n 1 | xargs -I{} cp {} "$MNT_DIR/boot/vmlinuz64" || true
    find / -name "corepure64.gz" 2>/dev/null | head -n 1 | xargs -I{} cp {} "$MNT_DIR/boot/corepure64.gz" || true
fi

# Locate extensions directory (cde or tce)
EXTENSION_SRC=""
for path in /cde /mnt/cdrom/cde /mnt/sr0/cde /tce /mnt/cdrom/tce /mnt/sr0/tce /tmp/cde_stage; do
    if [ -d "$path/optional" ]; then
        EXTENSION_SRC="$path"
        break
    fi
done

if [ -n "$EXTENSION_SRC" ]; then
    echo "Copying extensions from $EXTENSION_SRC..."
    cp -a "$EXTENSION_SRC/optional/"* "$MNT_DIR/tce/optional/" 2>/dev/null || true
    if [ -f "$EXTENSION_SRC/onboot.lst" ]; then
        cp "$EXTENSION_SRC/onboot.lst" "$MNT_DIR/tce/onboot.lst"
    fi
fi

# Ensure fowo is in onboot.lst
if [ -f "$MNT_DIR/tce/optional/fowo.tcz" ]; then
    if ! grep -q "fowo.tcz" "$MNT_DIR/tce/onboot.lst" 2>/dev/null; then
        echo "fowo.tcz" >> "$MNT_DIR/tce/onboot.lst"
    fi
fi

echo "[6/6] Installing GRUB2 EFI bootloader..."
if ! command -v grub-install >/dev/null 2>&1; then
    echo "Error: grub-install not found (install grub2-multi.tcz)."
    exit 1
fi

# Create locale directory to suppress harmless grub-install warning
mkdir -p /usr/local/share/locale

grub-install --target=x86_64-efi --efi-directory="$MNT_DIR/boot/efi" --boot-directory="$MNT_DIR/boot" --removable "$TARGET_DEV"

PART_LABEL="$(basename "$ROOT_DEV")"
cat > "$MNT_DIR/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

menuentry "Tiny Core Linux x64 with Fowo" {
    linux /boot/vmlinuz64 quiet waitusb=5 tce=${PART_LABEL}
    initrd /boot/corepure64.gz
}
EOF

echo ""
echo "================================================="
echo " Installation Complete!"
echo " Tiny Core Linux x64 + Fowo installed on $ROOT_DEV"
echo " Bootloader installed on $ESP_DEV"
echo " You may now reboot and boot from $TARGET_DEV."
echo "================================================="
