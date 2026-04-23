#!/bin/sh
# boot-targets/android.sh — Android kexec boot target (active slot, auto A/B)
# Google Pixel 8 Pro (husky / zuma)
#
# Boots Android on the A/B slot reported by the ABL-injected
# androidboot.slot_suffix=_a|_b in /proc/cmdline.
# For an explicit slot use android-a.sh or android-b.sh.
#
# Userdata store: /userdata/.android/
#
# ── dm-verity ────────────────────────────────────────────────────────────────
# On an unlocked device the ABL injects:
#   androidboot.verifiedbootstate=orange   → dm-verity relaxed
#   androidboot.vbmeta.device_state=unlocked → AVB enforcement skipped
# Both are inherited from /proc/cmdline and forwarded to the Android kernel.
# Android shows an orange warning screen for a few seconds, then boots.
#
# To fully disable dm-verity (no warning screen):
#   fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
#   (scripts/setup-android.sh handles this automatically)
#
# ── Anti-Rollback Protection (ARP) ──────────────────────────────────────────
# ARP is enforced by the ABL on the bootloader partition (Titan M2-locked).
# When kexec-booting Android, ARP is NOT re-evaluated — the ABL already ran.
# Ensure your Android system/vendor images match your ABL version to avoid
# boot loops after an ABL update.  Never downgrade the ABL.
#
# ── Magisk ───────────────────────────────────────────────────────────────────
# If the stored kernel was patched with Magisk (scripts/patch-magisk.sh or
# via the U-Boot Magisk patch mode), Android boots with root access.
# Magisk's own dm-verity and forceencrypt handling is applied automatically.
#
# ── Setup ────────────────────────────────────────────────────────────────────
# Populate the store with:
#   ./addons/boot-selector/scripts/setup-android.sh --factory-zip <zip>
# Or manually:
#   ./addons/boot-selector/scripts/set-target.sh store-android \
#       --kernel android-kernel.img --initrd android-vendor_boot.img

ANDROID_STORE=".android"

run_target() {
    echo "boot-selector[android]: starting (active slot, auto A/B)" \
         >/dev/console
    local cmdline
    cmdline="$(_build_android_cmdline "" "")"
    _kexec_boot "$ANDROID_STORE" "$cmdline" || _fallback_linux
}
