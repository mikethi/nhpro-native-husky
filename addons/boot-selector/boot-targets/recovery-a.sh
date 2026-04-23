#!/bin/sh
# boot-targets/recovery-a.sh — Android Recovery slot_a kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Boots Android Recovery explicitly on slot_a.
# Userdata store: /userdata/.recovery-a/
# See recovery.sh and android.sh for full notes.

run_target() {
    echo "boot-selector[recovery-a]: booting Recovery slot_a" >/dev/console
    local cmdline
    cmdline="$(_build_android_cmdline "_a" "androidboot.mode=recovery")"
    _kexec_boot ".recovery-a" "$cmdline" || _fallback_linux
}
