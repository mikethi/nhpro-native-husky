import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "create_fetched_sources_repo.py"

spec = importlib.util.spec_from_file_location("create_fetched_sources_repo", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class FakeResponse:
    def __init__(self, chunks, content_length=None):
        self._chunks = list(chunks)
        self.headers = {}
        if content_length is not None:
            self.headers["Content-Length"] = str(content_length)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return None

    def read(self, _size):
        if not self._chunks:
            return b""
        return self._chunks.pop(0)


class TestFetchedSourcesRepo(unittest.TestCase):
    def test_parse_simple_shell_vars(self):
        text = """
# comment
PKG=abc
INVALID-NAME=value
QUOTED="quoted value"
SINGLE='single value'
BAD_SPACE=a b
"""
        values = module.parse_simple_shell_vars(text)
        self.assertEqual(values["PKG"], "abc")
        self.assertEqual(values["QUOTED"], "quoted value")
        self.assertEqual(values["SINGLE"], "single value")
        self.assertNotIn("INVALID-NAME", values)
        self.assertNotIn("BAD_SPACE", values)

    def test_expand_apkbuild_vars_recursive(self):
        variables = {"A": "$B", "B": "final"}
        self.assertEqual(module.expand_apkbuild_vars("$A", variables), "final")
        self.assertEqual(module.expand_apkbuild_vars("$UNKNOWN", variables), "$UNKNOWN")

    def test_extract_apkbuild_source_urls_multiline(self):
        with tempfile.TemporaryDirectory() as td:
            apkbuild = Path(td) / "APKBUILD"
            apkbuild.write_text(
                """
pkgname=test
pkgver=1.2.3
source="
  https://example.org/$pkgname-$pkgver.tar.gz
  not-a-url
  http://example.net/raw.bin
"
""",
                encoding="utf-8",
            )
            urls = module.extract_apkbuild_source_urls(apkbuild)

        self.assertEqual(
            urls,
            [
                "https://example.org/test-1.2.3.tar.gz",
                "http://example.net/raw.bin",
            ],
        )

    def test_extract_jobs_includes_git_and_deduplicated_archive_jobs(self):
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            build_script = repo_root / "nethunter-pro" / "build.sh"
            build_script.parent.mkdir(parents=True)
            build_script.write_text(
                'UPSTREAM_REPO="https://github.com/example/upstream.git"\n',
                encoding="utf-8",
            )

            apkbuild_a = repo_root / "device" / "a" / "APKBUILD"
            apkbuild_a.parent.mkdir(parents=True)
            apkbuild_a.write_text(
                'source="https://example.com/src.tar.gz https://example.com"\n',
                encoding="utf-8",
            )

            apkbuild_b = repo_root / "device" / "b" / "APKBUILD"
            apkbuild_b.parent.mkdir(parents=True)
            apkbuild_b.write_text(
                'source="https://example.com/src.tar.gz"\n',
                encoding="utf-8",
            )

            jobs = module.extract_jobs(repo_root)

        by_type = {}
        for job in jobs:
            by_type.setdefault(job.source_type, []).append(job)

        self.assertEqual(len(by_type["git"]), 1)
        self.assertEqual(by_type["git"][0].url, "https://github.com/example/upstream.git")

        archive_urls = sorted(job.url for job in by_type["archive"])
        self.assertEqual(
            archive_urls,
            ["https://example.com", "https://example.com/src.tar.gz"],
        )

        no_name_job = next(job for job in by_type["archive"] if job.url == "https://example.com")
        self.assertTrue(no_name_job.destination.name.startswith("downloaded-source-"))

    def test_validate_fetch_url_rejects_invalid_inputs(self):
        with self.assertRaises(ValueError):
            module.validate_fetch_url("ftp://example.com/a")
        with self.assertRaises(ValueError):
            module.validate_fetch_url("https:///missing-host")

    def test_download_file_respects_size_limits(self):
        with tempfile.TemporaryDirectory() as td:
            destination = Path(td) / "file.bin"
            with mock.patch.object(module.urllib.request, "urlopen", return_value=FakeResponse([b"abc"], content_length=3)):
                result = module.download_file("https://example.com/file.bin", destination, max_download_bytes=10, dry_run=False)
            self.assertEqual(result["status"], "downloaded")
            self.assertEqual(destination.read_bytes(), b"abc")

        with tempfile.TemporaryDirectory() as td:
            destination = Path(td) / "too-large.bin"
            with mock.patch.object(module.urllib.request, "urlopen", return_value=FakeResponse([b"abc"], content_length=999)):
                with self.assertRaises(ValueError):
                    module.download_file("https://example.com/too-large.bin", destination, max_download_bytes=10, dry_run=False)

    def test_run_jobs_handles_success_and_failure(self):
        jobs = [
            module.FetchJob("a", "git", "https://example.com/repo.git", Path("x")),
            module.FetchJob("b", "archive", "https://example.com/file.tgz", Path("y")),
            module.FetchJob("c", "archive", "ftp://bad", Path("z")),
        ]

        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(module, "clone_git_repo", return_value={"status": "downloaded"}) as clone_mock, \
                 mock.patch.object(module, "download_file", side_effect=[{"status": "downloaded", "bytes": 1}]):
                results = module.run_jobs(Path(td), jobs, max_download_bytes=100, dry_run=False)

        self.assertEqual(len(results), 3)
        self.assertEqual(results[0]["status"], "downloaded")
        self.assertEqual(results[1]["status"], "downloaded")
        self.assertEqual(results[2]["status"], "failed")
        self.assertIn("unsupported URL scheme", results[2]["error"])
        clone_mock.assert_called_once()


if __name__ == "__main__":
    unittest.main()
