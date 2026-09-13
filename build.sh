#!/bin/sh

KERNEL_DIR=$(pwd)
DEVICE="$1"
DEVICE2="$2"
SOC="$3"

build_kernel() {
    echo "-----------------------------------------------"
    echo "Beginning kernel compilation for $DEVICE..."
    echo "-----------------------------------------------"

    export ARCH=arm64
    mkdir -p out

    export PATH=$(pwd)/llvm-22/bin:$PATH

    KERNEL_MAKE_ENV="DTC_EXT=$(pwd)/tools/dtc CONFIG_BUILD_ARM64_DT_OVERLAY=y"
    BUILD_VAR="-j$(nproc) -C $(pwd) O=$(pwd)/out $KERNEL_MAKE_ENV ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1"

    cat arch/arm64/configs/sdmmagpie_defconfig arch/arm64/configs/$DEVICE.config > arch/arm64/configs/temp_defconfig

    # Wstrzyknięcie wymaganych konfiguracji pamięci, tmpfs i SELinux dla Android init
    echo "
CONFIG_THINLTO=y
# CONFIG_LTO_NONE is not set
CONFIG_LTO_CLANG=y

# Android init PropertyInit() shared memory workspace
CONFIG_ASHMEM=y
CONFIG_MEMFD_CREATE=y
CONFIG_SHMEM=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y

# Boot parameters i SELinux overrides
CONFIG_SECURITY_SELINUX_BOOTPARAM=y
CONFIG_SECURITY_SELINUX_BOOTPARAM_VALUE=0
" >> arch/arm64/configs/temp_defconfig

    make $BUILD_VAR temp_defconfig

    # --- VERIFICATION CHECK ---
    echo "=========================================="
    echo "CHECKING PROPERLY INJECTED CONFIGS:"
    grep -E "CONFIG_TMPFS_XATTR|CONFIG_ASHMEM|CONFIG_MEMFD_CREATE|CONFIG_SHMEM" out/.config
    echo "=========================================="
    
    rm arch/arm64/configs/temp_defconfig
}

build_dtb() {
    echo "-----------------------------------------------"
    echo "Building dtb..."
    echo "-----------------------------------------------"
    make $BUILD_VAR
    make $BUILD_VAR dtbs
}

build_dtbo() {
    echo "-----------------------------------------------"
    echo "Building dtbo.img..."
    echo "-----------------------------------------------"
    DTBO_FILES=$(find $(pwd)/out/arch/arm64/boot/dts/samsung/ -name sm*150-sec-$DEVICE-eur-overlay-*.dtbo)
    $(pwd)/tools/mkdtimg create $(pwd)/out/dtbo.img --page_size=4096 ${DTBO_FILES}
}

prepare_ak3() {
    cd AnyKernel3/

    mv "$KERNEL_DIR/out/dtbo.img" dtbo.img
    mv "$KERNEL_DIR/out/arch/arm64/boot/Image" Image

    mv "$KERNEL_DIR/out/arch/arm64/boot/dts/qcom/$SOC.dtb" dtb

    sed -i "s/^device\.name1=.*/device.name1=${DEVICE}/" anykernel.sh
    sed -i "s/^device\.name2=.*/device.name2=${DEVICE2}/" anykernel.sh

    if [ "$DEVICE" = "a70q" ]; then
        if ! grep -q "androidboot.selinux=" anykernel.sh; then
            awk '
            /^write_boot;/ {
                print "ui_print \" \";"
                print "ui_print \"WARNING: SELinux forced PERMISSIVE for debugging!\";"
                print "ui_print \" \";"
                print "if ! grep -q \"androidboot.selinux=\" /tmp/anykernel/cmdline; then"
                print "    echo -n \" androidboot.selinux=permissive\" >> /tmp/anykernel/cmdline"
                print "else"
                print "    patch_cmdline \"androidboot.selinux\" \"androidboot.selinux=permissive\""
                print "fi"
            }
            { print }
            ' anykernel.sh > anykernel.sh.tmp && mv anykernel.sh.tmp anykernel.sh
        fi
    fi

    cd "$KERNEL_DIR"
}

build_kernel
build_dtb
build_dtbo
prepare_ak3
