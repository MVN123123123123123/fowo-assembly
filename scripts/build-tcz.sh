#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
STAGE_DIR="/tmp/fowo_tcz_stage"
PKG_NAME="fowo"

echo "=== Fowo TCZ Package Builder ==="
echo ""

# Step 1: Build fowo
echo "[1/5] Building fowo..."
make -C "$PROJECT_DIR" all
echo ""

# Step 2: Check for mksquashfs on build host
if ! command -v mksquashfs &>/dev/null; then
    echo "Error: mksquashfs not found on build host."
    echo "Install squashfs-tools for your distro:"
    echo "  Debian/Ubuntu: sudo apt install squashfs-tools"
    echo "  Fedora/RHEL:   sudo dnf install squashfs-tools"
    echo "  Arch:          sudo pacman -S squashfs-tools"
    exit 1
fi

# Step 3: Create staging directory with TCL filesystem layout
echo "[2/5] Creating staging directory..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/usr/local/bin"

cp "$BUILD_DIR/fowo" "$STAGE_DIR/usr/local/bin/fowo"
strip "$STAGE_DIR/usr/local/bin/fowo" 2>/dev/null || true

# Step 4: Create .tcz SquashFS archive
echo "[3/5] Creating $PKG_NAME.tcz..."
mksquashfs "$STAGE_DIR" "$BUILD_DIR/$PKG_NAME.tcz" -b 4096 -noappend -quiet

# Step 5: Generate metadata files
echo "[4/5] Generating metadata..."

# .dep - runtime dependencies from the official TCL repo
cat > "$BUILD_DIR/$PKG_NAME.tcz.dep" <<EOF
git.tcz
squashfs-tools.tcz
EOF

# .md5.txt
(cd "$BUILD_DIR" && md5sum "$PKG_NAME.tcz" > "$PKG_NAME.tcz.md5.txt")

# .list - files contained in the package
(cd "$STAGE_DIR" && find . -not -type d | sed 's|^\./||') > "$BUILD_DIR/$PKG_NAME.tcz.list"

# .info - package metadata
TCZ_SIZE="$(du -h "$BUILD_DIR/$PKG_NAME.tcz" | cut -f1)"
cat > "$BUILD_DIR/$PKG_NAME.tcz.info" <<EOF
Title:          fowo
Description:    Source-based package manager with TCZ support ( only for TCL)
Version:        1.0
Author:         discord-phobochienxu
Original-site:  
Copying-policy: GPL-3.0-or-later
Size:           $TCZ_SIZE
Extension_by:   discord-phobochienxu
Comments:       Builds packages from git repositories.
                Supports Makefile, CMake, Meson, and Cargo build systems.
                Use --tcz flag to build Tiny Core Linux .tcz packages.
Change-log:     no.
EOF

# Cleanup staging
rm -rf "$STAGE_DIR"

echo "[5/5] Done!"
echo ""
echo "Output:"
ls -lh "$BUILD_DIR/$PKG_NAME.tcz"*
echo ""
echo "=== Install on Tiny Core Linux ==="
echo "  1. Copy these files to /etc/sysconfig/tcedir/optional/:"
echo "     $PKG_NAME.tcz  $PKG_NAME.tcz.dep  $PKG_NAME.tcz.md5.txt"
echo "  2. Run: tce-load -i $PKG_NAME.tcz"
echo "  (tce-load will auto-fetch git.tcz and squashfs-tools.tcz)"
