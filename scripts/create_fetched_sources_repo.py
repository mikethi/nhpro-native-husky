#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

MAX_DOWNLOAD_BYTES = 100 * 1024 * 1024


@dataclass
class FetchJob:
    source_file: str
    source_type: str
    url: str
    destination: Path


def parse_simple_shell_vars(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        match = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=\"([^\"]*)\"\s*$", line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def expand_apkbuild_vars(value: str, variables: dict[str, str]) -> str:
    pattern = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")

    previous = None
    current = value
    while previous != current:
        previous = current
        current = pattern.sub(lambda m: variables.get(m.group(1), m.group(0)), current)
    return current


def extract_apkbuild_source_urls(apkbuild_path: Path) -> list[str]:
    text = apkbuild_path.read_text(encoding="utf-8", errors="ignore")
    variables = parse_simple_shell_vars(text)

    match = re.search(r'(?ms)^\s*source="(.*?)"\s*$', text)
    if not match:
        return []

    source_block = match.group(1)
    urls: list[str] = []
    for raw_line in source_block.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        expanded = expand_apkbuild_vars(line, variables)
        if expanded.startswith("http://") or expanded.startswith("https://"):
            urls.append(expanded)

    return urls


def extract_jobs(repo_root: Path) -> list[FetchJob]:
    jobs: list[FetchJob] = []

    build_script = repo_root / "nethunter-pro" / "build.sh"
    if build_script.exists():
        text = build_script.read_text(encoding="utf-8", errors="ignore")
        match = re.search(r'^\s*UPSTREAM_REPO="(https?://[^"]+)"\s*$', text, flags=re.MULTILINE)
        if match:
            jobs.append(
                FetchJob(
                    source_file=str(build_script.relative_to(repo_root)),
                    source_type="git",
                    url=match.group(1),
                    destination=Path("nethunter-pro/.upstream"),
                )
            )

    for apkbuild_path in sorted(repo_root.rglob("APKBUILD")):
        relative_apkbuild = apkbuild_path.relative_to(repo_root)
        for url in extract_apkbuild_source_urls(apkbuild_path):
            url_path = urllib.parse.urlparse(url).path
            filename = Path(url_path).name or "downloaded-source"
            destination = relative_apkbuild.parent / "sources" / filename
            jobs.append(
                FetchJob(
                    source_file=str(relative_apkbuild),
                    source_type="archive",
                    url=url,
                    destination=destination,
                )
            )

    unique: list[FetchJob] = []
    seen: set[tuple[str, str]] = set()
    for job in jobs:
        key = (job.source_type, job.url)
        if key in seen:
            continue
        seen.add(key)
        unique.append(job)
    return unique


def clone_git_repo(url: str, destination: Path, dry_run: bool) -> dict[str, object]:
    if dry_run:
        return {"status": "planned"}

    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "--no-pager", "clone", "--depth", "1", url, str(destination)],
        check=True,
        capture_output=True,
        text=True,
    )
    return {"status": "downloaded"}


def download_file(url: str, destination: Path, max_download_bytes: int, dry_run: bool) -> dict[str, object]:
    if dry_run:
        return {"status": "planned"}

    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "fetched-sources-repo/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        content_length = response.headers.get("Content-Length")
        if content_length is not None:
            length = int(content_length)
            if length > max_download_bytes:
                raise ValueError(f"content-length exceeds {max_download_bytes} bytes")

        total = 0
        chunks: list[bytes] = []
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_download_bytes:
                raise ValueError(f"download exceeds {max_download_bytes} bytes")
            chunks.append(chunk)

    data = b"".join(chunks)
    destination.write_bytes(data)
    return {"status": "downloaded", "bytes": len(data)}


def run_jobs(
    output_root: Path,
    jobs: list[FetchJob],
    max_download_bytes: int,
    dry_run: bool,
) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for job in jobs:
        destination = output_root / job.destination
        entry: dict[str, object] = {
            "source_file": job.source_file,
            "source_type": job.source_type,
            "url": job.url,
            "destination": str(job.destination),
        }
        try:
            if job.source_type == "git":
                entry.update(clone_git_repo(job.url, destination, dry_run))
            else:
                entry.update(download_file(job.url, destination, max_download_bytes, dry_run))
        except (subprocess.CalledProcessError, urllib.error.URLError, OSError, ValueError) as error:
            entry["status"] = "failed"
            entry["error"] = str(error)
        results.append(entry)
    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create a repo-style directory containing all external sources this repo fetches, "
            "placed in paths matching how they are used."
        )
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Path to repository root (default: parent of this script)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("dist/fetched-sources-repo"),
        help="Output directory (default: dist/fetched-sources-repo)",
    )
    parser.add_argument(
        "--max-download-bytes",
        type=int,
        default=MAX_DOWNLOAD_BYTES,
        help=f"Maximum bytes per downloaded archive (default: {MAX_DOWNLOAD_BYTES})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only discover and map fetch jobs without downloading.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Delete output directory first if it exists.",
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    output_dir = (repo_root / args.output_dir).resolve() if not args.output_dir.is_absolute() else args.output_dir

    if output_dir.exists():
        if not args.force:
            print(f"Output directory exists: {output_dir}", file=sys.stderr)
            print("Use --force to replace it.", file=sys.stderr)
            return 2
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    jobs = extract_jobs(repo_root)
    results = run_jobs(
        output_root=output_dir,
        jobs=jobs,
        max_download_bytes=args.max_download_bytes,
        dry_run=args.dry_run,
    )

    manifest = {
        "repo_root": str(repo_root),
        "job_count": len(jobs),
        "dry_run": args.dry_run,
        "jobs": results,
    }
    (output_dir / "fetched_sources_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    downloaded = sum(1 for item in results if item.get("status") == "downloaded")
    failed = sum(1 for item in results if item.get("status") == "failed")
    planned = sum(1 for item in results if item.get("status") == "planned")

    print(f"Created: {output_dir}")
    print(f"Fetch jobs found: {len(jobs)}")
    print(f"Downloaded: {downloaded}")
    print(f"Planned (dry-run): {planned}")
    print(f"Failed: {failed}")
    print(f"Manifest: {output_dir / 'fetched_sources_manifest.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
