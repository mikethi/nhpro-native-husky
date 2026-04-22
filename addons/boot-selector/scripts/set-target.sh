#!/usr/bin/env bash
# scripts/set-target.sh – read/write the boot-selector target flag
# Google Pixel 8 Pro (husky / zuma)
#
# Writes (or reads) the /userdata/.boot_target flag file that the selector
# initrd checks on every boot.
#
# Usage:
#   # Set target (persists across reboots until changed)
#   ./scripts/set-target.sh set linux
#   ./scripts/set-target.sh set android
#   ./scripts/set-target.sh set recovery
#   ./scripts/set-target.sh set <custom>     # any name matching boot-targets/<name>.sh
#
#   # Get current target
#   ./scripts/set-target.sh get
#
#   # Clear flag (reverts to built-in default: linux)
#   ./scripts/set-target.sh clear
#
#   # Store Android kernel files on userdata for the android/recovery targets
#   ./scripts/set-target.sh store-android  --kernel <path> [--initrd <path>] [--cmdline <path>]
#   ./scripts/set-target.sh store-recovery --kernel <path> [--initrd <path>] [--cmdline <path>]
#
# Modes:
#   --adb    Use ADB (default when 'adb' is in PATH and device is connected).
#            Requires the device to be booted into Android or NetHunter Pro with
#            ADB enabled, or to be in sideload mode.
#   --direct Mount userdata directly.  Use when running this script ON the device
#            (e.g. from a NetHunter Pro terminal), or on a host where the userdata
#            block device is accessible.  Requires root.
#
# Flag file location: /userdata/.boot_target   (plain text, one line)
# Kernel store paths: /userdata/.android/      /userdata/.recovery/

set -euo pipefail

FLAG_FILE=".boot_target"
ANDROID_STORE=".android"
RECOVERY_STORE=".recovery"

# ── detect connection mode ────────────────────────────────────────────────────
MODE=""
ADB_SERIAL=""

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
    exit 0
}

# Parse global flags before the subcommand
while [[ $# -gt 0 ]]; do
    case "$1" in
        --adb)     MODE="adb";    shift ;;
        --direct)  MODE="direct"; shift ;;
        -s)        ADB_SERIAL="$2"; MODE="adb"; shift 2 ;;
        -h|--help) usage ;;
        --) shift; break ;;
        -*) echo "Unknown flag: $1" >&2; usage ;;
        *)  break ;;
    esac
done

[[ $# -eq 0 ]] && usage

SUBCMD="$1"; shift

# Auto-detect mode
if [[ -z "${MODE}" ]]; then
    if command -v adb >/dev/null 2>&1 && adb devices 2>/dev/null | grep -q "device$"; then
        MODE="adb"
    else
        MODE="direct"
    fi
fi

# ── helpers ───────────────────────────────────────────────────────────────────

_adb() {
    if [[ -n "${ADB_SERIAL}" ]]; then
        adb -s "${ADB_SERIAL}" "$@"
    else
        adb "$@"
    fi
}

# Write a file to userdata via ADB.
# $1 = destination path relative to /data  (e.g. ".boot_target")
# $2 = source file on host (or - for stdin)
_adb_push_to_data() {
    local dest="$1"
    local src="$2"
    if [[ "${src}" == "-" ]]; then
        # Write stdin via a temp file
        local tmp
        tmp="$(mktemp)"
        cat > "${tmp}"
        _adb push "${tmp}" "/data/${dest}"
        rm -f "${tmp}"
    else
        _adb push "${src}" "/data/${dest}"
    fi
    # Ensure world-readable so the initrd's busybox can read it
    _adb shell "chmod 644 /data/${dest}" 2>/dev/null || true
}

# Read a file from userdata via ADB.
_adb_read_data() {
    local path="$1"
    _adb shell "cat /data/${path} 2>/dev/null" || true
}

# Write a file directly to userdata (direct mode, run as root on-device or host).
_direct_write() {
    local dest="$1"   # path relative to userdata mountpoint
    local src="$2"
    local mnt

    mnt="$(_mount_userdata)"
    [[ -z "${mnt}" ]] && { echo "[!] Could not mount userdata" >&2; exit 1; }
    install -Dm644 "${src}" "${mnt}/${dest}"
    _unmount_userdata "${mnt}"
}

_direct_read() {
    local path="$1"
    local mnt
    mnt="$(_mount_userdata ro)"
    [[ -z "${mnt}" ]] && { echo "[!] Could not mount userdata" >&2; exit 1; }
    cat "${mnt}/${path}" 2>/dev/null || true
    _unmount_userdata "${mnt}"
}

# Find and mount userdata by GPT label; print mountpoint on success.
_mount_userdata() {
    local opts="${1:-rw}"
    local mnt
    mnt="$(mktemp -d)"
    local dev=""

    for candidate in /dev/sda* /dev/nvme0n1p* /dev/mmcblk0p*; do
        [[ -b "${candidate}" ]] || continue
        local lbl
        lbl="$(blkid -o value -s PARTLABEL "${candidate}" 2>/dev/null)" || continue
        if [[ "${lbl}" == "userdata" ]]; then
            dev="${candidate}"
            break
        fi
    done

    if [[ -z "${dev}" ]]; then
        rmdir "${mnt}"
        return 1
    fi

    if ! mount -t ext4 -o "${opts}" "${dev}" "${mnt}" 2>/dev/null; then
        rmdir "${mnt}"
        return 1
    fi

    echo "${mnt}"
}

_unmount_userdata() {
    local mnt="$1"
    umount "${mnt}" 2>/dev/null || true
    rmdir  "${mnt}" 2>/dev/null || true
}

# ── subcommand: get ───────────────────────────────────────────────────────────
cmd_get() {
    local val=""
    case "${MODE}" in
        adb)    val="$(_adb_read_data "${FLAG_FILE}")" ;;
        direct) val="$(_direct_read   "${FLAG_FILE}")" ;;
    esac

    if [[ -z "${val}" ]]; then
        echo "linux  (default – no flag file set)"
    else
        echo "${val}"
    fi
}

# ── subcommand: set ───────────────────────────────────────────────────────────
cmd_set() {
    local target="${1:-}"
    [[ -z "${target}" ]] && { echo "[!] set requires a target name" >&2; usage; }

    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "${target}" > "${tmp}"

    case "${MODE}" in
        adb)    _adb_push_to_data "${FLAG_FILE}" "${tmp}" ;;
        direct) _direct_write      "${FLAG_FILE}" "${tmp}" ;;
    esac
    rm -f "${tmp}"

    echo "[+] Boot target set to: ${target}"
    echo "    Takes effect on next reboot."
}

# ── subcommand: clear ─────────────────────────────────────────────────────────
cmd_clear() {
    case "${MODE}" in
        adb)    _adb shell "rm -f /data/${FLAG_FILE}" 2>/dev/null || true ;;
        direct)
            local mnt
            mnt="$(_mount_userdata)"
            rm -f "${mnt}/${FLAG_FILE}" 2>/dev/null || true
            _unmount_userdata "${mnt}"
            ;;
    esac
    echo "[+] Boot target cleared (will default to: linux)"
}

# ── subcommand: store-android / store-recovery ────────────────────────────────
cmd_store() {
    local store_dir="$1"; shift   # .android or .recovery
    local kernel="" initrd="" cmdline_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kernel)  kernel="$2";       shift 2 ;;
            --initrd)  initrd="$2";       shift 2 ;;
            --cmdline) cmdline_file="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; usage ;;
        esac
    done

    [[ -z "${kernel}" ]] && { echo "[!] --kernel is required" >&2; exit 1; }
    [[ ! -f "${kernel}" ]] && { echo "[!] File not found: ${kernel}" >&2; exit 1; }

    case "${MODE}" in
        adb)
            _adb shell "mkdir -p /data/${store_dir}"
            _adb_push_to_data "${store_dir}/kernel" "${kernel}"
            [[ -n "${initrd}"       ]] && _adb_push_to_data "${store_dir}/initrd"  "${initrd}"
            [[ -n "${cmdline_file}" ]] && _adb_push_to_data "${store_dir}/cmdline" "${cmdline_file}"
            ;;
        direct)
            local mnt
            mnt="$(_mount_userdata)"
            mkdir -p "${mnt}/${store_dir}"
            install -m644 "${kernel}" "${mnt}/${store_dir}/kernel"
            [[ -n "${initrd}"       ]] && install -m644 "${initrd}"       "${mnt}/${store_dir}/initrd"
            [[ -n "${cmdline_file}" ]] && install -m644 "${cmdline_file}" "${mnt}/${store_dir}/cmdline"
            _unmount_userdata "${mnt}"
            ;;
    esac

    echo "[+] Stored kernel files in /userdata/${store_dir}/"
    echo "    Run: ./scripts/set-target.sh set ${store_dir#.}"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
case "${SUBCMD}" in
    get)             cmd_get ;;
    set)             cmd_set "$@" ;;
    clear)           cmd_clear ;;
    store-android)   cmd_store "${ANDROID_STORE}"  "$@" ;;
    store-recovery)  cmd_store "${RECOVERY_STORE}" "$@" ;;
    *) echo "Unknown subcommand: ${SUBCMD}" >&2; usage ;;
esac
