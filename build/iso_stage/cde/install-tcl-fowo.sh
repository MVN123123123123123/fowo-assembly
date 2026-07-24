#!/bin/sh
# install-tcl-fowo.sh - Installs Tiny Core Linux x64 + Fowo to disk
set -e

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

echo "[2/6] Partitioning $TARGET_DEV..."
# Create MBR partition table and 1 bootable primary partition spanning full disk
dd if=/dev/zero of="$TARGET_DEV" bs=512 count=2048 status=none || true
if command -v parted >/dev/null 2>&1; then
    parted -s "$TARGET_DEV" mklabel mdos
    parted -s "$TARGET_DEV" mkpart primary ext4 1MiB 100%
    parted -s "$TARGET_DEV" set 1 boot on
elif command -v fdisk >/dev/null 2>&1; then
    (
      echo o # Clear partition table
      echo n # New partition
      echo p # Primary
      echo 1 # Partition 1
      echo   # Default first sector
      echo   # Default last sector
      echo a # Make bootable
      echo w # Write
    ) | fdisk "$TARGET_DEV" >/dev/null 2>&1 || true
else
    echo "Error: Neither parted nor fdisk found."
    exit 1
fi

# Detect partition name (e.g. /dev/sda1 or /dev/nvme0n1p1)
if [ -b "${TARGET_DEV}1" ]; then
    PART_DEV="${TARGET_DEV}1"
elif [ -b "${TARGET_DEV}p1" ]; then
    PART_DEV="${TARGET_DEV}p1"
else
    PART_DEV="${TARGET_DEV}1"
fi

# Wait for kernel to register partition
sleep 2

echo "[3/6] Formatting partition $PART_DEV..."
if command -v mkfs.ext4 >/dev/null 2>&1; then
    mkfs.ext4 -F "$PART_DEV"
elif command -v mke2fs >/dev/null 2>&1; then
    mke2fs -t ext4 -F "$PART_DEV"
elif command -v mkfs.ext2 >/dev/null 2>&1; then
    mkfs.ext2 -F "$PART_DEV"
else
    echo "Error: No filesystem format utility found (mkfs.ext4 / mke2fs / mkfs.ext2)."
    exit 1
fi

MNT_DIR="/tmp/tcl_install_target"
mkdir -p "$MNT_DIR"

echo "[4/6] Mounting $PART_DEV to $MNT_DIR..."
mount "$PART_DEV" "$MNT_DIR"

# Cleanup trap
cleanup() {
    umount "$MNT_DIR" 2>/dev/null || true
    rmdir "$MNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "[5/6] Copying system files & fowo extensions..."
mkdir -p "$MNT_DIR/boot/extlinux"
mkdir -p "$MNT_DIR/tce/optional"

# Locate kernel and corepure64 initrd
VMLINUZ=""
COREGZ=""

for path in /boot/vmlinuz64 /mnt/cdrom/boot/vmlinuz64 /cde/boot/vmlinuz64 /tmp/iso_mount/boot/vmlinuz64; do
    if [ -f "$path" ]; then
        VMLINUZ="$path"
        break
    fi
done

for path in /boot/corepure64.gz /mnt/cdrom/boot/corepure64.gz /cde/boot/corepure64.gz /tmp/iso_mount/boot/corepure64.gz; do
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
for path in /cde /mnt/cdrom/cde /tce /mnt/cdrom/tce /tmp/cde_stage; do
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

echo "[6/6] Installing bootloader..."
# Create bootloader config
PART_LABEL="$(basename "$PART_DEV")"
cat > "$MNT_DIR/boot/extlinux/extlinux.conf" << EOF
DEFAULT tcl-fowo
PROMPT 0
TIMEOUT 30

LABEL tcl-fowo
    MENU LABEL Tiny Core Linux x64 with Fowo
    KERNEL /boot/vmlinuz64
    INITRD /boot/corepure64.gz
    APPEND quiet waitusb=5 tce=${PART_LABEL}
EOF

# Install extlinux / syslinux bootloader if available
if command -v extlinux >/dev/null 2>&1; then
    extlinux --install "$MNT_DIR/boot/extlinux" || true
elif command -v syslinux >/dev/null 2>&1; then
    syslinux --install "$PART_DEV" || true
fi

# Install MBR if mbr.bin exists
for mbr in /usr/lib/EXTLINUX/mbr.bin /usr/lib/syslinux/mbr/mbr.bin /usr/share/syslinux/mbr.bin /usr/lib/syslinux/bios/mbr.bin; do
    if [ -f "$mbr" ]; then
        echo "Writing MBR from $mbr to $TARGET_DEV..."
        dd if="$mbr" of="$TARGET_DEV" bs=440 count=1 conv=notrunc status=none || true
        break
    fi
done

echo ""
echo "================================================="
echo " Installation Complete!"
echo " Tiny Core Linux x64 + Fowo installed on $PART_DEV"
echo " You may now reboot and boot from $TARGET_DEV."
echo "================================================="
