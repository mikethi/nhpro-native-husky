#!/bin/sh
# boot-targets/recovery.sh — Android Recovery kexec boot target (active slot)
# Google Pixel 8 Pro (husky / zuma)
#
# Boots Android Recovery on the active A/B slot.
# For explicit slot use recovery-a.sh or recovery-b.sh.
#
# Userdata store: /userdata/.recovery/
#
# androidboot.mode=recovery causes Android's first-stage init to launch the
# recovery binary instead of the normal system init sequence.
#
# See android.sh for dm-verity, ARP, and Magisk notes — all apply here.
#
# Setup:
#   ./addons/boot-selector/scripts/setup-android.sh --factory-zip <zip>

RECOVERY_STORE=".recovery"

run_target() {
    echo "boot-selector[recovery]: starting (active slot)" >/dev/console
    local cmdline
    cmdline="$(_build_android_cmdline "" "androidboot.mode=recovery")"
    _kexec_boot "$RECOVERY_STORE" "$cmdline" || _fallback_linux
}
