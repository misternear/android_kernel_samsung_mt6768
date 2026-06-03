#!/bin/bash
# Kernel Build Script

# Configuration - EDIT THESE PATHS BEFORE RUNNING
SRCDIR="$(pwd)"
OUT_DIR="$SRCDIR/out"
DEFCONFIG="a32_loop_defconfig"

# Recommended toolchain: https://github.com/ZyCromerZ/Clang/releases/tag/14.0.6-20250704-release
# Paths to toolchains and tools - Replace placeholders with actual paths
ANYKERNEL_DIR="<PATH_TO_ANYKERNEL3_DIRECTORY>"   # e.g., "$HOME/git/kernel/AnyKernel3"
TC_DIR="<PATH_TO_CLANG_TOOLCHAIN_DIRECTORY>"     # e.g., "$HOME/git/kernel/toolchain/Clang-14.0.6-20250704"

# Build options
CLEAN=false
MENUCONFIG=false

# Parse Arguments
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -c, --clean       Clean output directory before building"
    echo "  -m, --menuconfig  Run menuconfig to update configuration, then exit"
    echo "  -h, --help        Show this help message"
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -c|--clean) CLEAN=true; shift ;;
        -m|--menuconfig) MENUCONFIG=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Environment Validation
if [[ "$ANYKERNEL_DIR" == *"<PATH_TO"* ]] || [[ "$TC_DIR" == *"<PATH_TO"* ]]; then
    echo "[-] Error: Please edit the paths in the Configuration section of this script first!"
    exit 1
fi

if [ ! -d "$TC_DIR" ]; then
    echo "[-] Error: Toolchain not found at: $TC_DIR"
    exit 1
fi

# Toolchain & Environment Setup
setup_env() {
    echo "[*] Setting up build environment..."
    export CROSS_COMPILE="$TC_DIR/bin/aarch64-linux-gnu-"
    export CROSS_COMPILE_ARM32="$TC_DIR/bin/arm-linux-gnueabi-"
    export CC="$TC_DIR/bin/clang"
    
    # LLVM toolchain utilities
    export LD="$TC_DIR/bin/ld.lld"
    export OBJCOPY="$TC_DIR/bin/llvm-objcopy"
    export AS="$TC_DIR/bin/llvm-as"
    export NM="$TC_DIR/bin/llvm-nm"
    export STRIP="$TC_DIR/bin/llvm-strip"
    export OBJDUMP="$TC_DIR/bin/llvm-objdump"
    export READELF="$TC_DIR/bin/llvm-readelf"
    
    # Target architecture & parameters
    export ARCH=arm64
    export ANDROID_MAJOR_VERSION=r
    export KCFLAGS=' -w -pipe -O3'
    export KCPPFLAGS=' -O3'
    export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
}

# Build Actions
do_clean() {
    echo "[*] Cleaning output directory..."
    make -C "$SRCDIR" O="$OUT_DIR" clean mrproper -j$(nproc) > /dev/null
}

do_configure() {
    echo "[*] Configuring kernel with $DEFCONFIG..."
    make -C "$SRCDIR" O="$OUT_DIR" -j$(nproc) "$DEFCONFIG" > /dev/null || { echo "[-] Configuration failed!"; exit 1; }
}

do_menuconfig() {
    echo "[*] Running menuconfig..."
    make -C "$SRCDIR" O="$OUT_DIR" -j$(nproc) menuconfig
    # Save the updated config back to the defconfig
    if [ -f "$OUT_DIR/.config" ]; then
        echo "[*] Saving updated config to $SRCDIR/arch/arm64/configs/$DEFCONFIG"
        cp "$OUT_DIR/.config" "$SRCDIR/arch/arm64/configs/$DEFCONFIG"
    fi
}

do_build() {
    echo "[*] Building kernel..."
    make -C "$SRCDIR" O="$OUT_DIR" -j$(nproc) || { echo "[-] Build failed!"; exit 1; }
}

do_package() {
    IMAGE="$OUT_DIR/arch/arm64/boot/Image"
    if [ ! -f "$IMAGE" ]; then
        echo "[-] Error: Built kernel image not found at $IMAGE"
        exit 1
    fi
    
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        echo "[-] Error: AnyKernel3 directory not found at $ANYKERNEL_DIR"
        exit 1
    fi
    
    echo "[*] Packaging kernel into AnyKernel3..."
    cp "$IMAGE" "$ANYKERNEL_DIR/zImage"
    
    (
        cd "$ANYKERNEL_DIR" || exit 1
        ZIP_NAME="kernel-loop.zip"
        zip -r -0 -q "../$ZIP_NAME" . -x "*/.git/*"
        echo "[+] Successfully packaged: $ZIP_NAME"
    )
}

# Main Flow
setup_env

if [ "$CLEAN" = true ]; then
    do_clean
fi

do_configure

if [ "$MENUCONFIG" = true ]; then
    do_menuconfig
    exit 0
fi

do_build
do_package
