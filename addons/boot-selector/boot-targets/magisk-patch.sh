#!/bin/sh
# boot-targets/magisk-patch.sh — Magisk patch mode (U-Boot / boot-selector)
# Google Pixel 8 Pro (husky / zuma)
#
# This target is used by U-Boot's Magisk patch menu entries AND can be
# triggered from the boot-selector via:
#   ./scripts/set-target.sh set magisk-patch
# with the target written to /userdata/.magisk_patch_target
#
# How it works:
#   1. Reads which store to patch from cmdline: patch_target=.android-a
#   2. Mounts userdata
#   3. Runs magiskboot to unpack the stored kernel
#   4. Injects Magisk's init wrapper and binaries
#   5. Repacks the kernel in-place (original saved as kernel.orig)
#   6. Reboots (if patch_reboot=1 in cmdline) or boots linux
#
# The patch-initrd containing magiskboot/magiskinit/magisk64 must be
# prepared on the host first:
#   ./addons/boot-selector/scripts/patch-magisk.sh \
#       --apk Magisk-v27.0.apk --push-adb
#
# Supported patch targets:  .android-a  .android-b  .gsi
# (Recovery variants can also be patched to install Magisk via recovery)
#
# ── dm-verity / ARP note ────────────────────────────────────────────────────
# Magisk patches the kernel to add its own ramdisk overlay which handles
# dm-verity disabling and forceencrypt bypassing at the Android init level.
# This is separate from and complementary to:
#   • vbmeta --disable-verity (partition-level, done at flash time)
#   • androidboot.verifiedbootstate=orange (ABL-level, inherited from cmdline)
# All three layers should be set for the most reliable root setup.

# Magisk binary locations within the patch-initrd
MAGISKBOOT=/magisk/magiskboot
MAGISKINIT=/magisk/magiskinit
MAGISK64=/magisk/magisk64

run_target() {
    # Read patch parameters from /proc/cmdline
    local patch_target="" patch_reboot=""
    for arg in $(cat /proc/cmdline 2>/dev/null); do
        case "$arg" in
            patch_target=*)  patch_target="${arg#*=}"  ;;
            patch_reboot=*)  patch_reboot="${arg#*=}"  ;;
        esac
    done

    if [ -z "$patch_target" ]; then
        # Try the .magisk_patch_target flag file on userdata
        USERDATA_DEV="$(_find_userdata 2>/dev/null)"
        if [ -n "$USERDATA_DEV" ]; then
            mkdir -p /run/boot-selector/mnt
            if mount -t f2fs -o ro "$USERDATA_DEV" /run/boot-selector/mnt \
                     2>/dev/null || \
               mount -t ext4 -o ro "$USERDATA_DEV" /run/boot-selector/mnt \
                     2>/dev/null; then
                if [ -f /run/boot-selector/mnt/.magisk_patch_target ]; then
                    patch_target="$(tr -d '[:space:]' \
                        </run/boot-selector/mnt/.magisk_patch_target)"
                fi
                umount /run/boot-selector/mnt 2>/dev/null || true
            fi
        fi
    fi

    if [ -z "$patch_target" ]; then
        echo "boot-selector[magisk-patch]: ERROR: no patch_target specified" \
             >/dev/console
        echo "  Set via cmdline (boot_target=magisk-patch patch_target=.android-a)" \
             >/dev/console
        echo "  or write target name to /userdata/.magisk_patch_target" \
             >/dev/console
        sleep 5
        _fallback_linux
        return
    fi

    echo "boot-selector[magisk-patch]: patching ${patch_target}" >/dev/console

    # Verify magiskboot is available in the initrd
    if [ ! -x "$MAGISKBOOT" ]; then
        echo "boot-selector[magisk-patch]: ERROR: ${MAGISKBOOT} not found" \
             >/dev/console
        echo "  Run: ./addons/boot-selector/scripts/patch-magisk.sh --push-adb" \
             >/dev/console
        sleep 5
        _fallback_linux
        return
    fi

    USERDATA_DEV="$(_find_userdata 2>/dev/null)" || {
        echo "boot-selector[magisk-patch]: userdata not found" >/dev/console
        _fallback_linux; return
    }

    mkdir -p /run/boot-selector/mnt
    if ! mount -t f2fs "$USERDATA_DEV" /run/boot-selector/mnt 2>/dev/null; then
        if ! mount -t ext4 "$USERDATA_DEV" /run/boot-selector/mnt \
                   2>/dev/null; then
            echo "boot-selector[magisk-patch]: cannot mount userdata (rw)" \
                 >/dev/console
            _fallback_linux; return
        fi
    fi

    local sdir="/run/boot-selector/mnt/${patch_target}"

    if [ ! -f "${sdir}/kernel" ]; then
        echo "boot-selector[magisk-patch]: no kernel at ${sdir}/kernel" \
             >/dev/console
        umount /run/boot-selector/mnt 2>/dev/null || true
        _fallback_linux; return
    fi

    # ── Patch kernel with magiskboot ─────────────────────────────────────────
    local workdir="/tmp/magisk-patch-$$"
    mkdir -p "$workdir"
    cp "${sdir}/kernel" "${workdir}/kernel"

    cd "$workdir" || { _fallback_linux; return; }

    echo "boot-selector[magisk-patch]: unpacking kernel..." >/dev/console
    "$MAGISKBOOT" unpack kernel

    # If a ramdisk was extracted, inject Magisk's init wrapper
    if [ -f ramdisk.cpio ]; then
        echo "boot-selector[magisk-patch]: injecting Magisk into ramdisk..." \
             >/dev/console

        # Back up original init
        "$MAGISKBOOT" cpio ramdisk.cpio \
            "backup .backup/.magisk" 2>/dev/null || true

        # Inject magiskinit as the new init
        cp "$MAGISKINIT" ./magiskinit
        "$MAGISKBOOT" cpio ramdisk.cpio \
            "add 0750 init magiskinit" \
            "mkdir 0750 .backup" \
            "add 0000 .backup/.magisk /dev/null" \
            "add 0755 magisk/magiskinit magiskinit" \
            "add 0755 magisk/magisk64 magisk64"

        # Copy arm64 binaries so Magisk can install itself on first boot
        mkdir -p magisk
        cp "$MAGISKINIT" magisk/magiskinit
        cp "$MAGISK64"   magisk/magisk64
    else
        echo "boot-selector[magisk-patch]: no ramdisk — patching kernel image \
directly" >/dev/console
        # Apply the selinux_enforcing hex patch.
        # This patches two conditional branch instructions that would enforce
        # kernel SELinux enforcing mode, converting them to branches that
        # skip the enforcement check.  Required on some GKI kernels where
        # selinux_enforcing is compiled in and magiskinit cannot override it
        # via the init wrapper alone.
        "$MAGISKBOOT" hexpatch kernel \
            49010054011440B93FA00F71E9000054010840B93FA00F7189000054 \
            A1020054011440B93FA00F7140020054010840B93FA00F71E9010054 \
            2>/dev/null || true
    fi

    echo "boot-selector[magisk-patch]: repacking kernel..." >/dev/console
    "$MAGISKBOOT" repack kernel patched-kernel

    if [ ! -f patched-kernel ]; then
        echo "boot-selector[magisk-patch]: repack failed" >/dev/console
        cd / && rm -rf "$workdir"
        umount /run/boot-selector/mnt 2>/dev/null || true
        _fallback_linux; return
    fi

    # Write patched kernel back to userdata (save original as kernel.orig)
    [ -f "${sdir}/kernel.orig" ] || \
        cp "${sdir}/kernel" "${sdir}/kernel.orig"
    cp patched-kernel "${sdir}/kernel"

    # Clear the patch target flag file
    rm -f /run/boot-selector/mnt/.magisk_patch_target 2>/dev/null || true

    cd / && rm -rf "$workdir"
    sync
    umount /run/boot-selector/mnt 2>/dev/null || true

    echo "" >/dev/console
    echo "boot-selector[magisk-patch]: ✓ ${patch_target}/kernel patched with \
Magisk" >/dev/console
    echo "boot-selector[magisk-patch]: original saved as kernel.orig" \
         >/dev/console
    echo "" >/dev/console

    if [ "$patch_reboot" = "1" ]; then
        echo "boot-selector[magisk-patch]: rebooting in 3 seconds..." \
             >/dev/console
        sleep 3
        reboot -f
    else
        echo "boot-selector[magisk-patch]: done — booting linux" >/dev/console
        sleep 2
        _fallback_linux
    fi
}
