#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

URL_PATTERN = re.compile(r"https?://[^\s<>)\"]+")


def git_tracked_files(repo_root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "--no-pager", "ls-files", "-z"],
        cwd=repo_root,
        check=True,
        capture_output=True,
    )
    files = [Path(item.decode("utf-8")) for item in result.stdout.split(b"\0") if item]
    return files


def extract_urls(repo_root: Path, tracked_files: list[Path]) -> dict[str, list[str]]:
    locations: dict[str, list[str]] = {}
    for relative_path in tracked_files:
        absolute_path = repo_root / relative_path
        try:
            text = absolute_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        for url in URL_PATTERN.findall(text):
            locations.setdefault(url, []).append(str(relative_path))

    return dict(sorted(locations.items()))


def safe_path_component(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", value)


def download_links(url_locations: dict[str, list[str]], destination: Path) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []

    for index, (url, referenced_by) in enumerate(url_locations.items(), start=1):
        file_name = safe_path_component(url.replace("https://", "").replace("http://", ""))
        download_name = f"{index:03d}_{file_name}"
        target_path = destination / download_name

        record: dict[str, object] = {
            "url": url,
            "referenced_by": sorted(set(referenced_by)),
            "stored_as": str(target_path.relative_to(destination.parent)),
        }

        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read()
            target_path.write_bytes(data)
            record["status"] = "downloaded"
            record["bytes"] = len(data)
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            record["status"] = "failed"
            record["error"] = str(error)

        results.append(record)

    return results


def copy_tracked_files(repo_root: Path, tracked_files: list[Path], destination: Path) -> None:
    for relative_path in tracked_files:
        source = repo_root / relative_path
        target = destination / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def create_zip_from_directory(source_dir: Path, output_zip: Path) -> None:
    output_zip.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source_dir.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(source_dir))


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create a zip containing all tracked repository files and any HTTP(S) links found in those files."
        )
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Path to repository root (default: parent of this script)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("dist/repo-and-links.zip"),
        help="Output zip path (default: dist/repo-and-links.zip)",
    )

    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    output_zip = (repo_root / args.output).resolve() if not args.output.is_absolute() else args.output

    tracked_files = git_tracked_files(repo_root)
    url_locations = extract_urls(repo_root, tracked_files)

    with tempfile.TemporaryDirectory(prefix="repo-bundle-") as temp_dir:
        staging_root = Path(temp_dir)
        repo_destination = staging_root / "repository"
        linked_destination = staging_root / "linked_files"
        linked_destination.mkdir(parents=True, exist_ok=True)

        copy_tracked_files(repo_root, tracked_files, repo_destination)
        download_results = download_links(url_locations, linked_destination)

        manifest = {
            "repo_root": str(repo_root),
            "tracked_file_count": len(tracked_files),
            "linked_url_count": len(url_locations),
            "links": download_results,
        }
        (staging_root / "linked_files_manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True),
            encoding="utf-8",
        )

        create_zip_from_directory(staging_root, output_zip)

    downloaded = sum(1 for entry in download_results if entry.get("status") == "downloaded")
    failed = sum(1 for entry in download_results if entry.get("status") == "failed")

    print(f"Created: {output_zip}")
    print(f"Tracked files added: {len(tracked_files)}")
    print(f"Linked URLs found: {len(url_locations)}")
    print(f"Linked URLs downloaded: {downloaded}")
    print(f"Linked URLs failed: {failed}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
