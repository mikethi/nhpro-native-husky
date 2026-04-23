#!/usr/bin/env python3
"""extract_fbpk.py – parse and extract a Google Pixel FBPK v2 bootloader container.

FBPK v2 is the proprietary container format used by Google Pixel (Tensor / zuma)
factory firmware ZIPs for the Android Bootloader (ABL) partition image.

Reference image (abl.bin – ABL payload extracted from the FBPK v2 container):
    https://raw.githubusercontent.com/mikethi/zuma-husky-homebootloader/main/abl.bin

Full bootloader image (FBPK v2 container):
    https://raw.githubusercontent.com/mikethi/zuma-husky-homebootloader/main/bootloader-husky-ripcurrent-16.4-14540574.img

Format specification:
    https://github.com/mikethi/zuma-husky-homebootloader/blob/main/ALGORITHM.txt

Container layout (from ALGORITHM.txt in the zuma-husky-homebootloader repo):

  CONTAINER HEADER  (0x68 bytes at offset 0x00)
  ┌──────────┬──────┬──────────────────────────────────────────────────────┐
  │ offset   │ size │ field                                                │
  ├──────────┼──────┼──────────────────────────────────────────────────────┤
  │ 0x00     │  4   │ magic        – ASCII "FBPK"                          │
  │ 0x04     │  4   │ version      – uint32 LE  (2 for this image)         │
  │ 0x08     │  4   │ entry_count  – uint32 LE                             │
  │ 0x0C     │  4   │ (reserved / file-size hint)                          │
  │ 0x10     │ 16   │ platform     – null-padded ASCII  (e.g. "zuma")      │
  │ 0x20     │ 32   │ build_id     – null-padded ASCII  (e.g. "ripcurrent")│
  │ 0x40     │ 40   │ (reserved zeros)                                     │
  └──────────┴──────┴──────────────────────────────────────────────────────┘

  ENTRY TABLE  (entry_count × 0x68 bytes, starting at offset 0x68)
  ┌──────────┬──────┬──────────────────────────────────────────────────────┐
  │ +0x00    │  4   │ flags / index  (uint32 LE)                           │
  │ +0x04    │  4   │ extra field    (uint32 LE)                           │
  │ +0x08    │  4   │ type           (uint32 LE:                           │
  │          │      │   0 = raw / partition-table block                   │
  │          │      │   1 = firmware blob (ELF / flat binary)             │
  │          │      │   2 = UFS firmware update package)                  │
  │ +0x0C    │ 76   │ name           (null-terminated ASCII string)        │
  │ +0x58    │  8   │ data_offset    (uint64 LE – byte offset in file)     │
  │ +0x60    │  8   │ data_size      (uint64 LE – payload length in bytes) │
  └──────────┴──────┴──────────────────────────────────────────────────────┘

Usage:
    python3 scripts/extract_fbpk.py bootloader-husky-ripcurrent-14.1-11156677.img
    python3 scripts/extract_fbpk.py bootloader.img --output-dir extracted/
    python3 scripts/extract_fbpk.py bootloader.img --list
    python3 scripts/extract_fbpk.py bootloader.img --json manifest.json
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

# ── Format constants (from algorythm.txt) ────────────────────────────────────
FBPK_MAGIC = b"FBPK"
FBPK_SUPPORTED_VERSION = 2

HEADER_SIZE = 0x68          # 104 bytes
HEADER_MAGIC_OFF = 0x00     # 4 bytes
HEADER_VERSION_OFF = 0x04   # uint32 LE
HEADER_ENTRY_COUNT_OFF = 0x08  # uint32 LE
HEADER_PLATFORM_OFF = 0x10  # 16 bytes, null-padded ASCII
HEADER_PLATFORM_LEN = 16
HEADER_BUILD_ID_OFF = 0x20  # 32 bytes, null-padded ASCII
HEADER_BUILD_ID_LEN = 32

ENTRY_SIZE = 0x68           # 104 bytes per entry record
ENTRY_TABLE_OFF = 0x68      # entry table starts right after the container header
ENTRY_FLAGS_OFF = 0x00      # +0x00 uint32 LE
ENTRY_EXTRA_OFF = 0x04      # +0x04 uint32 LE
ENTRY_TYPE_OFF = 0x08       # +0x08 uint32 LE
ENTRY_NAME_OFF = 0x0C       # +0x0C 76 bytes, null-terminated ASCII
ENTRY_NAME_LEN = 76
ENTRY_DATA_OFFSET_OFF = 0x58  # +0x58 uint64 LE
ENTRY_DATA_SIZE_OFF = 0x60    # +0x60 uint64 LE

ENTRY_TYPE_NAMES = {
    0: "raw",
    1: "firmware",
    2: "ufs-update",
}

_SAFE_NAME_CHARS = frozenset(
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "-_."
)


def _decode_cstring(data: bytes) -> str:
    """Return the null-terminated ASCII portion of *data*, stripping any NUL bytes."""
    nul = data.find(b"\x00")
    raw = data[:nul] if nul != -1 else data
    return raw.decode("ascii", errors="replace")


def _sanitize_name(name: str) -> str:
    """Replace characters unsafe for filenames with underscores."""
    return "".join(c if c in _SAFE_NAME_CHARS else "_" for c in name) or "unnamed"


# ── Data classes ──────────────────────────────────────────────────────────────

class FbpkHeader:
    __slots__ = ("version", "entry_count", "platform", "build_id")

    def __init__(self, version: int, entry_count: int, platform: str, build_id: str) -> None:
        self.version = version
        self.entry_count = entry_count
        self.platform = platform
        self.build_id = build_id

    def to_dict(self) -> dict[str, object]:
        return {
            "version": self.version,
            "entry_count": self.entry_count,
            "platform": self.platform,
            "build_id": self.build_id,
        }


class FbpkEntry:
    __slots__ = ("index", "flags", "extra", "type_id", "type_name", "name", "data_offset", "data_size")

    def __init__(
        self,
        index: int,
        flags: int,
        extra: int,
        type_id: int,
        name: str,
        data_offset: int,
        data_size: int,
    ) -> None:
        self.index = index
        self.flags = flags
        self.extra = extra
        self.type_id = type_id
        self.type_name = ENTRY_TYPE_NAMES.get(type_id, f"unknown-{type_id}")
        self.name = name
        self.data_offset = data_offset
        self.data_size = data_size

    @property
    def has_payload(self) -> bool:
        return self.data_size > 0 and self.data_offset > 0

    def to_dict(self) -> dict[str, object]:
        return {
            "index": self.index,
            "flags": self.flags,
            "extra": self.extra,
            "type_id": self.type_id,
            "type_name": self.type_name,
            "name": self.name,
            "data_offset": self.data_offset,
            "data_size": self.data_size,
            "has_payload": self.has_payload,
        }


# ── Parser ────────────────────────────────────────────────────────────────────

def _read_exact(data: bytes, offset: int, length: int, context: str) -> bytes:
    end = offset + length
    if end > len(data):
        raise ValueError(
            f"{context}: need {length} bytes at offset {offset:#x}, "
            f"but file is only {len(data)} bytes"
        )
    return data[offset:end]


def parse_header(data: bytes) -> FbpkHeader:
    """Parse the 0x68-byte FBPK container header."""
    if len(data) < HEADER_SIZE:
        raise ValueError(
            f"File too small for FBPK header: {len(data)} < {HEADER_SIZE} bytes"
        )

    magic = data[HEADER_MAGIC_OFF: HEADER_MAGIC_OFF + 4]
    if magic != FBPK_MAGIC:
        raise ValueError(
            f"Invalid FBPK magic: expected {FBPK_MAGIC!r}, got {magic!r}"
        )

    (version,) = struct.unpack_from("<I", data, HEADER_VERSION_OFF)
    if version != FBPK_SUPPORTED_VERSION:
        raise ValueError(
            f"Unsupported FBPK version {version}; only version {FBPK_SUPPORTED_VERSION} is supported"
        )

    (entry_count,) = struct.unpack_from("<I", data, HEADER_ENTRY_COUNT_OFF)

    platform_raw = _read_exact(data, HEADER_PLATFORM_OFF, HEADER_PLATFORM_LEN, "platform")
    platform = _decode_cstring(platform_raw)

    build_id_raw = _read_exact(data, HEADER_BUILD_ID_OFF, HEADER_BUILD_ID_LEN, "build_id")
    build_id = _decode_cstring(build_id_raw)

    return FbpkHeader(version=version, entry_count=entry_count, platform=platform, build_id=build_id)


def parse_entries(data: bytes, entry_count: int) -> list[FbpkEntry]:
    """Parse the entry table that follows the container header."""
    entries: list[FbpkEntry] = []
    for i in range(entry_count):
        entry_base = ENTRY_TABLE_OFF + i * ENTRY_SIZE
        if entry_base + ENTRY_SIZE > len(data):
            raise ValueError(
                f"Entry {i}: entry record at {entry_base:#x} extends past end of file "
                f"({len(data)} bytes)"
            )

        (flags,) = struct.unpack_from("<I", data, entry_base + ENTRY_FLAGS_OFF)
        (extra,) = struct.unpack_from("<I", data, entry_base + ENTRY_EXTRA_OFF)
        (type_id,) = struct.unpack_from("<I", data, entry_base + ENTRY_TYPE_OFF)

        name_raw = _read_exact(data, entry_base + ENTRY_NAME_OFF, ENTRY_NAME_LEN, f"entry[{i}].name")
        name = _decode_cstring(name_raw)

        (data_offset,) = struct.unpack_from("<Q", data, entry_base + ENTRY_DATA_OFFSET_OFF)
        (data_size,) = struct.unpack_from("<Q", data, entry_base + ENTRY_DATA_SIZE_OFF)

        entries.append(
            FbpkEntry(
                index=i,
                flags=flags,
                extra=extra,
                type_id=type_id,
                name=name,
                data_offset=data_offset,
                data_size=data_size,
            )
        )
    return entries


def validate_entry_bounds(entry: FbpkEntry, file_size: int) -> str | None:
    """Return an error string if the entry's payload region is out of bounds, else None."""
    if not entry.has_payload:
        return None
    end = entry.data_offset + entry.data_size
    if end > file_size:
        return (
            f"entry[{entry.index}] '{entry.name}': payload "
            f"{entry.data_offset:#x}+{entry.data_size:#x} extends past end of file ({file_size} bytes)"
        )
    return None


# ── Extraction ────────────────────────────────────────────────────────────────

def extract_entry(data: bytes, entry: FbpkEntry, output_dir: Path, seen_names: dict[str, int]) -> Path:
    """Write an entry's payload to *output_dir* and return the output path.

    Output filenames follow ALGORITHM.txt step 4e: ``<name>.bin``.
    Duplicate names (e.g. ``ufs`` appears twice) get a ``_N`` counter suffix:
    ``ufs.bin``, ``ufs_1.bin``, ``ufs_2.bin``, …
    """
    count = seen_names.get(entry.name, 0)
    seen_names[entry.name] = count + 1
    base = entry.name if count == 0 else f"{entry.name}_{count}"
    safe = _sanitize_name(base)
    out_path = output_dir / f"{safe}.bin"
    payload = data[entry.data_offset: entry.data_offset + entry.data_size]
    out_path.write_bytes(payload)
    return out_path


def extract_all(
    data: bytes,
    header: FbpkHeader,
    entries: list[FbpkEntry],
    output_dir: Path,
    verbose: bool = False,
) -> list[dict[str, object]]:
    """Extract all entries with payloads to *output_dir*; return a result list."""
    output_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, object]] = []
    seen_names: dict[str, int] = {}
    for entry in entries:
        rec: dict[str, object] = entry.to_dict()
        if not entry.has_payload:
            rec["status"] = "skipped-no-payload"
            results.append(rec)
            if verbose:
                print(f"  [skip]  [{entry.index:3d}] {entry.name!r:40s}  (no payload)")
            continue

        bounds_error = validate_entry_bounds(entry, len(data))
        if bounds_error:
            rec["status"] = "error"
            rec["error"] = bounds_error
            results.append(rec)
            print(f"  [!] {bounds_error}", file=sys.stderr)
            continue

        out_path = extract_entry(data, entry, output_dir, seen_names)
        rec["status"] = "extracted"
        rec["output_file"] = str(out_path)
        results.append(rec)
        if verbose:
            print(
                f"  [ok]    [{entry.index:3d}] {entry.name!r:40s}"
                f"  {entry.data_size:>10d} bytes  →  {out_path.name}"
            )
    return results


# ── CLI ───────────────────────────────────────────────────────────────────────

def _format_size(n: int) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024  # type: ignore[assignment]
    return f"{n} B"  # unreachable, but satisfies type checkers


def cmd_list(header: FbpkHeader, entries: list[FbpkEntry]) -> None:
    print(f"FBPK v{header.version}  platform={header.platform!r}  build_id={header.build_id!r}")
    print(f"{'idx':>4}  {'type':<12}  {'offset':>12}  {'size':>12}  name")
    print("─" * 72)
    for e in entries:
        size_s = _format_size(e.data_size) if e.has_payload else "—"
        offset_s = f"{e.data_offset:#010x}" if e.has_payload else "—"
        print(f"{e.index:4d}  {e.type_name:<12}  {offset_s:>12}  {size_s:>12}  {e.name}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Parse and extract a Google Pixel FBPK v2 bootloader container.\n\n"
            "The format specification is documented in algorythm.txt inside the\n"
            "kali-nethunter-pro bootloader repository (.upstream/)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("image", type=Path, help="Path to the FBPK v2 container image file")
    parser.add_argument(
        "-o", "--output-dir",
        type=Path,
        default=None,
        help="Directory to write extracted payloads into (default: <image-stem>-extracted/)",
    )
    parser.add_argument(
        "-l", "--list",
        action="store_true",
        help="List entries without extracting",
    )
    parser.add_argument(
        "-j", "--json",
        type=Path,
        default=None,
        metavar="FILE",
        help="Write a JSON manifest of all entries (and extraction results) to FILE",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Print per-entry progress during extraction",
    )
    args = parser.parse_args(argv)

    image_path: Path = args.image.resolve()
    if not image_path.is_file():
        print(f"[!] Image file not found: {image_path}", file=sys.stderr)
        return 1

    data = image_path.read_bytes()

    try:
        header = parse_header(data)
    except ValueError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 1

    try:
        entries = parse_entries(data, header.entry_count)
    except ValueError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 1

    if args.list:
        cmd_list(header, entries)
        if args.json:
            manifest = {
                "image": str(image_path),
                "header": header.to_dict(),
                "entries": [e.to_dict() for e in entries],
            }
            args.json.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            print(f"\nManifest written to: {args.json}")
        return 0

    output_dir: Path = args.output_dir or (image_path.parent / f"{image_path.stem}-extracted")
    print(f"FBPK v{header.version}  platform={header.platform!r}  build_id={header.build_id!r}")
    print(f"Entries : {header.entry_count}")
    print(f"Output  : {output_dir}")
    print()

    results = extract_all(data, header, entries, output_dir, verbose=args.verbose)

    extracted = sum(1 for r in results if r.get("status") == "extracted")
    skipped = sum(1 for r in results if r.get("status") == "skipped-no-payload")
    errors = sum(1 for r in results if r.get("status") == "error")

    print(f"\nExtracted: {extracted}  skipped: {skipped}  errors: {errors}")

    if args.json:
        manifest = {
            "image": str(image_path),
            "header": header.to_dict(),
            "output_dir": str(output_dir),
            "entries": results,
        }
        args.json.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(f"Manifest : {args.json}")

    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
