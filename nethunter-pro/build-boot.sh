#!/usr/bin/env bash
# build-boot.sh — rebuild only the Android boot image for Pixel 8 Pro (husky)
#
# Rebuilds boot.img from an existing rootfs without re-running the full debos
# rootfs or image pipelines.  Use this after the initial full build when you
# only need to regenerate the boot image (e.g. after a kernel update or after
# changing boot parameters in bootloader.yaml).
#
# Usage:
#   ./build-boot.sh [OPTIONS]
#
# Options:
#   -d              Use Docker (recommended)
#   -e ENV          Desktop environment: phosh (default) | plasma-mobile
#   -V VERSION      Image version string (default: YYYYMMDD)
#   -v              Verbose output
#   -D              Debug output
#   -m MEMORY       debos memory limit (e.g. 4G)
#
# Prerequisites (bare metal):
#   sudo apt install git debos mkbootimg
#
# Prerequisites (Docker):
#   sudo apt install git docker.io
#
# The upstream directory (.upstream) must already contain a rootfs tarball
# produced by a previous full build (rootfs.yaml step).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro.git"
UPSTREAM_DIR="${SCRIPT_DIR}/.upstream"

# ── defaults ────────────────────────────────────────────────────────────────
device="husky"
family="zuma"
architecture="arm64"
environment="phosh"
version=$(date +%Y%m%d)
use_docker=""
verbose=""
debug=""
EXTRA_ARGS=""

display_help() {
  sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
  exit 0
}

while getopts ":dDvV:e:m:h" opt; do
  case "${opt}" in
    d) use_docker=1 ;;
    D) debug=1 ;;
    v) verbose=1 ;;
    V) version="${OPTARG}" ;;
    e) environment="${OPTARG}" ;;
    m) EXTRA_ARGS="${EXTRA_ARGS} --memory ${OPTARG}" ;;
    h|\?) display_help ;;
    :)
      if [ "${OPTARG}" = "e" ]; then
        environment="phosh"
      else
        echo "Option -${OPTARG} requires an argument." >&2
        display_help
      fi
      ;;
  esac
done

# ── verify upstream directory exists ─────────────────────────────────────────
if [ ! -d "${UPSTREAM_DIR}" ]; then
  echo "[!] Upstream directory not found: ${UPSTREAM_DIR}" >&2
  echo "[!] Run ./build.sh first to perform a full build before using build-boot.sh." >&2
  exit 1
fi

# ── verify rootfs tarball is present ─────────────────────────────────────────
ROOTFS_TARBALL="${UPSTREAM_DIR}/rootfs-${architecture}-${environment}-nonfree.tar.gz"
if [ ! -f "${ROOTFS_TARBALL}" ]; then
  echo "[!] Rootfs tarball not found: ${ROOTFS_TARBALL}" >&2
  echo "[!] Run ./build.sh first to produce the rootfs before rebuilding the boot image." >&2
  exit 1
fi

# ── inject/update device-family files ────────────────────────────────────────
echo "[+] Refreshing zuma device-family recipes..."
cp -r "${SCRIPT_DIR}/devices/zuma" "${UPSTREAM_DIR}/devices/"

echo "[+] Refreshing husky overlay..."
cp -r "${SCRIPT_DIR}/overlays/husky" "${UPSTREAM_DIR}/overlays/"

# ── build ─────────────────────────────────────────────────────────────────────
cd "${UPSTREAM_DIR}"

DEBOS_CMD="debos"
ARGS="${EXTRA_ARGS}"

ARGS="${ARGS} \
  -t architecture:${architecture} \
  -t family:${family} \
  -t device:${device} \
  -t environment:${environment} \
  -t image:nethunterpro-${version}-${device}-${environment} \
  -t rootfs:rootfs-${architecture}-${environment}-nonfree.tar.gz \
  -t nonfree:true \
  --scratchsize=4G"

[ "${debug:-}" ]   && ARGS="${ARGS} --debug-shell"
[ "${verbose:-}" ] && ARGS="${ARGS} --verbose"

ensure_docker_running() {
  local docker_unix_sock="unix:///var/run/docker.sock"
  local docker_sock_path="/var/run/docker.sock"
  local docker_start_retries=10

  check_docker_os() {
    local os
    os="$(${DOCKER_SUDO:-} docker info --format '{{.OSType}}' 2>/dev/null)" || return 1
    [ "${os}" = "linux" ] || [ "${os}" = "windows" ]
  }

  if check_docker_os; then
    return 0
  fi

  if grep -qi "microsoft" /proc/version 2>/dev/null; then
    if DOCKER_HOST="${docker_unix_sock}" check_docker_os 2>/dev/null; then
      export DOCKER_HOST="${docker_unix_sock}"
      return 0
    fi

    if [ -S "${docker_sock_path}" ]; then
      if DOCKER_SUDO=sudo check_docker_os 2>/dev/null; then
        export DOCKER_SUDO=sudo
        return 0
      fi
    fi

    echo "[+] WSL detected: Docker daemon not running – attempting to start it..."
    sudo service containerd start 2>&1 || true
    sudo service docker start 2>&1 || true

    for _ in $(seq 1 "${docker_start_retries}"); do
      sleep 1
      if check_docker_os; then return 0; fi
      if DOCKER_HOST="${docker_unix_sock}" check_docker_os 2>/dev/null; then
        export DOCKER_HOST="${docker_unix_sock}"
        return 0
      fi
      if DOCKER_SUDO=sudo check_docker_os 2>/dev/null; then
        export DOCKER_SUDO=sudo
        return 0
      fi
    done

    echo "[!] Docker daemon is not reachable in WSL." >&2
    exit 1
  fi

  echo "[!] Docker daemon is not running. Start it and re-run this script." >&2
  exit 1
}

DOCKER_SUDO=""

if [ "${use_docker}" ]; then
  ensure_docker_running

  DOCKER_KVM_ARG=""
  DOCKER_SERVER_OS=""
  if DOCKER_SERVER_OS="$(${DOCKER_SUDO:-} docker version --format '{{.Server.Os}}' 2>/dev/null)"; then
    :
  fi
  if [ -e /dev/kvm ] && [ "${DOCKER_SERVER_OS}" = "linux" ]; then
    DOCKER_KVM_ARG="--device /dev/kvm"
  fi

  DEBOS_CMD="${DOCKER_SUDO:-} docker run --rm --interactive --tty \
    ${DOCKER_KVM_ARG} \
    --workdir /recipes \
    --mount type=bind,source=$(pwd),destination=/recipes \
    --security-opt label=disable \
    godebos/debos"
fi

echo "[+] Rebuilding boot image only (bootloader.yaml)..."
${DEBOS_CMD} ${ARGS} devices/zuma/bootloader.yaml

BOOT_IMG="nethunterpro-${version}-${device}-${environment}-boot.img"

echo ""
echo "══════════════════════════════════════════════════════════"
echo " Boot image rebuild complete!"
echo "══════════════════════════════════════════════════════════"
echo ""
echo " Output: ${UPSTREAM_DIR}/${BOOT_IMG}"
echo ""
echo " Flash:"
echo "   fastboot flash boot ${BOOT_IMG}"
echo "   fastboot reboot"
echo "══════════════════════════════════════════════════════════"
