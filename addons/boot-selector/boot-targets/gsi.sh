#!/bin/sh
# boot-targets/gsi.sh — Android GSI (Generic System Image) kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Boots Android with a Generic System Image flashed to the system_a partition.
# The vendor_a and vendor_boot_a partitions remain as factory stock.
#
# Userdata store: /userdata/.gsi/
# Fallback:       /userdata/.android-a/ (if .gsi/kernel not found)
#
# androidboot.dynamic_partitions=true is required for GSI to correctly mount
# the dynamic logical partitions (system, product, system_ext).
#
# GSI setup:
#   1. Flash GSI to system_a:  fastboot flash system <gsi>.img
#   2. Flash stock vendor_a from factory image (if not already present)
#   3. Run setup-android.sh --gsi to populate the .gsi/ store
#   4. Set boot target:  ./scripts/set-target.sh set gsi
#
# See android.sh for dm-verity, ARP, and Magisk notes.

run_target() {
    echo "boot-selector[gsi]: booting Android GSI (system_a)" >/dev/console

    # Check if a dedicated GSI kernel store exists; fall back to .android-a/
    local store=".gsi"
    USERDATA_DEV="$(_find_userdata 2>/dev/null)"
    if [ -n "$USERDATA_DEV" ]; then
        mkdir -p /run/boot-selector/mnt
        if mount -t f2fs -o ro "$USERDATA_DEV" /run/boot-selector/mnt \
                 2>/dev/null || \
           mount -t ext4 -o ro "$USERDATA_DEV" /run/boot-selector/mnt \
                 2>/dev/null; then
            if [ ! -f "/run/boot-selector/mnt/.gsi/kernel" ]; then
                echo "boot-selector[gsi]: .gsi/kernel not found, \
trying .android-a/" >/dev/console
                store=".android-a"
            fi
            umount /run/boot-selector/mnt 2>/dev/null || true
        fi
    fi

    local cmdline
    cmdline="$(_build_android_cmdline "_a" \
        "androidboot.dynamic_partitions=true")"
    _kexec_boot "$store" "$cmdline" || _fallback_linux
}
