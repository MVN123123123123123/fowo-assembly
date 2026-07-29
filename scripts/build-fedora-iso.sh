#!/bin/bash
set -e
umask 022

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
STAGE_DIR="/tmp/fowo_fedora_stage"
ISO_STAGE="/tmp/fowo_fedora_iso_stage"
OUTPUT_ISO="$BUILD_DIR/fowo-fedora-x64.iso"

echo "================================================="
echo "   Fedora x64 + Fowo ISO Builder (Minimal)       "
echo "================================================="
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (or use sudo)."
    exit 1
fi

if ! command -v dnf &>/dev/null || ! command -v mksquashfs &>/dev/null || ! command -v grub2-mkrescue &>/dev/null; then
    echo "Error: Required tools not found."
    echo "Please install: dnf, squashfs-tools, grub2-tools, grub2-efi-x64-modules, xorriso"
    exit 1
fi

mkdir -p "$BUILD_DIR"
chmod 755 "$BUILD_DIR"

echo "Ensuring no stale mounts before cleanup..."
umount "$STAGE_DIR/run" 2>/dev/null || true
umount "$STAGE_DIR/sys" 2>/dev/null || true
umount "$STAGE_DIR/proc" 2>/dev/null || true
umount "$STAGE_DIR/dev" 2>/dev/null || true

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
chmod 755 "$STAGE_DIR"

cleanup() {
    echo "Cleaning up mounts..."
    umount "$STAGE_DIR/run" 2>/dev/null || true
    umount "$STAGE_DIR/sys" 2>/dev/null || true
    umount "$STAGE_DIR/proc" 2>/dev/null || true
    umount "$STAGE_DIR/dev" 2>/dev/null || true
}
trap cleanup EXIT

echo "Mounting API filesystems..."
mkdir -p "$STAGE_DIR"/{dev,proc,sys,run}
mount -o bind /dev "$STAGE_DIR/dev"
mount -t proc proc "$STAGE_DIR/proc"
mount -t sysfs sysfs "$STAGE_DIR/sys"
mount -t tmpfs tmpfs "$STAGE_DIR/run"

echo "[1/6] Bootstrapping minimal Fedora rootfs with dnf..."
dnf --use-host-config --installroot="$STAGE_DIR" --releasever=45 --setopt=install_weak_deps=False install -y \
    systemd bash coreutils kernel util-linux iproute iputils passwd \
    dracut-live dracut-network dbus-broker squashfs-tools \
    e2fsprogs dosfstools parted xfsprogs \
    gawk grep sed findutils tar \
    grub2-efi-x64 grub2-pc \
    git gcc gcc-c++ make cmake meson ninja-build bison flex \
    elfutils-libelf-devel openssl-devel ncurses-devel pkgconf pcre2-devel \
    sudo

echo "[2/6] Building and installing fowo..."
make -C "$PROJECT_DIR" all
mkdir -p "$STAGE_DIR/usr/local/bin"
cp "$PROJECT_DIR/build/fowo" "$STAGE_DIR/usr/local/bin/"
chmod 755 "$STAGE_DIR/usr/local/bin/fowo"

cp "$PROJECT_DIR/scripts/install-os.sh" "$STAGE_DIR/usr/local/bin/install-os.sh"
chmod 755 "$STAGE_DIR/usr/local/bin/install-os.sh"
ln -sf install-os.sh "$STAGE_DIR/usr/local/bin/install-os"
mkdir -p "$STAGE_DIR/root"
cp "$PROJECT_DIR/scripts/install-os.sh" "$STAGE_DIR/root/install-os.sh"
chmod 755 "$STAGE_DIR/root/install-os.sh"

echo "[3/6] Configuring rootfs..."
# Set root password to "fowo"
echo "root:fowo" | chroot "$STAGE_DIR" chpasswd

# Explicitly enable getty@tty1 and set default target to multi-user (text mode)
chroot "$STAGE_DIR" systemctl enable getty@tty1.service
chroot "$STAGE_DIR" systemctl set-default multi-user.target

# LiveOS fstab
cat > "$STAGE_DIR/etc/fstab" << 'EOF'
rootfs / tmpfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
tmpfs /dev/shm tmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
sysfs /sys sysfs defaults 0 0
proc /proc proc defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
tmpfs /run tmpfs defaults 0 0
EOF

# Silence kernel console logging via sysctl
cat > "$STAGE_DIR/etc/sysctl.d/20-quiet-printk.conf" << 'EOF'
kernel.printk = 3 4 1 7
EOF

# Ensure /usr/local/bin is first in PATH to mitigate application duplication
cat > "$STAGE_DIR/etc/profile.d/fowo-path.sh" << 'EOF'
export PATH="/usr/local/bin:$PATH"
EOF
chmod 755 "$STAGE_DIR/etc/profile.d/fowo-path.sh"

echo "[4/6] Generating initramfs..."
# Find kernel version
KVER=$(ls -1 "$STAGE_DIR/lib/modules" | head -n 1)
if [ -n "$KVER" ]; then
    chroot "$STAGE_DIR" dracut -N --add "dmsquash-live" -f /boot/initramfs.img --kver "$KVER" --nomdadmconf --nolvmconf
else
    echo "Warning: No kernel found in rootfs!"
fi

echo "[5/6] Creating LiveOS SquashFS..."
rm -rf "$ISO_STAGE"
mkdir -p "$ISO_STAGE/LiveOS" "$ISO_STAGE/boot/grub"

# Unmount before squashing
cleanup

# Re-arm the trap in case subsequent steps fail
trap cleanup EXIT

# Normalize file permissions before squashing
echo "Sanitizing file permissions..."
chmod 755 "$STAGE_DIR"
chmod -R go-w "$STAGE_DIR"
find "$STAGE_DIR" -name "*.conf" -exec chmod 644 {} +
find "$STAGE_DIR/usr/lib/systemd" -type f \( -name "*.service" -o -name "*.target" -o -name "*.socket" -o -name "*.timer" -o -name "*.mount" \) -exec chmod 644 {} + 2>/dev/null || true

mksquashfs "$STAGE_DIR" "$ISO_STAGE/LiveOS/squashfs.img" -comp xz

# Copy kernel and initrd
cp "$STAGE_DIR/boot/vmlinuz-"* "$ISO_STAGE/boot/vmlinuz"
cp "$STAGE_DIR/boot/initramfs.img" "$ISO_STAGE/boot/initrd.img"

echo "[6/6] Generating bootable ISO with grub2-mkrescue..."
cat > "$ISO_STAGE/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0
menuentry "Fowo Minimal Fedora (Live)" {
    linux /boot/vmlinuz root=live:CDLABEL=FOWO_FEDORA rd.live.image quiet loglevel=3 audit=0 selinux=0
    initrd /boot/initrd.img
}
EOF

grub2-mkrescue -o "$OUTPUT_ISO" "$ISO_STAGE" -- -volid "FOWO_FEDORA"

if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$OUTPUT_ISO"
fi
chmod 644 "$OUTPUT_ISO"

echo "[6/6] Done! ISO created at $OUTPUT_ISO"

echo ""
echo "================================================="
echo " Fedora ISO Generation Successful!"
echo " Output ISO: $OUTPUT_ISO"
echo " Size: $(du -h "$OUTPUT_ISO" | cut -f1)"
echo " Root password is 'fowo'."
echo "================================================="
echo ""
