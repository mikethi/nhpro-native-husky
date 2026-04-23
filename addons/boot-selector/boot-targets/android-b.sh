#!/bin/sh
# boot-targets/android-b.sh — Android slot_b kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Forces androidboot.slot_suffix=_b regardless of the active slot in BCB.
# Use this to boot the B slot even when slot_a is set as active.
#
# Userdata store: /userdata/.android-b/
#
# See android.sh for full notes on dm-verity, ARP, and Magisk.
# See setup-android.sh for how to populate the store.

run_target() {
    echo "boot-selector[android-b]: booting Android slot_b" >/dev/console
    local cmdline
    cmdline="$(_build_android_cmdline "_b" "")"
    _kexec_boot ".android-b" "$cmdline" || _fallback_linux
}
