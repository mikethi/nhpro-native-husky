#!/bin/sh
# boot-targets/recovery-b.sh — Android Recovery slot_b kexec boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Boots Android Recovery explicitly on slot_b.
# Userdata store: /userdata/.recovery-b/
# See recovery.sh and android.sh for full notes.

run_target() {
    echo "boot-selector[recovery-b]: booting Recovery slot_b" >/dev/console
    local cmdline
    cmdline="$(_build_android_cmdline "_b" "androidboot.mode=recovery")"
    _kexec_boot ".recovery-b" "$cmdline" || _fallback_linux
}
