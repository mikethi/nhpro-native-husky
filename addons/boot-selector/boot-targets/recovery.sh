#!/bin/sh
# boot-targets/recovery.sh – Android recovery kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Loads an Android recovery kernel from /userdata/.recovery/ and kexecs into it.
# Falls back to the linux target if any step fails.
#
# Required files on userdata (place with scripts/set-target.sh):
#   /userdata/.recovery/kernel    Android recovery kernel (Image.gz-dtb or Image.gz)
#   /userdata/.recovery/initrd    Android recovery ramdisk            (optional)
#   /userdata/.recovery/cmdline   Kernel command line, one line        (optional)
#
# Default cmdline (used when /userdata/.recovery/cmdline is absent):
#   earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8
#   clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma
#   androidboot.mode=recovery
#
# Requires: kexec (static arm64 binary embedded in the initrd by build.sh)

RECOVERY_STORE=".recovery"

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
    echo "boot-selector[recovery]: falling back to linux" >/dev/console
    # shellcheck disable=SC1091
    . /boot-targets/linux.sh
    run_target
}

run_target() {
    echo "boot-selector[recovery]: locating userdata partition" >/dev/console

    USERDATA_DEV="$(_find_userdata 2>/dev/null)" || {
        echo "boot-selector[recovery]: userdata not found" >/dev/console
        _fallback_linux; return
    }

    mkdir -p /run/boot-selector/mnt
    mount -t ext4 -o ro "$USERDATA_DEV" /run/boot-selector/mnt 2>/dev/null || {
        echo "boot-selector[recovery]: cannot mount userdata (${USERDATA_DEV})" >/dev/console
        _fallback_linux; return
    }

    STORE="/run/boot-selector/mnt/${RECOVERY_STORE}"

    if [ ! -f "${STORE}/kernel" ]; then
        echo "boot-selector[recovery]: no kernel at ${STORE}/kernel" >/dev/console
        umount /run/boot-selector/mnt 2>/dev/null || true
        _fallback_linux; return
    fi

    # Copy files out before unmounting
    cp "${STORE}/kernel" /tmp/recovery-kernel
    [ -f "${STORE}/initrd"  ] && cp "${STORE}/initrd"  /tmp/recovery-initrd
    CMDLINE="$(cat "${STORE}/cmdline" 2>/dev/null || \
        printf '%s' "earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma androidboot.mode=recovery")"

    umount /run/boot-selector/mnt 2>/dev/null || true

    echo "boot-selector[recovery]: loading kernel via kexec" >/dev/console

    if [ -f /tmp/recovery-initrd ]; then
        kexec -l /tmp/recovery-kernel \
              --initrd=/tmp/recovery-initrd \
              --append="$CMDLINE"
    else
        kexec -l /tmp/recovery-kernel \
              --append="$CMDLINE"
    fi

    kexec -e
    # kexec -e does not return on success; reaching here means it failed
    echo "boot-selector[recovery]: kexec failed" >/dev/console
    _fallback_linux
}
