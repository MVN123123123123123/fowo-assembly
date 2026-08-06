#!/bin/bash
set -e
umask 022

USE_CONTAINER=0
while getopts "c" opt; do
    case "$opt" in
        c)
            USE_CONTAINER=1
            ;;
        *)
            echo "Usage: $0 [-c]"
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$USE_CONTAINER" -eq 1 ]; then
    echo "================================================="
    echo "   Running build in a Fedora container...        "
    echo "================================================="
    if command -v podman &>/dev/null; then
        CONTAINER_ENGINE="podman"
    elif command -v docker &>/dev/null; then
        CONTAINER_ENGINE="docker"
    else
        echo "Error: Neither podman nor docker found."
        exit 1
    fi
    
    exec $CONTAINER_ENGINE run --rm --privileged \
        -v "$PROJECT_DIR:/workspace" \
        -w /workspace \
        fedora:latest \
        /bin/bash -c "dnf install -y dnf squashfs-tools grub2-tools grub2-tools-extra grub2-efi-x64-modules grub2-pc-modules xorriso gcc nasm make curl && /workspace/scripts/build-fedora-iso.sh"
fi

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

if ! command -v dnf &>/dev/null || ! command -v mksquashfs &>/dev/null || ! command -v grub2-mkrescue &>/dev/null || ! command -v curl &>/dev/null; then
    echo "Error: Required tools not found."
    echo "Please install: dnf, squashfs-tools, grub2-tools, grub2-efi-x64-modules, xorriso, curl"
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
    systemd bash coreutils kernel util-linux iproute iputils passwd nano \
    dracut-live dracut-network dbus-broker squashfs-tools \
    e2fsprogs dosfstools parted xfsprogs \
    gawk grep sed findutils tar diffutils bc perl rsync kmod \
    grub2-efi-x64 grub2-pc \
    git gcc gcc-c++ make cmake meson ninja-build bison flex \
    autoconf automake libtool m4 patch \
    elfutils-libelf-devel openssl-devel ncurses-devel pkgconf pcre2-devel \
    sudo nc fbida dnf5 \
    fontconfig google-noto-sans-fonts google-noto-cjk-fonts dejavu-sans-fonts glibc-all-langpacks glibc-gconv-extra kbd kbd-misc

echo "[2/6] Building and installing fowo..."
make -C "$PROJECT_DIR" all
mkdir -p "$STAGE_DIR/usr/local/bin"
cp "$PROJECT_DIR/build/fowo" "$STAGE_DIR/usr/local/bin/"
chmod 755 "$STAGE_DIR/usr/local/bin/fowo"

echo "Downloading haruka_installer from latest release..."
curl -L -o "$STAGE_DIR/usr/local/bin/haruka_installer" "https://github.com/MVN123123123123123/funny-random-fork/releases/download/latest/haruka_installer" || {
    echo "Warning: Failed to download haruka_installer. It might not be built or published yet."
}
chmod 755 "$STAGE_DIR/usr/local/bin/haruka_installer" 2>/dev/null || true
ln -sf haruka_installer "$STAGE_DIR/usr/local/bin/install-os"

cp "$PROJECT_DIR/scripts/update-debug.sh" "$STAGE_DIR/usr/local/bin/update-debug.sh"
chmod 755 "$STAGE_DIR/usr/local/bin/update-debug.sh"
ln -sf update-debug.sh "$STAGE_DIR/usr/local/bin/update-debug"

mkdir -p "$STAGE_DIR/root"
cp "$STAGE_DIR/usr/local/bin/haruka_installer" "$STAGE_DIR/root/install-os" 2>/dev/null || true
chmod 755 "$STAGE_DIR/root/install-os" 2>/dev/null || true
cp "$PROJECT_DIR/scripts/update-debug.sh" "$STAGE_DIR/root/update-debug.sh"
chmod 755 "$STAGE_DIR/root/update-debug.sh"

echo "[3/6] Configuring rootfs..."
# Set root password to "fowo"
echo "root:fowo" | chroot "$STAGE_DIR" chpasswd

# Prepare pixmaps directory for custom splash images
mkdir -p "$STAGE_DIR/usr/share/pixmaps"

# Configure Framebuffer Splash systemd service (fbida / fbi)
cat > "$STAGE_DIR/etc/systemd/system/fowo-splash.service" << 'EOF'
[Unit]
Description=Fowo OS Framebuffer Splash Screen
DefaultDependencies=no
After=systemd-udev-settle.service
Before=getty@tty1.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'if [ -f /usr/share/pixmaps/fowo_splash.png ]; then /usr/bin/fbi -T 1 -d /dev/fb0 --noverbose -a /usr/share/pixmaps/fowo_splash.png; fi'
StandardOutput=tty
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Explicitly enable getty@tty1, fowo-splash and set default target to multi-user (text mode)
chroot "$STAGE_DIR" systemctl enable fowo-splash.service
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

# Ensure /usr/local/bin is first in PATH to mitigate application duplication and set UTF-8 locale
cat > "$STAGE_DIR/etc/profile.d/fowo-path.sh" << 'EOF'
export PATH="/usr/local/bin:$PATH"
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"
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
chmod -R go-w "$STAGE_DIR" 2>/dev/null || true
find "$STAGE_DIR" -type f -name "*.conf" -exec chmod 644 {} + 2>/dev/null || true
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
