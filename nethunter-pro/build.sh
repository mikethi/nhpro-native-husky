#!/usr/bin/env bash
# NetHunter Pro build script for Google Pixel 8 Pro (husky / zuma SoC)
#
# Wraps the upstream kali-nethunter-pro debos build system and injects
# the zuma device-family recipes needed for the Pixel 8 Pro.
#
# Usage:
#   ./build.sh [OPTIONS]
#
# Options:
#   -d              Use Docker (recommended)
#   -e ENV          Desktop environment: phosh (default) | plasma-mobile
#   -c              Enable encrypted root filesystem
#   -R PASSWORD     Encryption password
#   -H HOSTNAME     Hostname (default: kali)
#   -u USERNAME     Username (default: kali)
#   -p PASSWORD     User password (default: 1234)
#   -s              Enable SSH
#   -Z              Enable ZRAM
#   -z              Compress output image
#   -V VERSION      Image version string (default: YYYYMMDD)
#   -M MIRROR       Kali APT mirror (default: http://http.kali.org/kali)
#   -v              Verbose output
#   -D              Debug output
#
# Prerequisites (bare metal):
#   sudo apt install git debos xz-utils android-sdk-libsparse-utils
#
# Prerequisites (Docker):
#   sudo apt install git docker.io kali-archive-keyring
#
# The resulting image is flashed to the Pixel 8 Pro via:
#   fastboot flash boot   nethunterpro-*-husky-phosh-boot.img
#   fastboot flash system nethunterpro-*-husky-phosh.img   # or userdata
#   fastboot reboot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro.git"
UPSTREAM_DIR="${SCRIPT_DIR}/.upstream"

# ── defaults ────────────────────────────────────────────────────────────────
device="husky"
family="zuma"
architecture="arm64"
environment="phosh"
hostname="kali"
username="kali"
password="1234"
version=$(date +%Y%m%d)
mirror="http://http.kali.org/kali"
use_docker=""
verbose=""
debug=""
do_compress=""
crypt_root=""
crypt_password=""
ssh="true"
zram=""
EXTRA_ARGS=""

display_help() {
  sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
  exit 0
}

while getopts ":dDvcszCZrR:e:H:u:p:M:m:V:f:h:x:g:" opt; do
  case "${opt}" in
    d) use_docker=1 ;;
    D) debug=1 ;;
    v) verbose=1 ;;
    c) crypt_root=1 ;;
    s) ssh=1 ;;
    z) do_compress=1 ;;
    Z) zram=1 ;;
    R) crypt_password="${OPTARG}" ;;
    e) environment="${OPTARG}" ;;
    H) hostname="${OPTARG}" ;;
    u) username="${OPTARG}" ;;
    p) password="${OPTARG}" ;;
    M) mirror="${OPTARG}" ;;
    m) EXTRA_ARGS="${EXTRA_ARGS} --memory ${OPTARG}" ;;
    V) version="${OPTARG}" ;;
    f) EXTRA_ARGS="${EXTRA_ARGS} -e ftp_proxy:${OPTARG}" ;;
    h) EXTRA_ARGS="${EXTRA_ARGS} -e http_proxy:${OPTARG}" ;;
    x) EXTRA_ARGS="${EXTRA_ARGS} -t debian_suite:${OPTARG}" ;;
    g) EXTRA_ARGS="${EXTRA_ARGS} -t sign:${OPTARG}" ;;
    :)
      if [ "${OPTARG}" = "e" ]; then
        environment="phosh"
      else
        echo "Option -${OPTARG} requires an argument." >&2
        display_help
      fi
      ;;
    \?) display_help ;;
  esac
done

# ── clone / update upstream ──────────────────────────────────────────────────
if [ ! -d "${UPSTREAM_DIR}/.git" ]; then
  echo "[+] Cloning upstream kali-nethunter-pro..."
  git clone "${UPSTREAM_REPO}" "${UPSTREAM_DIR}"
else
  echo "[+] Updating upstream kali-nethunter-pro..."
  git -C "${UPSTREAM_DIR}" pull --ff-only || true
fi

# ── inject zuma device-family files ──────────────────────────────────────────
echo "[+] Installing zuma device-family recipes..."
cp -r "${SCRIPT_DIR}/devices/zuma" "${UPSTREAM_DIR}/devices/"

# ── inject husky overlay ──────────────────────────────────────────────────────
echo "[+] Installing husky overlay..."
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
  -t hostname:${hostname} \
  -t username:${username} \
  -t password:${password} \
  -t mirror:${mirror} \
  -t image:nethunterpro-${version}-${device}-${environment} \
  -t rootfs:rootfs-${architecture}-${environment}-nonfree.tar.gz \
  -t nonfree:true \
  -t bootonroot:true \
  -t partitiontable:gpt \
  -t filesystem:ext4 \
  -t debian_suite:kali-rolling \
  -t suite:trixie \
  -t contrib:true \
  --scratchsize=8G"

[ "${ssh}" ]          && ARGS="${ARGS} -t ssh:true"
[ "${zram}" ]         && ARGS="${ARGS} -t zram:true"
[ "${crypt_root}" ]   && ARGS="${ARGS} -t crypt_root:true"
[ "${crypt_password}" ] && ARGS="${ARGS} -t crypt_password:${crypt_password}"
[ "${debug}" ]        && ARGS="${ARGS} --debug-shell"
[ "${verbose}" ]      && ARGS="${ARGS} --verbose"

ensure_docker_running() {
  # Returns 0 only when the daemon is reachable AND reports a known OS type.
  # The Docker CLI checks ServerInfo.OSType before every `docker run`; if it is
  # empty or unrecognised the run fails with "unknown server OS:".
  local DOCKER_UNIX_SOCK="unix:///var/run/docker.sock"
  # Maximum one-second polling iterations while waiting for dockerd to start.
  local DOCKER_START_RETRIES=10

  _docker_os_ok() {
    local os
    os="$(docker info --format '{{.OSType}}' 2>/dev/null)" || return 1
    [ "${os}" = "linux" ] || [ "${os}" = "windows" ]
  }

  # Happy path – daemon up and OS type known.
  if _docker_os_ok; then
    return 0
  fi

  # Detect WSL (both WSL1 and WSL2 require manual service start).
  if grep -qi "microsoft" /proc/version 2>/dev/null; then
    # Docker Desktop may have set the default context to a Windows-side
    # socket.  Try the local Unix socket first before attempting to start a
    # native daemon – this handles the "Desktop running but wrong context"
    # case without needing sudo.
    if DOCKER_HOST="${DOCKER_UNIX_SOCK}" _docker_os_ok 2>/dev/null; then
      export DOCKER_HOST="${DOCKER_UNIX_SOCK}"
      echo "[+] Using native Docker socket (${DOCKER_UNIX_SOCK})."
      return 0
    fi

    # Daemon not reachable at all – try starting it.
    echo "[+] WSL detected: Docker daemon not running – attempting to start it..."
    # containerd must be up before dockerd; starting it is a no-op if already running.
    # Capture stderr so any startup errors are visible if the daemon never comes up.
    local containerd_err docker_err
    containerd_err="$(sudo service containerd start 2>&1)" || true
    docker_err="$(sudo service docker start 2>&1)" || true

    for _ in $(seq 1 "${DOCKER_START_RETRIES}"); do
      sleep 1
      if _docker_os_ok; then
        echo "[+] Docker daemon started successfully."
        return 0
      fi
      if DOCKER_HOST="${DOCKER_UNIX_SOCK}" _docker_os_ok 2>/dev/null; then
        export DOCKER_HOST="${DOCKER_UNIX_SOCK}"
        echo "[+] Docker daemon started (using ${DOCKER_UNIX_SOCK})."
        return 0
      fi
    done

    echo "[!] Docker daemon is not reachable in WSL." >&2
    [ -n "${containerd_err}" ] && echo "[!]   containerd: ${containerd_err}" >&2
    [ -n "${docker_err}" ]     && echo "[!]   dockerd:    ${docker_err}" >&2
    echo "[!]   Using Docker Desktop for Windows?" >&2
    echo "[!]     1. Start Docker Desktop on Windows." >&2
    echo "[!]     2. In Settings → Resources → WSL Integration, enable your Kali distro." >&2
    echo "[!]   Using native Docker (docker.io installed in WSL)?" >&2
    echo "[!]     sudo service docker start" >&2
    exit 1
  fi

  echo "[!] Docker daemon is not running. Start it and re-run this script." >&2
  exit 1
}

if [ "${use_docker}" ]; then
  ensure_docker_running

  DOCKER_KVM_ARG=""
  DOCKER_SERVER_OS=""
  if DOCKER_SERVER_OS="$(docker version --format '{{.Server.Os}}' 2>/dev/null)"; then
    if [ -z "${DOCKER_SERVER_OS}" ]; then
      echo "[!] Warning: Docker server did not report its OS; skipping /dev/kvm passthrough."
    fi
  else
    echo "[!] Warning: could not query Docker server version; skipping /dev/kvm passthrough."
  fi
  if [ -e /dev/kvm ] && [ "${DOCKER_SERVER_OS}" = "linux" ]; then
    DOCKER_KVM_ARG="--device /dev/kvm"
  fi

  DEBOS_CMD="docker run --rm --interactive --tty \
    ${DOCKER_KVM_ARG} \
    --workdir /recipes \
    --mount type=bind,source=$(pwd),destination=/recipes \
    --security-opt label=disable \
    godebos/debos"
fi

echo "[+] Building rootfs..."
${DEBOS_CMD} ${ARGS} rootfs.yaml

echo "[+] Building disk image..."
${DEBOS_CMD} ${ARGS} image.yaml

if [ "${do_compress}" ]; then
  img="nethunterpro-${version}-${device}-${environment}.img"
  echo "[+] Compressing ${img}..."
  xz --compress --keep --force "${img}"
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo " Build complete!"
echo "══════════════════════════════════════════════════════════"
echo ""
echo " Flash to Pixel 8 Pro (husky) – unlock bootloader first:"
echo ""
echo "   fastboot flash boot   nethunterpro-${version}-${device}-${environment}-boot.img"
echo "   fastboot flash userdata nethunterpro-${version}-${device}-${environment}.img"
echo "   fastboot reboot"
echo ""
echo " Default credentials:  kali / ${password}"
echo "══════════════════════════════════════════════════════════"
