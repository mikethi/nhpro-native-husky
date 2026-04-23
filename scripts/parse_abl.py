#!/usr/bin/env python3
"""parse_abl.py – ABL (Android Bootloader) binary analyser for Pixel 8 Pro (husky/zuma).

abl.bin is Google's Android Bootloader for the Pixel 8 / 8 Pro (Tensor G3 /
"zuma" / "ripcurrent").  It is the closest equivalent to U-Boot in the Pixel
boot chain:

  Samsung BL1 (bl1.bin)   ≈  U-Boot SPL          – runs from on-chip SRAM
  Google PBL  (pbl.bin)   ≈  U-Boot SPL stage 2  – initialises DRAM
  Google BL2  (bl2.bin)   ≈  U-Boot proper        – SoC/power bring-up
  Google ABL  (abl.bin)   ≈  U-Boot + distro-boot – fastboot, AVB, A/B, kernel launch
  ARM TF BL31 (bl31.bin)  ≈  ARM Trusted Firmware – EL3 runtime (SMC handler)

Reference image:
    https://raw.githubusercontent.com/mikethi/zuma-husky-homebootloader/main/abl.bin

Obtain abl.bin by extracting it from the FBPK v2 bootloader container:
    python3 scripts/extract_fbpk.py bootloader-husky-ripcurrent-*.img --verbose
    # Produces: bootloader-husky-ripcurrent-*-extracted/abl.bin

Usage:
    python3 scripts/parse_abl.py [--abl PATH]   # default: ./abl.bin
    python3 scripts/parse_abl.py --abl bootloader-husky-ripcurrent-16.4-14540574-extracted/abl.bin
    python3 scripts/parse_abl.py --no-offsets    # omit hex offsets from output

Output sections:
    1. Boot modes & reboot reasons
    2. Fastboot protocol  (FAIL/INFO/OKAY prefixes + OEM commands)
    3. A/B slot handling
    4. Verified Boot (AVB) integration
    5. Kernel cmdline  (every androidboot.* param injected at boot)
    6. Hardware / device identity
    7. Embedded source-file paths  (reveals LK code layout)
    8. Load addresses / memory regions
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# ── tunables ──────────────────────────────────────────────────────────────────
DEFAULT_ABL = Path("abl.bin")
MIN_STR_LEN = 8

# The dense ASCII string section starts around this offset in the binary.
# The auto-detection logic below finds the right zone for any build.
_KNOWN_STRINGS_START = 0x10E000
_KNOWN_STRINGS_END   = 0x145000


# ── string extraction ─────────────────────────────────────────────────────────

def extract_strings(data: bytes, start: int, end: int, min_len: int = MIN_STR_LEN):
    """Yield (offset, text) for every printable-ASCII run >= min_len in [start, end)."""
    window = data[start:end]
    pattern = re.compile(rb"[\x20-\x7e]{" + str(min_len).encode() + rb",}")
    for m in pattern.finditer(window):
        yield start + m.start(), m.group().decode("ascii", errors="replace")


def _find_string_zone(
    data: bytes,
    chunk: int = 0x10000,
    threshold: float = 0.30,
) -> tuple[int, int]:
    """Return (start, end) of the largest contiguous high-density ASCII region.

    Avoids false positives from individual bytes in the ARM64 code section that
    happen to fall in the printable range but do not form long runs.
    """
    best_start = best_end = 0
    cur_start = None
    pat = re.compile(rb"[\x20-\x7e]{8,}")
    for off in range(0, len(data), chunk):
        block = data[off : off + chunk]
        string_bytes = sum(len(m.group()) for m in pat.finditer(block))
        if string_bytes / len(block) >= threshold:
            if cur_start is None:
                cur_start = off
            if off + chunk - cur_start > best_end - best_start:
                best_start, best_end = cur_start, off + chunk
        else:
            cur_start = None
    if best_end == 0:
        return _KNOWN_STRINGS_START, _KNOWN_STRINGS_END
    return best_start, min(best_end, len(data))


# ── output helpers ────────────────────────────────────────────────────────────

def _section(title: str, items: list[tuple[int, str]], *, show_offsets: bool) -> None:
    print(f"\n{'─' * 78}")
    print(f"  {title}")
    print(f"{'─' * 78}")
    if not items:
        print("  (none found)")
        return
    for off, s in items:
        if show_offsets:
            print(f"  {off:#010x}  {s}")
        else:
            print(f"  {s}")


def _matches(text: str, keywords: list[str]) -> bool:
    low = text.lower()
    return any(kw.lower() in low for kw in keywords)


# ── analysis sections ─────────────────────────────────────────────────────────

def _boot_modes(strings: list[tuple[int, str]], show: bool) -> None:
    kw = [
        "reboot,", "bootmode", "boot mode", "Fastboot Mode", "Recovery Mode",
        "FastBoot Mode", "Fastboot mode", "FastBoot mode",
        "boot-cmd", "avf_boot_mode", "force_normal_boot",
    ]
    _section("1. BOOT MODES & REBOOT REASONS",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


def _fastboot(strings: list[tuple[int, str]], show: bool) -> None:
    kw = [
        "FAIL", "INFO", "OKAY", "DATA",
        "fastboot", "oem ", "boot-fastboot",
        "slot-fastboot", "force-fastboot",
        "version-bootloader", "version-baseband",
    ]
    _section("2. FASTBOOT PROTOCOL (FAIL/INFO/OEM/…)",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


def _ab_slots(strings: list[tuple[int, str]], show: bool) -> None:
    kw = [
        "slot_a", "slot_b", "active slot", "inactive slot",
        "boot_a", "boot_b", "slot suffix", "androidboot.slot",
        "slot-unbootable", "slot-fastboot-ok",
        "could not get slot", "switch slot",
        "decrement", "boot retry", "fastboot_ab",
    ]
    _section("3. A/B SLOT HANDLING",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


def _avb(strings: list[tuple[int, str]], show: bool) -> None:
    kw = [
        "avb_", "AVB_", "vbmeta", "verified boot", "verifiedbootstate",
        "veritymode", "dm-verity", "avb_slot_verify", "libavb",
        "avb_menu_delay", "AVBf", "vbmeta_vendor", "vbmeta_system",
    ]
    _section("4. VERIFIED BOOT / AVB",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


def _cmdline(strings: list[tuple[int, str]], show: bool) -> None:
    kw = ["androidboot.", "bootargs", "kcmdline", "cmdline(full)", "Starting Linux"]
    _section("5. KERNEL CMDLINE / androidboot.* PARAMS",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


def _hw_identity(strings: list[tuple[int, str]], show: bool) -> None:
    kw = [
        "Pixel", "pixel", "husky", "zuma", "ripcurrent", "Ripcurrent",
        "Tensor", "gs401", "gs301", "gs201",
        "Serial number", "serial number", "Error getting serial",
        "ro.product", "device_info", "device_state", "model:",
        "LK build", "version-bootloader",
    ]
    _section("6. HARDWARE / DEVICE IDENTITY",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


def _source_paths(strings: list[tuple[int, str]], show: bool) -> None:
    items = [
        (o, s) for o, s in strings
        if (s.endswith(".c") or s.endswith(".h")
            or any(k in s for k in ["/lib/", "lk/arch", "lk/dev", "lk/top"]))
    ]
    _section("7. EMBEDDED SOURCE-FILE PATHS  (reveals LK code layout)",
             items, show_offsets=show)


def _memory(strings: list[tuple[int, str]], show: bool) -> None:
    kw = [
        "text_offset", "load addr", "base addr", "entry point",
        "kernel heap", "secure dram", "bl31_dram", "sec_dram",
        "heap_grow", "mem_base", "kernel allocation",
        "physical address", "PT base address",
    ]
    _section("8. LOAD ADDRESSES / MEMORY REGIONS",
             [(o, s) for o, s in strings if _matches(s, kw)], show_offsets=show)


# ── main ──────────────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Analyse abl.bin (Android Bootloader) internals for Pixel 8 Pro (husky/zuma).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--abl",
        type=Path,
        default=DEFAULT_ABL,
        metavar="PATH",
        help=f"Path to abl.bin (default: {DEFAULT_ABL})",
    )
    parser.add_argument(
        "--no-offsets",
        action="store_true",
        help="Omit hex offsets from output",
    )
    args = parser.parse_args(argv)

    abl_path: Path = args.abl
    if not abl_path.exists():
        print(
            f"[!] {abl_path} not found.\n"
            f"    Extract it first with:\n"
            f"      python3 scripts/extract_fbpk.py <bootloader.img> --verbose",
            file=sys.stderr,
        )
        return 1

    data = abl_path.read_bytes()
    size = len(data)
    print(f"[+] Loaded  {abl_path}  ({size:#x}  /  {size:,} bytes)")

    s_start, s_end = _find_string_zone(data)
    if (s_start, s_end) != (_KNOWN_STRINGS_START, _KNOWN_STRINGS_END):
        print(f"[!] Auto-detected string zone: {s_start:#x} – {s_end:#x}")
    print(f"[+] Scanning string zone  {s_start:#x} – {s_end:#x}")

    strings = list(extract_strings(data, s_start, s_end))
    print(f"[+] Found {len(strings)} strings (>= {MIN_STR_LEN} chars)")

    show = not args.no_offsets
    _boot_modes(strings, show)
    _fastboot(strings, show)
    _ab_slots(strings, show)
    _avb(strings, show)
    _cmdline(strings, show)
    _hw_identity(strings, show)
    _source_paths(strings, show)
    _memory(strings, show)

    print(f"\n{'─' * 78}")
    print("  DONE")
    print(f"{'─' * 78}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
