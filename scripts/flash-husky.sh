#!/usr/bin/env bash
# flash-husky.sh – configurable fastboot flash script for the Google Pixel 8 Pro (husky)
#
# Reads [[flash.targets]] entries from a TOML config file and runs the
# corresponding `fastboot flash` commands in order.
#
# Usage:
#   ./scripts/flash-husky.sh [OPTIONS] [IMAGE_BASENAME]
#
# Options:
#   -c, --config <file>   TOML config file (default: nethunter-pro/devices/zuma/configs/husky.toml)
#   -i, --image  <name>   Image basename used to expand ${image} in the config
#                         (default: auto-detected from the newest *.img in the current directory)
#   -n, --dry-run         Print fastboot commands without executing them
#       --no-reboot       Skip the final `fastboot reboot`
#   -h, --help            Show this help message
#
# Examples:
#   # Flash with auto-detected image name, using the default config
#   ./scripts/flash-husky.sh
#
#   # Preview commands only
#   ./scripts/flash-husky.sh --dry-run
#
#   # Use a custom config (e.g. a full factory reset layout)
#   ./scripts/flash-husky.sh --config husky-factory.toml --image nethunterpro-20260101-husky-phosh
#
# The TOML parser used here is a minimal pure-bash/awk implementation that
# handles the subset of TOML needed for [[flash.targets]] tables:
#   - array-of-tables  [[flash.targets]]
#   - string values    key = "value"
#   - boolean values   key = true | false
# No external TOML library is required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_CONFIG="${REPO_ROOT}/nethunter-pro/devices/zuma/configs/husky.toml"

# ── argument parsing ──────────────────────────────────────────────────────────
config="${DEFAULT_CONFIG}"
image_name=""
dry_run=""
no_reboot=""

usage() {
  sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,1\}//; p }; /^[^#]/q }' "$0"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)   config="$2";     shift 2 ;;
    -i|--image)    image_name="$2"; shift 2 ;;
    -n|--dry-run)  dry_run=1;       shift   ;;
    --no-reboot)   no_reboot=1;     shift   ;;
    -h|--help)     usage ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage ;;
    *)  image_name="$1"; shift ;;
  esac
done

# ── validate config ───────────────────────────────────────────────────────────
if [[ ! -f "${config}" ]]; then
  echo "[!] Config file not found: ${config}" >&2
  exit 1
fi

# ── auto-detect image basename if not provided ────────────────────────────────
if [[ -z "${image_name}" ]]; then
  # Pick the newest nethunterpro-*-boot.img in the current directory via bash
  # globbing (safe for filenames with spaces; images never contain spaces in
  # practice but we avoid ls|head for correctness).
  latest_boot=""
  latest_mtime=0
  for f in nethunterpro-*-boot.img; do
    [[ -f "${f}" ]] || continue
    mtime="$(stat -c '%Y' "${f}" 2>/dev/null || stat -f '%m' "${f}" 2>/dev/null || echo 0)"
    if (( mtime > latest_mtime )); then
      latest_mtime="${mtime}"
      latest_boot="${f}"
    fi
  done
  if [[ -n "${latest_boot}" ]]; then
    image_name="${latest_boot%-boot.img}"
    echo "[+] Auto-detected image basename: ${image_name}"
  else
    echo "[!] Could not auto-detect image basename. Use --image <name> or run from the build output directory." >&2
    exit 1
  fi
fi

# ── minimal TOML parser for [[flash.targets]] ─────────────────────────────────
# Emits lines of the form:  partition=<val> image=<val> optional=<val> slot=<val>
# One line per [[flash.targets]] block.
parse_flash_targets() {
  local toml_file="$1"
  awk '
  BEGIN { in_target=0; partition=""; image=""; optional="false"; slot=""; fastboot_flags="" }

  # Detect start of a [[flash.targets]] block
  /^\[\[flash\.targets\]\]/ {
    # Flush previous block if any
    if (in_target) {
      print "partition=" partition " image=" image " optional=" optional " slot=" slot " fastboot_flags=" fastboot_flags
    }
    in_target=1
    partition=""; image=""; optional="false"; slot=""; fastboot_flags=""
    next
  }

  # Detect start of any other section – flush and leave target mode
  /^\[/ && !/^\[\[flash\.targets\]\]/ {
    if (in_target) {
      print "partition=" partition " image=" image " optional=" optional " slot=" slot " fastboot_flags=" fastboot_flags
      in_target=0
      partition=""; image=""; optional="false"; slot=""; fastboot_flags=""
    }
    next
  }

  # Skip comment lines and blank lines
  /^[[:space:]]*(#|$)/ { next }

  in_target {
    # Strip inline comments
    sub(/[[:space:]]*#.*$/, "")

    # partition = "value"
    if (/^[[:space:]]*partition[[:space:]]*=/) {
      match($0, /=[[:space:]]*"([^"]*)"/, arr)
      partition = arr[1]
    }
    # image = "value"
    else if (/^[[:space:]]*image[[:space:]]*=/) {
      match($0, /=[[:space:]]*"([^"]*)"/, arr)
      image = arr[1]
    }
    # optional = true|false
    else if (/^[[:space:]]*optional[[:space:]]*=/) {
      match($0, /=[[:space:]]*(true|false)/, arr)
      optional = arr[1]
    }
    # slot = "value"
    else if (/^[[:space:]]*slot[[:space:]]*=/) {
      match($0, /=[[:space:]]*"([^"]*)"/, arr)
      slot = arr[1]
    }
    # fastboot_flags = "value"  (comma-separated; spaces expand at call site)
    else if (/^[[:space:]]*fastboot_flags[[:space:]]*=/) {
      match($0, /=[[:space:]]*"([^"]*)"/, arr)
      # Store with commas; caller expands commas to spaces
      fastboot_flags = arr[1]
    }
  }

  END {
    if (in_target && partition != "") {
      print "partition=" partition " image=" image " optional=" optional " slot=" slot " fastboot_flags=" fastboot_flags
    }
  }
  ' "${toml_file}"
}

# ── expand ${image} placeholder ───────────────────────────────────────────────
expand_image() {
  # Replace literal ${image} with the resolved image_name
  echo "${1/\$\{image\}/${image_name}}"
}

# ── build and (optionally) run a fastboot command ─────────────────────────────
run_fastboot() {
  local cmd=("$@")
  if [[ -n "${dry_run}" ]]; then
    echo "  [dry-run]  ${cmd[*]}"
  else
    echo "[+] Running: ${cmd[*]}"
    "${cmd[@]}"
  fi
}

# ── bootloader / radio partition guard ───────────────────────────────────────
# The Google ABL (Android Bootloader, e.g. bootloader-husky-ripcurrent-*) injects
# the version-specific identifier androidboot.bootloader=<version> and enforces
# Android Verified Boot (AVB / boot security levels).  Native Linux does not use
# Android's boot-level security chain, so flashing a proprietary, version-locked
# ABL provides no benefit and needlessly ties the device to a specific Google
# firmware build.  The radio firmware is similarly managed outside OS flashing.
#
# If a "bootloader" or "radio" partition entry appears in the flash config this
# script aborts with an explanation rather than silently flashing it.
check_no_abl_partitions() {
  local toml_file="$1"
  local forbidden
  forbidden="$(awk '
    /^\[\[flash\.targets\]\]/ { in_target=1; next }
    /^\[/ && !/^\[\[flash\.targets\]\]/ { in_target=0; next }
    /^[[:space:]]*(#|$)/ { next }
    in_target && /^[[:space:]]*partition[[:space:]]*=/ {
      match($0, /=[[:space:]]*"([^"]*)"/, arr)
      p = arr[1]
      if (p == "bootloader" || p == "radio") print p
    }
  ' "${toml_file}")"
  if [[ -n "${forbidden}" ]]; then
    echo "" >&2
    echo "[!] ABORT: flash config contains a forbidden partition entry:" >&2
    while IFS= read -r p; do
      echo "      partition = \"${p}\"" >&2
    done <<< "${forbidden}"
    echo "" >&2
    echo "    The Google ABL (bootloader partition) embeds a version-specific" >&2
    echo "    identifier (androidboot.bootloader=ripcurrent-<ver>) and enforces" >&2
    echo "    Android Verified Boot.  Native Linux does not use this security" >&2
    echo "    chain.  Remove the '${forbidden}' entry from the flash config." >&2
    echo "" >&2
    exit 1
  fi
}

check_no_abl_partitions "${config}"

# ── main flash loop ───────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo " flash-husky.sh – Pixel 8 Pro (husky) flash tool"
[[ -n "${dry_run}" ]] && echo " MODE: dry-run (no commands will be executed)"
echo "══════════════════════════════════════════════════════════"
echo " Config : ${config}"
echo " Image  : ${image_name}"
echo ""

target_count=0
skipped_count=0

while IFS= read -r target_line; do
  # Parse the fields emitted by awk.
  # The awk parser emits key=value tokens with no spaces inside values (partition
  # names, image filenames, the literals "true"/"false", and slot letters are
  # all space-free by construction).  "optional" is always the string "true" or
  # "false" — compare it as a string, not a boolean.
  unset fields
  declare -A fields=()
  for token in ${target_line}; do
    key="${token%%=*}"
    val="${token#*=}"
    fields["${key}"]="${val}"
  done

  partition="${fields[partition]:-}"
  raw_image="${fields[image]:-}"
  optional="${fields[optional]:-false}"
  slot="${fields[slot]:-}"
  raw_fastboot_flags="${fields[fastboot_flags]:-}"
  # Expand comma-separated flags back to space-separated arguments
  fastboot_flags="${raw_fastboot_flags//,/ }"

  if [[ -z "${partition}" || -z "${raw_image}" ]]; then
    echo "[!] Skipping malformed target entry (missing partition or image)" >&2
    continue
  fi

  image_file="$(expand_image "${raw_image}")"

  # Optionality check ("optional" is the string "true" returned by the awk parser)
  if [[ ! -f "${image_file}" ]]; then
    if [[ "${optional}" == "true" ]]; then
      echo "[~] Skipping optional target '${partition}': file not found: ${image_file}"
      (( skipped_count++ )) || true
      continue
    else
      echo "[!] Required image not found for partition '${partition}': ${image_file}" >&2
      exit 1
    fi
  fi

  # Build fastboot command
  # fastboot_flags (e.g. --disable-verity --disable-verification) go BEFORE
  # the flash subcommand so fastboot sends them as global protocol flags.
  fastboot_args=("fastboot")
  if [[ -n "${fastboot_flags}" ]]; then
    # shellcheck disable=SC2206
    read -ra extra_flags <<< "${fastboot_flags}"
    fastboot_args+=("${extra_flags[@]}")
  fi
  if [[ -n "${slot}" ]]; then
    fastboot_args+=("--slot" "${slot}")
  fi
  fastboot_args+=("flash" "${partition}" "${image_file}")

  run_fastboot "${fastboot_args[@]}"
  (( target_count++ )) || true

done < <(parse_flash_targets "${config}")

echo ""
echo "[+] Flashed ${target_count} partition(s), skipped ${skipped_count} optional target(s)."

# ── reboot ────────────────────────────────────────────────────────────────────
if [[ -z "${no_reboot}" ]]; then
  run_fastboot fastboot reboot
else
  echo "[~] Skipping reboot (--no-reboot)."
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo " Done."
echo "══════════════════════════════════════════════════════════"
