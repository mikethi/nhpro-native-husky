#!/bin/sh
# boot-targets/android-a.sh — Android slot_a kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Forces androidboot.slot_suffix=_a regardless of the active slot in BCB.
# Use this to boot the A slot even when slot_b is set as active.
#
# Userdata store: /userdata/.android-a/
#
# See android.sh for full notes on dm-verity, ARP, and Magisk.
# See setup-android.sh for how to populate the store.

run_target() {
    echo "boot-selector[android-a]: booting Android slot_a" >/dev/console
    local cmdline
    cmdline="$(_build_android_cmdline "_a" "")"
    _kexec_boot ".android-a" "$cmdline" || _fallback_linux
}
