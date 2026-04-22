#!/bin/sh
# boot-targets/android.sh – Android kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Loads an Android kernel from /userdata/.android/ and kexecs into it.
# Falls back to the linux target if any step fails.
#
# Required files on userdata (place with scripts/set-target.sh):
#   /userdata/.android/kernel    Android kernel image (Image.gz-dtb or Image.gz)
#   /userdata/.android/initrd    Android vendor_ramdisk / initrd  (optional)
#   /userdata/.android/cmdline   Kernel command line, one line     (optional)
#
# Default cmdline (used when /userdata/.android/cmdline is absent):
#   earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8
#   clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma
#
# Requires: kexec (static arm64 binary embedded in the initrd by build.sh)

ANDROID_STORE=".android"

# ── locate userdata block device by GPT partition label ──────────────────────
_find_userdata() {
    for dev in /dev/sda* /dev/nvme0n1p* /dev/mmcblk0p*; do
        [ -b "$dev" ] || continue
        label="$(blkid -o value -s PARTLABEL "$dev" 2>/dev/null)" || continue
        [ "$label" = "userdata" ] && echo "$dev" && return 0
    done
    return 1
}

_fallback_linux() {
    echo "boot-selector[android]: falling back to linux" >/dev/console
    # shellcheck disable=SC1091
    . /boot-targets/linux.sh
    run_target
}

run_target() {
    echo "boot-selector[android]: locating userdata partition" >/dev/console

    USERDATA_DEV="$(_find_userdata 2>/dev/null)" || {
        echo "boot-selector[android]: userdata not found" >/dev/console
        _fallback_linux; return
    }

    mkdir -p /run/boot-selector/mnt
    mount -t ext4 -o ro "$USERDATA_DEV" /run/boot-selector/mnt 2>/dev/null || {
        echo "boot-selector[android]: cannot mount userdata (${USERDATA_DEV})" >/dev/console
        _fallback_linux; return
    }

    STORE="/run/boot-selector/mnt/${ANDROID_STORE}"

    if [ ! -f "${STORE}/kernel" ]; then
        echo "boot-selector[android]: no kernel at ${STORE}/kernel" >/dev/console
        umount /run/boot-selector/mnt 2>/dev/null || true
        _fallback_linux; return
    fi

    # Copy files out before unmounting
    cp "${STORE}/kernel" /tmp/android-kernel
    [ -f "${STORE}/initrd"  ] && cp "${STORE}/initrd"  /tmp/android-initrd
    CMDLINE="$(cat "${STORE}/cmdline" 2>/dev/null || \
        printf '%s' "earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma")"

    umount /run/boot-selector/mnt 2>/dev/null || true

    echo "boot-selector[android]: loading kernel via kexec" >/dev/console

    if [ -f /tmp/android-initrd ]; then
        kexec -l /tmp/android-kernel \
              --initrd=/tmp/android-initrd \
              --append="$CMDLINE"
    else
        kexec -l /tmp/android-kernel \
              --append="$CMDLINE"
    fi

    kexec -e
    # kexec -e does not return on success; reaching here means it failed
    echo "boot-selector[android]: kexec failed" >/dev/console
    _fallback_linux
}
