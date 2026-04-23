#!/bin/sh
# boot-targets/_common.sh — shared helpers for all boot-selector targets
# Google Pixel 8 Pro (husky / zuma)
#
# Sourced by /init BEFORE the individual target script, so every target
# can call these functions without redefining them.
#
# Functions provided:
#   _find_userdata          — find the userdata block device by GPT label
#   _android_inherited_params — extract androidboot.* from /proc/cmdline
#   _set_slot_suffix        — replace/append androidboot.slot_suffix
#   _set_boot_mode          — replace/append androidboot.mode
#   _build_android_cmdline  — compose full Android cmdline (with ABL params)
#   _kexec_boot             — load kernel+initrd from userdata store, kexec
#   _fallback_linux         — fall back to the linux target on any failure

# ── Find userdata block device by GPT PARTLABEL ──────────────────────────────
_find_userdata() {
    for dev in /dev/sda* /dev/nvme0n1p* /dev/mmcblk0p*; do
        [ -b "$dev" ] || continue
        label="$(blkid -o value -s PARTLABEL "$dev" 2>/dev/null)" || continue
        [ "$label" = "userdata" ] && echo "$dev" && return 0
    done
    return 1
}

# ── Extract all androidboot.* tokens from /proc/cmdline ──────────────────────
# The ABL injected these when it loaded the Sultan kernel. Forwarding them to
# Android/Recovery ensures identical verified-boot state, A/B slot,
# dm-verity mode, and UFS device path as if ABL had booted Android directly.
#
# Key params forwarded:
#   androidboot.verifiedbootstate=orange  → unlocked device, dm-verity relaxed
#   androidboot.vbmeta.device_state=unlocked → Android init skips strict AVB
#   androidboot.slot_suffix=_a|_b         → A/B partition selection
#   androidboot.selinux=permissive        → prevents SELinux early-boot denials
#   androidboot.boot_devices=13200000.ufs → UFS path for ueventd rules
#   androidboot.hardware=zuma             → device identity
_android_inherited_params() {
    local result=""
    for arg in $(cat /proc/cmdline 2>/dev/null); do
        case "$arg" in
            androidboot.*) result="${result} ${arg}" ;;
        esac
    done
    printf '%s' "${result# }"
}

# ── Replace/append androidboot.slot_suffix in a cmdline string ───────────────
# $1 = original cmdline string
# $2 = desired suffix (_a or _b)
_set_slot_suffix() {
    local cmdline="$1" suffix="$2" out="" found=""
    for tok in ${cmdline}; do
        case "$tok" in
            androidboot.slot_suffix=*)
                out="${out} androidboot.slot_suffix=${suffix}"
                found=1 ;;
            *) out="${out} ${tok}" ;;
        esac
    done
    [ -z "$found" ] && out="${out} androidboot.slot_suffix=${suffix}"
    printf '%s' "${out# }"
}

# ── Replace/append androidboot.mode in a cmdline string ──────────────────────
# $1 = original cmdline string
# $2 = desired mode (e.g. recovery)
_set_boot_mode() {
    local cmdline="$1" mode="$2" out="" found=""
    for tok in ${cmdline}; do
        case "$tok" in
            androidboot.mode=*)
                out="${out} androidboot.mode=${mode}"
                found=1 ;;
            *) out="${out} ${tok}" ;;
        esac
    done
    [ -z "$found" ] && out="${out} androidboot.mode=${mode}"
    printf '%s' "${out# }"
}

# ── Build a complete Android/Recovery cmdline ────────────────────────────────
# Inherits all androidboot.* from /proc/cmdline (ABL-injected), then applies
# any slot or mode overrides requested by the caller.
#
# Usage: _build_android_cmdline [slot_suffix_override] [extra_params]
#   slot_suffix_override  — "_a", "_b", or "" for auto (no override)
#   extra_params          — appended verbatim (e.g. "androidboot.mode=recovery")
_build_android_cmdline() {
    local slot_override="${1:-}" extra="${2:-}"
    local inherited

    inherited="$(_android_inherited_params)"

    # If no androidboot.* found in /proc/cmdline (non-ABL kernel or custom
    # kernel that doesn't forward ABL params), use safe defaults for an
    # unlocked husky device.
    # NOTE: slot_suffix defaults to _a. If your active slot is _b and you
    # have no androidboot.* in /proc/cmdline, use android-b.sh explicitly
    # or write a cmdline file with the correct slot to the target's store.
    if [ -z "$inherited" ]; then
        echo "boot-selector[_common]: WARNING: no androidboot.* in /proc/cmdline" \
             "— using safe defaults (unlocked husky)" >/dev/console
        inherited="androidboot.hardware=zuma \
androidboot.vbmeta.device_state=unlocked \
androidboot.verifiedbootstate=orange \
androidboot.selinux=permissive \
androidboot.slot_suffix=_a \
androidboot.boot_devices=13200000.ufs"
    fi

    # Log key params for diagnostics
    for p in ${inherited}; do
        case "$p" in
            androidboot.verifiedbootstate=*| \
            androidboot.vbmeta.device_state=*| \
            androidboot.slot_suffix=*)
                echo "boot-selector[_common]: ${p}" >/dev/console ;;
        esac
    done

    # dm-verity warning: if verifiedbootstate is not orange (unlocked),
    # dm-verity may block Android from booting.
    local vbs=""
    for p in ${inherited}; do
        case "$p" in androidboot.verifiedbootstate=*) vbs="${p#*=}" ;; esac
    done
    if [ -n "$vbs" ] && [ "$vbs" != "orange" ]; then
        echo "boot-selector[_common]: WARNING: verifiedbootstate=${vbs}" \
             "(expected 'orange' on unlocked device)" >/dev/console
        echo "boot-selector[_common]: WARNING: dm-verity may prevent Android" \
             "boot. Fix: fastboot flash vbmeta --disable-verity vbmeta.img" \
             >/dev/console
    fi

    # Assemble base cmdline
    local cmdline
    cmdline="earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 \
clk_ignore_unused swiotlb=noforce ${inherited}"

    # Apply slot suffix override
    if [ -n "$slot_override" ]; then
        cmdline="$(_set_slot_suffix "$cmdline" "$slot_override")"
    fi

    # Append extra params
    if [ -n "$extra" ]; then
        cmdline="${cmdline} ${extra}"
    fi

    printf '%s' "$cmdline"
}

# ── Load kernel+initrd from userdata store and kexec into it ─────────────────
# $1 = store directory name (e.g. ".android-a")
# $2 = default cmdline (used if no cmdline file in store; may be empty)
#
# Priority for cmdline:
#   1. /userdata/<store>/cmdline  (explicit user override, full replacement)
#   2. $2 (computed default built by caller)
#
# Returns 1 on any failure (caller should _fallback_linux).
_kexec_boot() {
    local store="$1" default_cmdline="$2"

    USERDATA_DEV="$(_find_userdata 2>/dev/null)" || {
        echo "boot-selector[_common]: userdata block device not found" \
             >/dev/console
        return 1
    }

    mkdir -p /run/boot-selector/mnt
    if ! mount -t f2fs -o ro "$USERDATA_DEV" /run/boot-selector/mnt \
               2>/dev/null; then
        if ! mount -t ext4 -o ro "$USERDATA_DEV" \
                   /run/boot-selector/mnt 2>/dev/null; then
            echo "boot-selector[_common]: cannot mount userdata \
(${USERDATA_DEV})" >/dev/console
            return 1
        fi
    fi

    local sdir="/run/boot-selector/mnt/${store}"

    if [ ! -f "${sdir}/kernel" ]; then
        echo "boot-selector[_common]: no kernel at ${sdir}/kernel" \
             >/dev/console
        umount /run/boot-selector/mnt 2>/dev/null || true
        return 1
    fi

    # Copy files out of the mount before unmounting
    cp "${sdir}/kernel" /tmp/bs-kernel

    rm -f /tmp/bs-initrd
    [ -f "${sdir}/initrd" ] && cp "${sdir}/initrd" /tmp/bs-initrd

# Cmdline: stored file wins over computed default
    local cmdline="$default_cmdline"
    if [ -f "${sdir}/cmdline" ]; then
        # IMPORTANT: the stored cmdline is used as a FULL REPLACEMENT for the
        # computed default.  It must include ALL required params — including
        # androidboot.* tokens — because the computed default will not be
        # merged in.  Use this only when you need complete control over the
        # cmdline (e.g. custom slot suffix or specific selinux mode).
        # If you just need to append params, leave the cmdline file absent
        # and let _build_android_cmdline() handle inheritance from ABL.
        cmdline="$(cat "${sdir}/cmdline")"
        echo "boot-selector[_common]: using stored cmdline from ${store}/cmdline \
(FULL OVERRIDE — ensure all androidboot.* params are present)" >/dev/console
    fi

    umount /run/boot-selector/mnt 2>/dev/null || true

    if [ -z "$cmdline" ]; then
        echo "boot-selector[_common]: ERROR: no cmdline for ${store}" \
             >/dev/console
        return 1
    fi

    echo "boot-selector[_common]: kexec into ${store}" >/dev/console

    if [ -f /tmp/bs-initrd ]; then
        kexec -l /tmp/bs-kernel \
              --initrd=/tmp/bs-initrd \
              --append="$cmdline"
    else
        kexec -l /tmp/bs-kernel \
              --append="$cmdline"
    fi

    kexec -e
    # kexec -e does not return on success; reaching here means it failed
    echo "boot-selector[_common]: kexec failed" >/dev/console
    return 1
}

# ── Fall back to the linux (NetHunter Pro) target ────────────────────────────
_fallback_linux() {
    echo "boot-selector[_common]: falling back to linux target" >/dev/console
    # shellcheck disable=SC1091
    . /boot-targets/linux.sh
    run_target
}
