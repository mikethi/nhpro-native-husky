#!/usr/bin/env bash
# patch-magisk.sh — prepare the Magisk patch environment for U-Boot / boot-selector
# Google Pixel 8 Pro (husky / zuma)
#
# This script runs on the HOST and:
#   1. Extracts magiskboot (host arch), magiskinit, magisk64 (arm64) from the
#      Magisk APK (which is a ZIP file).
#   2. Builds a minimal patch-initrd.cpio.gz containing those binaries and
#      a /init script (boot-targets/magisk-patch.sh).
#   3. Pushes the patch-initrd and magiskboot to /data/.magisk/ on the device
#      via ADB (--push-adb) or stores locally (--output-dir).
#
# Usage:
#   ./patch-magisk.sh --apk Magisk-v27.0.apk [OPTIONS]
#
# Options:
#   --apk       <file>    Magisk APK file (required)
#   --push-adb            Push patch-initrd to device via ADB  (default if ADB connected)
#   --output-dir <dir>    Save files locally instead of pushing
#   --adb-serial <serial> Target a specific ADB device
#   -n, --dry-run         Show plan without doing anything
#   -h, --help            Show this message
#
# After running this script, trigger Magisk patching from U-Boot or boot-selector:
#
#   Via U-Boot boot menu:
#     Select "Magisk: patch android-a" (or android-b / GSI) from the menu.
#     U-Boot boots the Sultan kernel + patch-initrd; patching runs automatically.
#
#   Via boot-selector (fastboot one-shot):
#     fastboot boot -c 'boot_target=magisk-patch patch_target=.android-a' \
#                   boot-selector.img
#
#   Via flag files (persistent):
#     echo ".android-a" | adb shell "cat > /data/.magisk_patch_target"
#     ./scripts/set-target.sh set magisk-patch
#     # reboot → patches android-a → reboots back to linux
#
# Supported patch targets:
#   .android-a   Android slot_a kernel
#   .android-b   Android slot_b kernel
#   .gsi         GSI kernel
#   .recovery-a  Recovery slot_a kernel  (Magisk recovery — for management)
#   .recovery-b  Recovery slot_b kernel
#
# Combinations supported:
#   linux only          — no Magisk needed
#   android-a + Magisk  — root on slot_a, clean on slot_b
#   android-b + Magisk  — root on slot_b, clean on slot_a
#   both slots          — root on both (run patch twice)
#   GSI + Magisk        — rooted GSI
#   GSI + Magisk + recovery-a — rooted GSI with Magisk recovery management
#   all targets         — use --patch-all flag
#
# dm-verity / ARP interaction:
#   Magisk patches the kernel ramdisk to add its own init overlay which handles
#   dm-verity disabling and forceencrypt bypassing at Android init time.
#   For maximum reliability, ALSO flash vbmeta with --disable-verity before
#   using Magisk:
#     fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
#   setup-android.sh does this automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Magisk APK paths for each architecture
MAGISKBOOT_X86_64="lib/x86_64/libmagiskboot.so"
MAGISKBOOT_ARM64="lib/arm64-v8a/libmagiskboot.so"
MAGISKINIT_ARM64="lib/arm64-v8a/libmagiskinit.so"
MAGISK64_ARM64="lib/arm64-v8a/libmagisk64.so"

# Device userdata path for Magisk patch environment
DEVICE_MAGISK_DIR="/data/.magisk"

# ── Argument parsing ─────────────────────────────────────────────────────────
APK=""
OUTPUT_DIR=""
PUSH_ADB=""
ADB_SERIAL=""
DRY_RUN=""
PATCH_ALL=""

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk)          APK="$2";         shift 2 ;;
        --push-adb)     PUSH_ADB=1;       shift   ;;
        --output-dir)   OUTPUT_DIR="$2";  shift 2 ;;
        --adb-serial)   ADB_SERIAL="$2";  shift 2 ;;
        --patch-all)    PATCH_ALL=1;      shift   ;;
        -n|--dry-run)   DRY_RUN=1;        shift   ;;
        -h|--help)      usage ;;
        *) echo "[!] Unknown option: $1" >&2; usage ;;
    esac
done

[[ -z "$APK" ]] && { echo "[!] --apk <Magisk.apk> is required" >&2; usage; }
[[ ! -f "$APK" ]] && { echo "[!] APK not found: $APK" >&2; exit 1; }

# Auto-detect push mode
if [[ -z "$PUSH_ADB" && -z "$OUTPUT_DIR" ]]; then
    if command -v adb >/dev/null 2>&1 && \
       adb ${ADB_SERIAL:+-s "$ADB_SERIAL"} devices 2>/dev/null \
           | grep -q "device$"; then
        PUSH_ADB=1
    else
        OUTPUT_DIR="$(pwd)/magisk-patch-env"
        echo "[~] ADB not available — saving to ${OUTPUT_DIR}"
    fi
fi

_adb() {
    if [[ -n "$ADB_SERIAL" ]]; then
        adb -s "$ADB_SERIAL" "$@"
    else
        adb "$@"
    fi
}

echo ""
echo "════════════════════════════════════════════════════════"
echo " patch-magisk.sh — Magisk patch environment builder"
echo " Google Pixel 8 Pro (husky / zuma)"
[[ -n "$DRY_RUN" ]] && echo " MODE: dry-run (no files written)"
echo "════════════════════════════════════════════════════════"
echo " APK        : $APK"
echo " Push ADB   : ${PUSH_ADB:-no}"
echo " Output dir : ${OUTPUT_DIR:-(adb push)}"
echo ""

# ── Step 1: Extract binaries from APK ───────────────────────────────────────
echo "[1/4] Extracting Magisk binaries from APK..."

WORKDIR="$(mktemp -d --tmpdir magisk-patch.XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

MAGISK_DIR="${WORKDIR}/magisk"
mkdir -p "$MAGISK_DIR"

# Detect host architecture for magiskboot
HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" == "aarch64" || "$HOST_ARCH" == "arm64" ]]; then
    MAGISKBOOT_HOST="$MAGISKBOOT_ARM64"
    echo "    Host arch: arm64 — using native magiskboot"
else
    MAGISKBOOT_HOST="$MAGISKBOOT_X86_64"
    echo "    Host arch: ${HOST_ARCH} — using x86_64 magiskboot"
fi

extract_from_apk() {
    local src="$1" dst="$2" name="$3"
    if [[ -n "$DRY_RUN" ]]; then
        echo "    [dry-run] extract ${src} → ${dst}"
        return
    fi
    if ! unzip -p "$APK" "$src" > "$dst" 2>/dev/null; then
        echo "[!] Could not extract ${name} from APK" \
             "(path: ${src})" >&2
        echo "    Make sure you have a recent Magisk release APK." >&2
        exit 1
    fi
    chmod +x "$dst"
    echo "    extracted: ${name} ($(du -sh "$dst" | cut -f1))"
}

extract_from_apk "$MAGISKBOOT_HOST"  "${WORKDIR}/magiskboot"  "magiskboot (host)"
extract_from_apk "$MAGISKINIT_ARM64" "${MAGISK_DIR}/magiskinit" "magiskinit (arm64)"
extract_from_apk "$MAGISK64_ARM64"   "${MAGISK_DIR}/magisk64"   "magisk64 (arm64)"
extract_from_apk "$MAGISKBOOT_ARM64" "${MAGISK_DIR}/magiskboot" "magiskboot (arm64)"

# ── Step 2: Build patch-initrd staging area ──────────────────────────────────
echo "[2/4] Building patch-initrd staging area..."

STAGE="${WORKDIR}/stage"
mkdir -p "${STAGE}"/{proc,sys,dev,mnt,tmp,magisk}

# The init script IS the magisk-patch boot target
install -m 755 "${ADDON_DIR}/boot-targets/magisk-patch.sh" "${STAGE}/init"

# Source _common.sh functions needed by magisk-patch.sh
install -m 644 "${ADDON_DIR}/boot-targets/_common.sh" \
               "${STAGE}/boot-targets/_common.sh" 2>/dev/null || true
mkdir -p "${STAGE}/boot-targets"
cat > "${STAGE}/boot-targets/_common_stub.sh" << 'EOF'
# _common_stub.sh — minimal stub for patch-initrd context
# Sourced by magisk-patch.sh instead of the full _common.sh.
# The patch-initrd does not use kexec, so only the two functions called by
# magisk-patch.sh's run_target() are needed:
#   _find_userdata  — mount userdata for patching
#   _fallback_linux — error path (reboots instead of kexec in this context)
# If magisk-patch.sh is updated to call additional _common.sh functions,
# add them here to prevent silent failures.
_find_userdata() {
    for dev in /dev/sda* /dev/nvme0n1p* /dev/mmcblk0p*; do
        [ -b "$dev" ] || continue
        label="$(blkid -o value -s PARTLABEL "$dev" 2>/dev/null)" || continue
        [ "$label" = "userdata" ] && echo "$dev" && return 0
    done
    return 1
}
_fallback_linux() { reboot -f; }
EOF
chmod 644 "${STAGE}/boot-targets/_common_stub.sh"

# Patch init to source the stub instead of _common.sh
sed 's|/boot-targets/_common\.sh|/boot-targets/_common_stub.sh|g' \
    "${STAGE}/init" > "${STAGE}/init.tmp" && \
    mv "${STAGE}/init.tmp" "${STAGE}/init"
chmod 755 "${STAGE}/init"

# Embed arm64 Magisk binaries
install -m 755 "${MAGISK_DIR}/magiskinit" "${STAGE}/magisk/magiskinit"
install -m 755 "${MAGISK_DIR}/magisk64"   "${STAGE}/magisk/magisk64"
install -m 755 "${MAGISK_DIR}/magiskboot" "${STAGE}/magisk/magiskboot"

echo "    staging area: $(du -sh "${STAGE}" | cut -f1)"

# ── Step 3: Pack patch-initrd.cpio.gz ────────────────────────────────────────
echo "[3/4] Packing patch-initrd.cpio.gz..."

PATCH_INITRD="${WORKDIR}/patch-initrd.cpio.gz"

if [[ -z "$DRY_RUN" ]]; then
    (
        cd "${STAGE}"
        find . | sort | \
            cpio --create --format=newc --owner=0:0 --quiet 2>/dev/null
    ) | gzip -9 > "$PATCH_INITRD"
    echo "    patch-initrd: $(du -sh "${PATCH_INITRD}" | cut -f1)"
fi

# ── Step 4: Deploy ────────────────────────────────────────────────────────────
echo "[4/4] Deploying..."

if [[ -n "$PUSH_ADB" ]]; then
    if [[ -n "$DRY_RUN" ]]; then
        echo "    [dry-run] adb shell mkdir -p ${DEVICE_MAGISK_DIR}"
        echo "    [dry-run] adb push patch-initrd.cpio.gz ${DEVICE_MAGISK_DIR}/"
        echo "    [dry-run] adb push magiskboot ${DEVICE_MAGISK_DIR}/"
    else
        _adb shell "mkdir -p ${DEVICE_MAGISK_DIR}"
        _adb push "$PATCH_INITRD"         "${DEVICE_MAGISK_DIR}/patch-initrd.cpio.gz"
        _adb push "${WORKDIR}/magiskboot"  "${DEVICE_MAGISK_DIR}/magiskboot"
        _adb shell "chmod 755 ${DEVICE_MAGISK_DIR}/magiskboot"
        echo "    pushed to device:${DEVICE_MAGISK_DIR}/"
    fi
else
    OUTDIR="${OUTPUT_DIR}"
    if [[ -z "$DRY_RUN" ]]; then
        mkdir -p "$OUTDIR"
        cp "$PATCH_INITRD"         "${OUTDIR}/patch-initrd.cpio.gz"
        cp "${WORKDIR}/magiskboot" "${OUTDIR}/magiskboot"
        echo "    saved to: ${OUTDIR}/"
        echo ""
        echo "    To deploy manually:"
        echo "      adb push ${OUTDIR}/patch-initrd.cpio.gz ${DEVICE_MAGISK_DIR}/"
        echo "      adb push ${OUTDIR}/magiskboot            ${DEVICE_MAGISK_DIR}/"
        echo "      adb shell chmod 755 ${DEVICE_MAGISK_DIR}/magiskboot"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo " Done!  Magisk patch environment is ready."
echo ""
echo " Trigger patching via U-Boot boot menu:"
echo "   Select 'Magisk: patch android-a' (or -b, GSI)"
echo ""
echo " Or via boot-selector (one-shot):"
echo "   fastboot boot -c \\"
echo "     'boot_target=magisk-patch patch_target=.android-a' \\"
echo "     boot-selector.img"
echo ""
echo " Or via flag files (persistent reboot patch):"
echo "   echo '.android-a' | adb shell 'cat > /data/.magisk_patch_target'"
echo "   ./scripts/set-target.sh set magisk-patch"
if [[ -n "$PATCH_ALL" ]]; then
    echo ""
    echo " --patch-all: run this script again for each target you want"
    echo "   to patch, or trigger each from U-Boot menu separately."
fi
echo "════════════════════════════════════════════════════════"
