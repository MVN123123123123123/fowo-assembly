#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
STAGE_DIR="$BUILD_DIR/iso_stage"
CACHE_DIR="$BUILD_DIR/cache"
OUTPUT_ISO="$BUILD_DIR/tinycore-fowo-x64.iso"

echo "================================================="
echo "   Tiny Core Linux x64 + Fowo ISO Builder       "
echo "================================================="
echo ""

mkdir -p "$BUILD_DIR" "$CACHE_DIR" "$STAGE_DIR"

# 1. Step 1: Detect latest TCL x64 release
echo "[1/6] Detecting newest Tiny Core Linux x64 release..."
TCL_VER=""
for ver in 17.x 16.x 15.x; do
    ISO_TEST_URL="http://tinycorelinux.net/${ver}/x86_64/release/CorePure64-current.iso"
    if curl -sI "$ISO_TEST_URL" | grep -q "200 OK"; then
        TCL_VER="$ver"
        echo "Found latest release: TCL $TCL_VER"
        break
    fi
done

if [ -z "$TCL_VER" ]; then
    echo "Warning: Could not auto-detect TCL release online. Falling back to 17.x."
    TCL_VER="17.x"
fi

BASE_ISO_URL="http://tinycorelinux.net/${TCL_VER}/x86_64/release/CorePure64-current.iso"
TCZ_REPO_URL="http://tinycorelinux.net/${TCL_VER}/x86_64/tcz"
CACHED_ISO="$CACHE_DIR/CorePure64-${TCL_VER}.iso"

if [ ! -f "$CACHED_ISO" ]; then
    echo "Downloading $BASE_ISO_URL..."
    curl -sL "$BASE_ISO_URL" -o "$CACHED_ISO"
else
    echo "Using cached ISO: $CACHED_ISO"
fi

# 2. Step 2: Build fowo.tcz
echo "[2/6] Building fowo.tcz package..."
"$SCRIPT_DIR/build-tcz.sh"

# 3. Step 3: Extract base ISO contents
echo "[3/6] Extracting base ISO image..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

if command -v xorriso &>/dev/null; then
    xorriso -osirrox on -indev "$CACHED_ISO" -extract / "$STAGE_DIR" 2>/dev/null || true
elif command -v 7z &>/dev/null; then
    7z x "$CACHED_ISO" -o"$STAGE_DIR" -y >/dev/null
else
    echo "Error: xorriso or 7z required to extract base ISO."
    exit 1
fi

chmod -R u+w "$STAGE_DIR"

# 4. Step 4: Download and stage extensions (cde/optional)
echo "[4/6] Staging fowo.tcz and downloading dependencies..."
CDE_DIR="$STAGE_DIR/cde"
OPTIONAL_DIR="$CDE_DIR/optional"
mkdir -p "$OPTIONAL_DIR"

# Copy fowo artifacts
cp "$BUILD_DIR"/fowo.tcz* "$OPTIONAL_DIR/"

# Recursive TCZ dependency fetcher
FETCHED_DEPS=""

fetch_tcz_recursive() {
    local pkg="$1"
    # Ignore empty or already processed
    [ -z "$pkg" ] && return 0
    echo "$FETCHED_DEPS" | grep -q -w "$pkg" && return 0

    FETCHED_DEPS="$FETCHED_DEPS $pkg"
    echo "  -> Processing dependency: $pkg"

    for ext in "" ".dep" ".info" ".list" ".md5.txt"; do
        local file="${pkg}${ext}"
        local cached_file="$CACHE_DIR/$file"
        local target_file="$OPTIONAL_DIR/$file"

        if [ ! -f "$cached_file" ]; then
            curl -sL "$TCZ_REPO_URL/$file" -o "$cached_file" || true
        fi

        # Check if file was actually found on server (ignore 404 HTML contents)
        if grep -q "404 Not Found" "$cached_file" 2>/dev/null; then
            rm -f "$cached_file"
        elif [ -s "$cached_file" ]; then
            cp "$cached_file" "$target_file"
        fi
    done

    # Parse .dep file for sub-dependencies
    local dep_file="$OPTIONAL_DIR/${pkg}.dep"
    if [ -f "$dep_file" ]; then
        while IFS= read -r subdep || [ -n "$subdep" ]; do
            # Trim whitespace
            subdep=$(echo "$subdep" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ -n "$subdep" ]; then
                fetch_tcz_recursive "$subdep"
            fi
        done < "$dep_file"
    fi
}

# Process dependencies listed in fowo.tcz.dep
if [ -f "$BUILD_DIR/fowo.tcz.dep" ]; then
    while IFS= read -r dep || [ -n "$dep" ]; do
        dep=$(echo "$dep" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$dep" ]; then
            fetch_tcz_recursive "$dep"
        fi
    done < "$BUILD_DIR/fowo.tcz.dep"
fi

# Build onboot.lst
echo "Generating cde/onboot.lst..."
ONBOOT_FILE="$CDE_DIR/onboot.lst"
rm -f "$ONBOOT_FILE"

# Add fowo first, then dependencies
echo "fowo.tcz" >> "$ONBOOT_FILE"
for dep in $FETCHED_DEPS; do
    if [ -f "$OPTIONAL_DIR/$dep" ]; then
        if ! grep -q "^$dep$" "$ONBOOT_FILE"; then
            echo "$dep" >> "$ONBOOT_FILE"
        fi
    fi
done

# Copy installer script into cde
cp "$SCRIPT_DIR/install-tcl-fowo.sh" "$CDE_DIR/install-tcl-fowo.sh"
chmod +x "$CDE_DIR/install-tcl-fowo.sh"

# 5. Step 5: Configure bootloader
echo "[5/6] Configuring bootloader..."
ISOLINUX_DIR="$STAGE_DIR/boot/isolinux"
if [ ! -d "$ISOLINUX_DIR" ]; then
    ISOLINUX_DIR="$STAGE_DIR/boot/syslinux"
fi
mkdir -p "$ISOLINUX_DIR"

cat > "$ISOLINUX_DIR/boot.msg" << 'EOF'
 \17\0e=======================================================\07
 \17\0f   Tiny Core Linux x64 + Fowo Package Manager Live    \07
 \17\0e=======================================================\07

 Press [ENTER] to boot live environment with Fowo,
 or type 'install' to run automated disk installation.

EOF

cat > "$ISOLINUX_DIR/isolinux.cfg" << 'EOF'
DEFAULT live
PROMPT 1
TIMEOUT 600
DISPLAY boot.msg

LABEL live
    KERNEL /boot/vmlinuz64
    INITRD /boot/corepure64.gz
    APPEND loglevel=3 cde quiet

LABEL install
    KERNEL /boot/vmlinuz64
    INITRD /boot/corepure64.gz
    APPEND loglevel=3 cde quiet autofowo
EOF

# 6. Step 6: Generate bootable ISO
echo "[6/6] Packing bootable ISO..."
rm -f "$OUTPUT_ISO"

if command -v xorriso &>/dev/null; then
    xorriso -as mkisofs \
        -o "$OUTPUT_ISO" \
        -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -J -R \
        -V "TCL_FOWO_X64" \
        "$STAGE_DIR"
elif command -v mkisofs &>/dev/null; then
    mkisofs \
        -o "$OUTPUT_ISO" \
        -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -J -R \
        -V "TCL_FOWO_X64" \
        "$STAGE_DIR"
else
    genisoimage \
        -o "$OUTPUT_ISO" \
        -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -J -R \
        -V "TCL_FOWO_X64" \
        "$STAGE_DIR"
fi

if command -v isohybrid &>/dev/null; then
    echo "Applying isohybrid formatting..."
    isohybrid "$OUTPUT_ISO" 2>/dev/null || true
fi

echo ""
echo "================================================="
echo " ISO Generation Successful!"
echo " Output ISO: $OUTPUT_ISO"
echo " Size: $(du -h "$OUTPUT_ISO" | cut -f1)"
echo "================================================="
echo ""
echo "To test in QEMU:"
echo "  qemu-system-x86_64 -m 1024 -cdrom $OUTPUT_ISO -boot d"
