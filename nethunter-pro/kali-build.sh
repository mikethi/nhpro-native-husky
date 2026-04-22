#!/usr/bin/env bash
# kali-build.sh — NetHunter Pro build runner for the Pixel 8 Pro (husky)
#
# Run this script inside Kali Linux (WSL or bare-metal) after running
# setup-wsl-kali.ps1 on the Windows host, or after manually installing Kali.
#
# What it does:
#   1. Validates the environment (OS, user, disk space, required tools).
#   2. Installs any missing prerequisites via apt.
#   3. Ensures the Docker daemon is running.
#   4. Locates the nethunter-pro/build.sh inside this repository.
#   5. Runs the full Docker-based debos build.
#   6. Prints flash instructions for fastboot.
#
# Usage:
#   cd ~/nhpro-native-husky/nethunter-pro   # or wherever the repo was cloned
#   ./kali-build.sh [OPTIONS]
#
# Options passed directly to build.sh:
#   -e ENV      Desktop environment: phosh (default) | plasma-mobile
#   -c          Enable encrypted rootfs
#   -R PASS     Encryption password
#   -H HOST     Hostname (default: kali)
#   -u USER     Username (default: kali)
#   -p PASS     User password (default: 1234)
#   -s          Enable SSH
#   -Z          Enable ZRAM
#   -z          Compress output image
#   -V VER      Version string (default: YYYYMMDD)
#   -M MIRROR   APT mirror
#   -v          Verbose
#   -D          Debug
#
# Prerequisites installed automatically if missing:
#   git, docker.io, kali-archive-keyring, fastboot, adb, xz-utils,
#   android-sdk-libsparse-utils

set -euo pipefail

# ─── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'

step()  { echo -e "\n${CYAN}[+] $*${NC}"; }
ok()    { echo -e "    ${GREEN}OK${NC}  $*"; }
warn()  { echo -e "    ${YELLOW}WARN${NC}  $*"; }
fail()  { echo -e "\n${RED}[!] FATAL: $*${NC}" >&2; exit 1; }

# ─── 1. OS / distribution check ───────────────────────────────────────────────
step "Checking operating system"

if [[ "$(uname -s)" != "Linux" ]]; then
    fail "This script must run on Linux (Kali). Detected: $(uname -s)"
fi

# Read /etc/os-release safely
. /etc/os-release 2>/dev/null || true

DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"
DISTRO_VERSION="${VERSION_ID:-unknown}"

echo "    Distro: ${PRETTY_NAME:-${DISTRO_ID}}"

# Accept kali, debian, or ubuntu (debos dependencies are Debian-based)
if [[ "${DISTRO_ID}" != "kali" && "${DISTRO_ID}" != "debian" && "${DISTRO_ID}" != "ubuntu" && "${DISTRO_LIKE}" != *"debian"* && "${DISTRO_LIKE}" != *"ubuntu"* ]]; then
    warn "Distro '${DISTRO_ID}' is not Kali or Debian-based."
    warn "Package installation steps may fail. Proceeding anyway."
else
    ok "Distro ${DISTRO_ID} is compatible"
fi

# ─── 2. User / sudo check ─────────────────────────────────────────────────────
step "Checking user privileges"

CURRENT_USER="$(id -un)"
echo "    Running as: ${CURRENT_USER}"

if [[ "${CURRENT_USER}" == "root" ]]; then
    warn "Running as root. Docker commands will use root directly."
    SUDO=""
else
    if ! sudo -n true 2>/dev/null; then
        # Not passwordless sudo — prompt once to cache credentials.
        echo "    Sudo access required. You may be prompted for your password."
        sudo -v || fail "sudo access is required to install packages and manage services."
    fi
    SUDO="sudo"
    ok "sudo access confirmed"
fi

# ─── 3. Architecture check ────────────────────────────────────────────────────
step "Checking CPU architecture"
ARCH="$(uname -m)"
echo "    Architecture: ${ARCH}"
if [[ "${ARCH}" != "x86_64" ]]; then
    fail "The Docker debos image (godebos/debos) requires an x86_64 host. Detected: ${ARCH}"
fi
ok "x86_64 confirmed"

# ─── 4. Disk space ────────────────────────────────────────────────────────────
step "Checking available disk space"

# Build requires roughly 20 GB in the current working directory.
MIN_FREE_KB=$((20 * 1024 * 1024))  # 20 GB in KB

FREE_KB="$(df --output=avail -k "$(pwd)" | tail -1 | tr -d ' ')"
FREE_GB=$(( FREE_KB / 1024 / 1024 ))

echo "    Free space: ${FREE_GB} GB (need at least 20 GB)"
if (( FREE_KB < MIN_FREE_KB )); then
    fail "Insufficient disk space: ${FREE_GB} GB free, need at least 20 GB."
fi
ok "${FREE_GB} GB available"

# ─── 5. Network connectivity ──────────────────────────────────────────────────
step "Checking network connectivity"
if ! curl -fsS --max-time 10 https://http.kali.org/ > /dev/null 2>&1; then
    if ! curl -fsS --max-time 10 https://www.google.com/ > /dev/null 2>&1; then
        fail "No internet connectivity detected. Check your network and try again."
    fi
    warn "Kali mirror not reachable; other internet hosts are up. Proceeding."
else
    ok "Kali APT mirror reachable"
fi

# ─── 6. Locate repository and build script ────────────────────────────────────
step "Locating repository"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH=""

# Accept being run from:
#   a) nethunter-pro/   (the script lives alongside build.sh)
#   b) the repo root    (nethunter-pro/build.sh is a subdirectory)
if [[ -f "${SCRIPT_DIR}/build.sh" ]]; then
    # Running from nethunter-pro/
    BUILD_SH="${SCRIPT_DIR}/build.sh"
elif [[ -f "${SCRIPT_DIR}/nethunter-pro/build.sh" ]]; then
    # Running from repo root
    BUILD_SH="${SCRIPT_DIR}/nethunter-pro/build.sh"
else
    # Search up to 2 parent levels
    for candidate in \
        "$(dirname "${SCRIPT_DIR}")/nethunter-pro/build.sh" \
        "$(dirname "$(dirname "${SCRIPT_DIR}")")/nethunter-pro/build.sh"
    do
        if [[ -f "${candidate}" ]]; then
            BUILD_SH="${candidate}"
            break
        fi
    done
fi

if [[ -z "${BUILD_SH}" ]]; then
    fail "Cannot find nethunter-pro/build.sh. Run this script from inside the cloned repository."
fi

BUILD_DIR="$(dirname "${BUILD_SH}")"
echo "    Repository root: $(dirname "${BUILD_DIR}")"
echo "    build.sh:        ${BUILD_SH}"
ok "Repository located"

# Verify the zuma device files that build.sh depends on are present.
step "Verifying repository contents"

REQUIRED_FILES=(
    "${BUILD_DIR}/devices/zuma/bootloader.yaml"
    "${BUILD_DIR}/devices/zuma/packages-base.yaml"
    "${BUILD_DIR}/overlays/husky"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -e "${f}" ]]; then
        fail "Expected file/directory missing: ${f}"
    fi
    ok "Found: $(basename "${f}")"
done

# ─── 7. Install / verify required packages ────────────────────────────────────
step "Checking required packages"

REQUIRED_PKGS=(git docker.io kali-archive-keyring fastboot adb xz-utils android-sdk-libsparse-utils)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"; then
        MISSING_PKGS+=("${pkg}")
        warn "Missing: ${pkg}"
    else
        ok "Installed: ${pkg}"
    fi
done

if (( ${#MISSING_PKGS[@]} > 0 )); then
    step "Installing missing packages: ${MISSING_PKGS[*]}"
    $SUDO apt-get update -y
    $SUDO apt-get install -y "${MISSING_PKGS[@]}"
    ok "All packages installed"
fi

# ─── 8. Docker checks ─────────────────────────────────────────────────────────
step "Checking Docker"

# Version check — debos requires Docker Engine 20+ for --mount syntax.
DOCKER_VERSION="$(docker --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || true)"
DOCKER_MAJOR="$(echo "${DOCKER_VERSION}" | cut -d. -f1)"
echo "    Docker version: ${DOCKER_VERSION:-unknown}"
if [[ -z "${DOCKER_MAJOR}" || "${DOCKER_MAJOR}" -lt 20 ]]; then
    warn "Docker version ${DOCKER_VERSION:-unknown} may be too old; 20+ recommended."
fi

# Docker group membership
if [[ "${CURRENT_USER}" != "root" ]] && ! groups | grep -qw docker; then
    warn "User '${CURRENT_USER}' is not in the docker group."
    warn "Adding to docker group. You will need to log out and back in"
    warn "(or run 'newgrp docker') for it to take effect in interactive sessions."
    $SUDO usermod -aG docker "${CURRENT_USER}"
    # Re-exec this script under the docker group so Docker is reachable without sudo.
    QUOTED_ARGS="$(printf '%q ' "$@")"
    exec sg docker -c "bash ${BASH_SOURCE[0]} ${QUOTED_ARGS}" || true
    # If exec returns for any reason, continue — Docker commands may require sudo.
fi

# Ensure daemon is running
DOCKER_RUNNING=false
if docker info > /dev/null 2>&1; then
    DOCKER_RUNNING=true
    ok "Docker daemon is running"
else
    step "Docker daemon not reachable — attempting to start it"

    $SUDO service containerd start 2>&1 || true
    $SUDO service docker start 2>&1     || true

    for i in $(seq 1 15); do
        sleep 1
        if docker info > /dev/null 2>&1; then
            DOCKER_RUNNING=true
            ok "Docker daemon started (after ${i}s)"
            break
        fi
    done

    if [[ "${DOCKER_RUNNING}" != "true" ]]; then
        fail "Docker daemon is not running and could not be started automatically."$'\n'"    Try: sudo service docker start"
    fi
fi

# ─── 9. Pull / verify the debos Docker image ──────────────────────────────────
step "Ensuring godebos/debos image is available"

if docker image inspect godebos/debos > /dev/null 2>&1; then
    ok "godebos/debos image already present"
else
    warn "Pulling godebos/debos (this is a large image — several hundred MB)..."
    docker pull godebos/debos
    ok "godebos/debos pulled"
fi

# ─── 10. KVM availability (optional but speeds up debos) ──────────────────────
step "Checking KVM availability"
if [[ -e /dev/kvm ]]; then
    ok "/dev/kvm is present — debos will use hardware acceleration"
else
    warn "/dev/kvm not found. The build will still work but may be slower."
    warn "In WSL2: enable nested virtualisation via the Windows hypervisor settings"
    warn "if faster builds are needed."
fi

# ─── 11. Ensure build.sh is executable ────────────────────────────────────────
step "Checking build.sh permissions"
if [[ ! -x "${BUILD_SH}" ]]; then
    warn "build.sh is not executable — fixing..."
    chmod +x "${BUILD_SH}"
fi
ok "build.sh is executable"

# ─── 12. Pass remaining arguments and run the build ───────────────────────────
step "Starting build (using Docker)"
echo "    Working directory: ${BUILD_DIR}"
echo "    build.sh:          ${BUILD_SH}"
echo "    Extra args:        ${*:-<none>}"
echo ""
echo "    The build pulls the upstream kali-nethunter-pro recipe set,"
echo "    injects the Pixel 8 Pro (husky/zuma) device files, then runs"
echo "    debos inside Docker to produce boot.img + userdata.img."
echo "    This typically takes 20-60 minutes."
echo ""

cd "${BUILD_DIR}"
bash "${BUILD_SH}" -d "$@"
BUILD_EXIT=$?

if [[ "${BUILD_EXIT}" -ne 0 ]]; then
    fail "build.sh exited with code ${BUILD_EXIT}."
fi

# ─── 13. Verify output images ─────────────────────────────────────────────────
step "Verifying build output"

UPSTREAM_DIR="${BUILD_DIR}/.upstream"
if [[ ! -d "${UPSTREAM_DIR}" ]]; then
    fail "Expected upstream directory not found: ${UPSTREAM_DIR}"
fi

BOOT_IMG="$(ls -1t "${UPSTREAM_DIR}"/nethunterpro-*-husky-*-boot.img 2>/dev/null | head -1 || true)"
ROOT_IMG="$(ls -1t "${UPSTREAM_DIR}"/nethunterpro-*-husky-*.img 2>/dev/null | grep -v boot | head -1 || true)"

if [[ -z "${BOOT_IMG}" ]]; then
    fail "No boot image found in ${UPSTREAM_DIR}. Check build logs above."
fi
if [[ -z "${ROOT_IMG}" ]]; then
    fail "No rootfs image found in ${UPSTREAM_DIR}. Check build logs above."
fi

BOOT_SIZE="$(du -h "${BOOT_IMG}" | cut -f1)"
ROOT_SIZE="$(du -h "${ROOT_IMG}" | cut -f1)"

ok "Boot image:   $(basename "${BOOT_IMG}") (${BOOT_SIZE})"
ok "Rootfs image: $(basename "${ROOT_IMG}") (${ROOT_SIZE})"

# ─── 14. Flash instructions ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} Build complete! Flash instructions for Pixel 8 Pro (husky)${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo " Prerequisites:"
echo "   • Bootloader must be unlocked (Settings → Developer options →"
echo "     OEM unlocking ON, then: fastboot flashing unlock)"
echo "   • If using WSL, attach the phone via usbipd-win first:"
echo "     (in an elevated PowerShell on Windows)"
echo "       usbipd list"
echo "       usbipd bind --busid <BUSID>"
echo "       usbipd attach --wsl --busid <BUSID>"
echo ""
echo " Reboot into bootloader:"
echo "   adb reboot bootloader"
echo "   # or hold: Power + Volume Down for 10 seconds"
echo ""
echo " Flash commands (run inside Kali):"
echo ""
echo "   fastboot flash boot     $(basename "${BOOT_IMG}")"
echo "   fastboot flash userdata $(basename "${ROOT_IMG}")"
echo "   fastboot reboot"
echo ""
echo " Full paths:"
echo "   ${BOOT_IMG}"
echo "   ${ROOT_IMG}"
echo ""
echo " Default credentials: kali / 1234"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
