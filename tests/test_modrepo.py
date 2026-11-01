#!/usr/bin/env python3
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from lualoader_modrepo import (  # noqa: E402
    PackageRejected,
    PackageSkipped,
    import_packages,
    rebuild_index,
    scan_package,
)


def make_zip(path: Path, *, pkg_id="example.mod", package_id=None,
             extra=None, main_mtime=None):
    info_id = package_id or pkg_id
    info = {"pkgId": info_id, "name": "Example", "version": "1.2.3", "versionCode": 7}
    manifest = {"type": "Mod", "file": "luamod.json", "parentLoader": "lzup333.lualoader"}
    lua = {"main": "main.lua", "pkg_id": pkg_id, "version": "1.2.3", "version_code": 7}
    entries = {
        "Info.json": json.dumps(info),
        "Manifest.json": json.dumps(manifest),
        "luamod.json": json.dumps(lua),
        "Resources/lib/main.lua": "return {}\n",
    }
    entries.update(extra or {})
    with zipfile.ZipFile(path, "w") as zf:
        for name, content in entries.items():
            if main_mtime and name == "Resources/lib/main.lua":
                stamp = (*main_mtime[:6],)
                zi = zipfile.ZipInfo(name, date_time=stamp)
                zf.writestr(zi, content)
            else:
                zf.writestr(name, content)


class ModRepoTests(unittest.TestCase):
    def test_scan_reads_metadata_and_main_mtime(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "example.zip"
            make_zip(path, main_mtime=(2025, 1, 2, 3, 4, 5))
            result = scan_package(path)
            self.assertEqual(result.pkg_id, "example.mod")
            self.assertEqual(result.version, "1.2.3")
            self.assertEqual(result.main_path, "Resources/lib/main.lua")
            self.assertIn("2025-01-02T03:04:04", result.main_mtime)

    def test_native_binary_is_skipped_but_native_directory_is_allowed(self):
        with tempfile.TemporaryDirectory() as td:
            accepted = Path(td) / "accepted.zip"
            make_zip(accepted, extra={"native/README.txt": "directory only"})
            self.assertNotIsInstance(scan_package(accepted), PackageSkipped)

            skipped = Path(td) / "skipped.zip"
            make_zip(skipped, extra={"native/android_arm64/example.so": b"ELF"})
            with self.assertRaises(PackageSkipped) as raised:
                scan_package(skipped)
            self.assertIn("example.so", str(raised.exception))

    def test_metadata_id_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "mismatch.zip"
            make_zip(path, pkg_id="lua.one", package_id="info.two")
            with self.assertRaises(PackageRejected):
                scan_package(path)

    def test_zip_path_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "unsafe.zip"
            make_zip(path, extra={"../outside.txt": "bad"})
            with self.assertRaises(PackageRejected):
                scan_package(path)

    def test_import_extracts_pkgid_directory_and_builds_dist_and_index(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td) / "source.zip"
            repo = Path(td) / "repo"
            make_zip(source)
            report = import_packages(repo, [source], interactive=False)
            self.assertEqual(report.accepted, 1)
            self.assertTrue((repo / "packages/example.mod/Resources/lib/main.lua").is_file())
            self.assertTrue((repo / "dist/example.mod.tefpkg").is_file())
            index = rebuild_index(repo)
            self.assertEqual(index["packages"][0]["pkgId"], "example.mod")
            self.assertEqual(index["packages"][0]["path"], "dist/example.mod.tefpkg")


if __name__ == "__main__":
    unittest.main()
