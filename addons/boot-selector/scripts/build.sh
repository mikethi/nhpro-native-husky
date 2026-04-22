#!/usr/bin/env bash
# scripts/build.sh – wrap an existing husky boot.img with the boot-selector
# Google Pixel 8 Pro (husky / zuma)
#
# Takes an existing boot.img produced by the main nhpro build and produces a
# new boot.img whose initrd is a selector prepend-initrd.  The original initrd
# is embedded inside as /real-initrd.cpio.gz so the linux target can hand off
# to it transparently.
#
# Usage:
#   ./scripts/build.sh -i <boot.img> [OPTIONS]
#
# Options:
#   -i, --boot-img  <path>   Input boot.img (required)
#   -o, --output    <path>   Output path (default: <input>-selector.img)
#   -k, --kexec     <path>   Static arm64 kexec binary to embed
#                            (required for android/recovery targets)
#   -b, --busybox   <path>   Static arm64 busybox binary to embed
#                            (required unless --host-bins is set)
#       --host-bins          Use host binaries instead of requiring static arm64 ones.
#                            Only use on an arm64 build host.
#   -n, --dry-run            Show plan without writing output
#   -h, --help               Show this help
#
# Prerequisites (host):
#   unpack_bootimg   from android-tools-mkbootimg (or android-sdk-libsparse-utils)
#   mkbootimg        from android-tools-mkbootimg
#   cpio, gzip       (coreutils)
#   file             (file-roller / file package)
#
# The output boot.img uses the same kernel, cmdline, and DTB as the input but
# with the selector as its ramdisk.  All mkbootimg parameters are read from
# husky.toml (header v4, base 0x00000000, pagesize 4096).

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ADDON_DIR}/../.." && pwd)"
HUSKY_TOML="${REPO_ROOT}/nethunter-pro/devices/zuma/configs/husky.toml"

# ── husky boot image parameters (Android header v4) ─────────────────────────
# Sourced from nethunter-pro/devices/zuma/configs/husky.toml
HEADER_VERSION=4
PAGESIZE=4096
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x00000100
DTB_OFFSET=0x01f00000
DEFAULT_CMDLINE="earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma"

# ── argument parsing ─────────────────────────────────────────────────────────
BOOT_IMG=""
OUTPUT_IMG=""
KEXEC_BIN=""
BUSYBOX_BIN=""
HOST_BINS=""
DRY_RUN=""

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--boot-img)   BOOT_IMG="$2";    shift 2 ;;
        -o|--output)     OUTPUT_IMG="$2";  shift 2 ;;
        -k|--kexec)      KEXEC_BIN="$2";   shift 2 ;;
        -b|--busybox)    BUSYBOX_BIN="$2"; shift 2 ;;
        --host-bins)     HOST_BINS=1;      shift   ;;
        -n|--dry-run)    DRY_RUN=1;        shift   ;;
        -h|--help)       usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

[[ -z "${BOOT_IMG}" ]] && { echo "[!] --boot-img is required" >&2; usage; }
[[ ! -f "${BOOT_IMG}" ]] && { echo "[!] File not found: ${BOOT_IMG}" >&2; exit 1; }
[[ -z "${OUTPUT_IMG}" ]] && OUTPUT_IMG="${BOOT_IMG%.img}-selector.img"

# ── check host prerequisites ─────────────────────────────────────────────────
for tool in unpack_bootimg mkbootimg cpio gzip file; do
    command -v "${tool}" >/dev/null || {
        echo "[!] Required host tool not found: ${tool}" >&2
        case "${tool}" in
            unpack_bootimg|mkbootimg) echo "    Install: sudo apt install android-tools-mkbootimg" >&2 ;;
            cpio|gzip|file)           echo "    Install: sudo apt install ${tool}" >&2 ;;
        esac
        exit 1
    }
done

# ── resolve binaries to embed ────────────────────────────────────────────────
embed_bins() {
    # Prints one path per line for each binary that will be embedded.
    local bins=()

    if [[ -n "${HOST_BINS}" ]]; then
        # Use host binaries (only safe on aarch64 build hosts)
        if [[ "$(uname -m)" != "aarch64" ]]; then
            echo "[!] --host-bins requires an aarch64 build host (detected: $(uname -m))" >&2
            exit 1
        fi
        for b in sh mount umount blkid cpio gzip; do
            p="$(command -v "${b}" 2>/dev/null)" || {
                echo "[!] Host binary not found: ${b}" >&2; exit 1
            }
            bins+=("${p}")
        done
    else
        # Require a static busybox (provides sh, mount, umount, blkid, cpio, gzip …)
        if [[ -z "${BUSYBOX_BIN}" ]]; then
            echo "[!] --busybox <arm64 static busybox> is required (or use --host-bins on aarch64)" >&2
            echo "    Download: https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox-armv8l" >&2
            echo "    Or build: make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig busybox" >&2
            exit 1
        fi
        [[ ! -f "${BUSYBOX_BIN}" ]] && { echo "[!] busybox not found: ${BUSYBOX_BIN}" >&2; exit 1; }
        bins+=("${BUSYBOX_BIN}")
    fi

    if [[ -n "${KEXEC_BIN}" ]]; then
        [[ ! -f "${KEXEC_BIN}" ]] && { echo "[!] kexec not found: ${KEXEC_BIN}" >&2; exit 1; }
        bins+=("${KEXEC_BIN}")
    else
        echo "[~] Warning: no --kexec provided; android/recovery targets will not work" >&2
    fi

    printf '%s\n' "${bins[@]}"
}

# ── dry-run banner ────────────────────────────────────────────────────────────
if [[ -n "${DRY_RUN}" ]]; then
    echo "══════════════════════════════════════════════════════════"
    echo " boot-selector build.sh – DRY RUN (no files written)"
    echo "══════════════════════════════════════════════════════════"
    echo " Input boot.img : ${BOOT_IMG}"
    echo " Output boot.img: ${OUTPUT_IMG}"
    echo " kexec binary   : ${KEXEC_BIN:-(not provided; android/recovery disabled)}"
    echo " busybox binary : ${BUSYBOX_BIN:-(--host-bins or host path)}"
    echo "══════════════════════════════════════════════════════════"
    exit 0
fi

# ── working directory ─────────────────────────────────────────────────────────
WORKDIR="$(mktemp -d --tmpdir boot-selector-build.XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo ""
echo "══════════════════════════════════════════════════════════"
echo " boot-selector build.sh – Google Pixel 8 Pro (husky)"
echo "══════════════════════════════════════════════════════════"
echo " Input  : ${BOOT_IMG}"
echo " Output : ${OUTPUT_IMG}"
echo ""

# ── step 1: unpack input boot.img ────────────────────────────────────────────
echo "[1/5] Unpacking input boot.img..."

UNPACK_DIR="${WORKDIR}/unpack"
mkdir -p "${UNPACK_DIR}"
unpack_bootimg --boot_img "${BOOT_IMG}" --out "${UNPACK_DIR}" >/dev/null

# Locate kernel and ramdisk files produced by unpack_bootimg
KERNEL_FILE=""
RAMDISK_FILE=""

for candidate in kernel kernel.img; do
    [[ -f "${UNPACK_DIR}/${candidate}" ]] && KERNEL_FILE="${UNPACK_DIR}/${candidate}" && break
done
for candidate in ramdisk ramdisk.img ramdisk.gz; do
    [[ -f "${UNPACK_DIR}/${candidate}" ]] && RAMDISK_FILE="${UNPACK_DIR}/${candidate}" && break
done

[[ -z "${KERNEL_FILE}"  ]] && { echo "[!] kernel not found in unpacked boot.img" >&2; exit 1; }
[[ -z "${RAMDISK_FILE}" ]] && { echo "[!] ramdisk not found in unpacked boot.img" >&2; exit 1; }

echo "    kernel  : ${KERNEL_FILE}"
echo "    ramdisk : ${RAMDISK_FILE}  ($(du -sh "${RAMDISK_FILE}" | cut -f1))"

# Detect DTB appended to kernel (common on husky: Image.gz-dtb)
DTB_FILE=""
[[ -f "${UNPACK_DIR}/dtb" ]] && DTB_FILE="${UNPACK_DIR}/dtb"

# ── step 2: build selector initrd staging area ───────────────────────────────
echo "[2/5] Building selector initrd staging area..."

STAGE="${WORKDIR}/stage"
mkdir -p "${STAGE}"/{proc,sys,dev/pts,run/boot-selector/mnt,tmp,bin,sbin,boot-targets}

# init script
install -m 755 "${ADDON_DIR}/init" "${STAGE}/init"

# boot-target handlers
for f in "${ADDON_DIR}/boot-targets/"*.sh; do
    install -m 755 "${f}" "${STAGE}/boot-targets/$(basename "${f}")"
done

# embed real initrd as /real-initrd.cpio.gz
# Normalise to .gz regardless of input format
REAL_INITRD_TYPE="$(file -b "${RAMDISK_FILE}")"
REAL_INITRD="${STAGE}/real-initrd.cpio.gz"
if echo "${REAL_INITRD_TYPE}" | grep -qi "gzip"; then
    cp "${RAMDISK_FILE}" "${REAL_INITRD}"
else
    gzip -9 -c "${RAMDISK_FILE}" > "${REAL_INITRD}"
fi
echo "    embedded real initrd: $(du -sh "${REAL_INITRD}" | cut -f1)"

# embed target binaries
mapfile -t EMBED_BINS < <(embed_bins)
for bin_path in "${EMBED_BINS[@]}"; do
    bin_name="$(basename "${bin_path}")"
    case "${bin_name}" in
        busybox)
            install -m 755 "${bin_path}" "${STAGE}/bin/busybox"
            # Create symlinks for every applet busybox provides
            for applet in sh ash mount umount blkid cpio gzip cat echo mkdir \
                          mknod tr uname; do
                ln -sf /bin/busybox "${STAGE}/bin/${applet}" 2>/dev/null || true
            done
            ;;
        kexec)
            install -m 755 "${bin_path}" "${STAGE}/sbin/kexec"
            ;;
        *)
            # host binary – copy with library deps handled by --host-bins path
            install -m 755 "${bin_path}" "${STAGE}/bin/${bin_name}"
            ;;
    esac
done

# ── step 3: pack selector into a cpio.gz ─────────────────────────────────────
echo "[3/5] Packing selector initrd (cpio.gz)..."

SELECTOR_CPIO="${WORKDIR}/selector-initrd.cpio.gz"
(
    cd "${STAGE}"
    find . | sort | \
        cpio --create --format=newc --owner=0:0 --quiet 2>/dev/null
) | gzip -9 > "${SELECTOR_CPIO}"
echo "    selector initrd: $(du -sh "${SELECTOR_CPIO}" | cut -f1)"

# ── step 4: repack boot.img ───────────────────────────────────────────────────
echo "[4/5] Repacking boot.img with selector initrd..."

# Use cmdline from unpacked args if present, otherwise fall back to default
CMDLINE="${DEFAULT_CMDLINE}"
MKBOOTIMG_ARGS_FILE="${UNPACK_DIR}/mkbootimg_args"
if [[ -f "${MKBOOTIMG_ARGS_FILE}" ]]; then
    # unpack_bootimg writes args in --key value format; extract --cmdline
    extracted_cmdline="$(grep -oP '(?<=--cmdline )[^\-]+' "${MKBOOTIMG_ARGS_FILE}" | \
        head -1 | sed 's/[[:space:]]*$//' || true)"
    [[ -n "${extracted_cmdline}" ]] && CMDLINE="${extracted_cmdline}"
fi

MKBOOTIMG_EXTRA_ARGS=()
[[ -n "${DTB_FILE}" ]] && MKBOOTIMG_EXTRA_ARGS+=(--dtb "${DTB_FILE}" --dtb_offset "${DTB_OFFSET}")

# shellcheck disable=SC2068
mkbootimg \
    --header_version "${HEADER_VERSION}" \
    --kernel         "${KERNEL_FILE}" \
    --ramdisk        "${SELECTOR_CPIO}" \
    --cmdline        "${CMDLINE}" \
    --base           "${BASE}" \
    --pagesize       "${PAGESIZE}" \
    --kernel_offset  "${KERNEL_OFFSET}" \
    --ramdisk_offset "${RAMDISK_OFFSET}" \
    --tags_offset    "${TAGS_OFFSET}" \
    ${MKBOOTIMG_EXTRA_ARGS[@]+"${MKBOOTIMG_EXTRA_ARGS[@]}"} \
    --output         "${OUTPUT_IMG}"

# ── step 5: summary ──────────────────────────────────────────────────────────
echo "[5/5] Done."
echo ""
echo "══════════════════════════════════════════════════════════"
echo " Output boot.img: ${OUTPUT_IMG}"
echo " Size           : $(du -sh "${OUTPUT_IMG}" | cut -f1)"
echo "══════════════════════════════════════════════════════════"
echo ""
echo " Flash to Pixel 8 Pro:"
echo "   fastboot flash boot ${OUTPUT_IMG}"
echo "   fastboot reboot"
echo ""
echo " Set boot target before rebooting:"
echo "   ./scripts/set-target.sh linux|android|recovery"
echo ""
echo " Boot target via fastboot (one-shot, no flag file needed):"
echo "   fastboot boot -c 'boot_target=android' ${OUTPUT_IMG}"
echo "══════════════════════════════════════════════════════════"
