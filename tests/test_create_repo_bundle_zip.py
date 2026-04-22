import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "create_repo_bundle_zip.py"

spec = importlib.util.spec_from_file_location("create_repo_bundle_zip", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


class FakeCompletedProcess:
    def __init__(self, stdout):
        self.stdout = stdout


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


class TestCreateRepoBundleZip(unittest.TestCase):
    def test_git_tracked_files_parses_null_separated_output(self):
        output = b"a.txt\0nested/b.txt\0"
        with mock.patch.object(module.subprocess, "run", return_value=FakeCompletedProcess(output)):
            files = module.git_tracked_files(Path("/tmp/repo"))
        self.assertEqual(files, [Path("a.txt"), Path("nested/b.txt")])

    def test_extract_urls_collects_and_sorts(self):
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            (repo_root / "one.txt").write_text("visit https://b.example/p and http://a.example", encoding="utf-8")
            (repo_root / "two.txt").write_text("again https://b.example/p", encoding="utf-8")
            tracked = [Path("one.txt"), Path("two.txt")]
            urls = module.extract_urls(repo_root, tracked)

        self.assertEqual(list(urls.keys()), ["http://a.example", "https://b.example/p"])
        self.assertEqual(urls["https://b.example/p"], ["one.txt", "two.txt"])

    def test_safe_path_component(self):
        self.assertEqual(module.safe_path_component("a/b?c=d"), "a_b_c_d")

    def test_download_links_handles_success_and_size_failure(self):
        url_locations = {
            "https://ok.example/file.bin": ["a.txt"],
            "https://bad.example/large.bin": ["b.txt"],
        }

        def fake_urlopen(request, timeout):
            if "ok.example" in request.full_url:
                return FakeResponse([b"ab", b"cd"], content_length=4)
            return FakeResponse([b"x"], content_length=module.MAX_DOWNLOAD_BYTES + 1)

        with tempfile.TemporaryDirectory() as td:
            destination = Path(td) / "linked_files"
            destination.mkdir(parents=True)

            with mock.patch.object(module.urllib.request, "urlopen", side_effect=fake_urlopen):
                results = module.download_links(url_locations, destination)

            self.assertEqual(results[0]["status"], "downloaded")
            self.assertEqual(results[0]["bytes"], 4)
            self.assertEqual(results[1]["status"], "failed")
            self.assertIn("content-length exceeds", results[1]["error"])

            downloaded_path = destination.parent / results[0]["stored_as"]
            self.assertTrue(downloaded_path.exists())

    def test_download_links_skips_urls_with_control_characters(self):
        bad_url = "https://bad.example/file\x05name.txt"
        url_locations = {
            bad_url: ["bad.txt"],
            "https://ok.example/file.bin": ["ok.txt"],
        }

        def fake_urlopen(request, timeout):
            self.assertNotIn("\x05", request.full_url)
            return FakeResponse([b"ok"], content_length=2)

        with tempfile.TemporaryDirectory() as td:
            destination = Path(td) / "linked_files"
            destination.mkdir(parents=True)

            with mock.patch.object(module.urllib.request, "urlopen", side_effect=fake_urlopen) as mock_urlopen:
                results = module.download_links(url_locations, destination)

            self.assertEqual(results[0]["status"], "skipped")
            self.assertIsNone(results[0]["stored_as"])
            self.assertIn("ASCII control characters", results[0]["error"])
            self.assertEqual(results[1]["status"], "downloaded")
            self.assertEqual(mock_urlopen.call_count, 1)

    def test_copy_tracked_files_and_create_zip(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            source_repo = root / "repo"
            source_repo.mkdir()
            (source_repo / "dir").mkdir()
            (source_repo / "dir" / "file.txt").write_text("hello", encoding="utf-8")

            dest = root / "staging"
            module.copy_tracked_files(source_repo, [Path("dir/file.txt")], dest)
            self.assertEqual((dest / "dir" / "file.txt").read_text(encoding="utf-8"), "hello")

            output_zip = root / "out" / "bundle.zip"
            module.create_zip_from_directory(dest, output_zip)

            with zipfile.ZipFile(output_zip, "r") as zf:
                self.assertEqual(sorted(zf.namelist()), ["dir/file.txt"])


if __name__ == "__main__":
    unittest.main()
