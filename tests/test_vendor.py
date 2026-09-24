"""Offline vendor integrity and migration regression tests (no network)."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("vendor", Path(__file__).resolve().parents[1] / "scripts" / "vendor.py")
vendor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(vendor)


class VendorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source_tmp = tempfile.TemporaryDirectory()
        cls.source = Path(cls.source_tmp.name)
        subprocess.run(["git", "init", "-q", str(cls.source)], check=True)
        cls.revisions = {}
        for label, names, version in (
            ("legacy3", set(vendor.LEGACY_FILES) - {"SelfTests.lua"}, "0.1.0"),
            ("legacy4", set(vendor.LEGACY_FILES), "0.2.0"),
            ("first", set(vendor.FILES), "1.0.0"),
            ("second", set(vendor.FILES), "1.1.0"),
        ):
            for path in cls.source.iterdir():
                if path.is_file():
                    path.unlink()
            for name in names:
                main = name in ("libchev.lua", "LibTogether.lua")
                (cls.source / name).write_text(f'local Library = {{ VERSION = "{version}" }}\n' if main else f"{label}: {name}\n")
            subprocess.run(["git", "add", "-A"], cwd=cls.source, check=True)
            subprocess.run(["git", "-c", "user.name=Vendor Test", "-c", "user.email=vendor@example.invalid",
                            "-c", "commit.gpgsign=false", "commit", "-qm", label], cwd=cls.source, check=True)
            cls.revisions[label] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=cls.source, text=True).strip()

    @classmethod
    def tearDownClass(cls):
        cls.source_tmp.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addon = Path(self.tmp.name) / "Addon"
        self.addon.mkdir()
        self.target = self.addon / "Libs" / "libchev"
        self.legacy = self.addon / "Libs" / "LibTogether"
        self.source_patch = patch.object(vendor, "SOURCE", self.source)
        self.source_patch.start()
        self.addCleanup(self.source_patch.stop)
        self.output_patch = contextlib.redirect_stdout(io.StringIO())
        self.output_patch.__enter__()
        self.addCleanup(self.output_patch.__exit__, None, None, None)

    def install(self, label="first", **kwargs):
        vendor.vendor(self.addon, self.revisions[label], **kwargs)

    def manifest(self):
        return json.loads((self.target / "manifest.json").read_text())

    def write_manifest(self, manifest):
        (self.target / "manifest.json").write_text(json.dumps(manifest))

    def snapshot(self, root=None):
        root = root or self.target
        return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}

    def make_legacy(self, label="legacy4"):
        revision = self.revisions[label]
        payloads = vendor.source_payloads(revision, legacy=True)
        self.legacy.mkdir(parents=True)
        for name, data in payloads.items():
            (self.legacy / name).write_bytes(data)
        manifest = {"schema": 1, "repository": vendor.LEGACY_REPOSITORY, "revision": revision,
                    "version": vendor.payload_version(payloads["LibTogether.lua"]),
                    "files": {name: vendor.digest(data) for name, data in payloads.items()}}
        (self.legacy / "manifest.json").write_text(json.dumps(manifest))
        return manifest

    def test_roundtrip_upgrade_and_check_without_git_or_network(self):
        self.install()
        manifest = self.manifest()
        self.assertEqual(manifest["revision"], self.revisions["first"])
        self.assertEqual(manifest["repository"], "https://github.com/AlexAllocated/libchev")
        self.assertEqual(set(manifest["files"]), set(vendor.FILES))
        before = self.snapshot()
        with patch.object(vendor.subprocess, "check_output", side_effect=AssertionError("check must not invoke Git")):
            vendor.vendor(self.addon, "missing-ref", check_only=True)
        self.assertEqual(before, self.snapshot())
        self.install("second")
        self.assertEqual(self.manifest()["version"], "1.1.0")
        self.assertEqual(self.manifest()["revision"], self.revisions["second"])

    def test_edited_file_is_preserved(self):
        self.install()
        (self.target / "libchev.lua").write_text("local edits\n")
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.install("second")
        self.assertEqual(before, self.snapshot())

    def test_rehashed_edits_are_preserved_during_upgrade(self):
        self.install()
        path = self.target / "ReportWindow.lua"
        path.write_text("local edits")
        manifest = self.manifest()
        manifest["files"][path.name] = vendor.digest(path.read_bytes())
        self.write_manifest(manifest)
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.install("second")
        self.assertEqual(before, self.snapshot())

    def test_strict_manifest_schema_and_complete_file_set(self):
        self.install()
        original = self.manifest()
        mutations = [
            lambda x: x.update(schema=True), lambda x: x.update(schema=2),
            lambda x: x.update(repository="https://example.invalid/forged"),
            lambda x: x.update(revision="HEAD"), lambda x: x.update(revision="a" * 39),
            lambda x: x.update(version=""), lambda x: x.update(version="2.0.0"),
            lambda x: x.update(files={}), lambda x: x["files"].pop("LICENSE"),
            lambda x: x["files"].update({"LICENSE": "z" * 64}),
            lambda x: x["files"].update({"LICENSE": 42}), lambda x: x.update(extra=True),
            lambda x: x.pop("schema"), lambda x: x.update(files=[]),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                candidate = json.loads(json.dumps(original))
                mutate(candidate)
                self.write_manifest(candidate)
                before = self.snapshot()
                with self.assertRaises(ValueError):
                    self.install("second")
                self.assertEqual(before, self.snapshot())
        for candidate in ([], None, 42, "manifest"):
            self.write_manifest(candidate)
            with self.assertRaises(ValueError):
                vendor.check(self.target)

    def test_malicious_manifest_names_are_never_read(self):
        self.install()
        original = self.manifest()
        sentinel = self.addon / "sentinel"
        sentinel.write_text("preserve me")
        for name in ("../../sentinel", str(sentinel), "libchev.lua/../LICENSE", "$(touch hacked)", "LICENSE\x00"):
            with self.subTest(name=name):
                candidate = json.loads(json.dumps(original))
                candidate["files"][name] = vendor.digest(b"preserve me")
                self.write_manifest(candidate)
                with self.assertRaises(ValueError):
                    self.install("second")
                self.assertEqual(sentinel.read_text(), "preserve me")

    def test_duplicate_manifest_keys_refused(self):
        self.install()
        path = self.target / "manifest.json"
        path.write_text(path.read_text().replace('"schema": 1', '"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):
            vendor.check(self.target)

    def test_extras_and_missing_files_refused(self):
        self.install()
        extra = self.target / "custom.lua"
        extra.write_text("keep")
        with self.assertRaises(ValueError):
            self.install("second")
        self.assertEqual(extra.read_text(), "keep")
        extra.unlink()
        (self.target / "LICENSE").unlink()
        with self.assertRaises(ValueError):
            self.install("second")

    def test_each_file_and_manifest_symlink_refused(self):
        self.install()
        for name in (*vendor.FILES, "manifest.json"):
            with self.subTest(name=name):
                path = self.target / name
                original = path.read_bytes()
                outside = Path(self.tmp.name) / "outside"
                outside.write_bytes(original)
                path.unlink()
                path.symlink_to(outside)
                with self.assertRaises(ValueError):
                    self.install("second")
                with self.assertRaises(ValueError):
                    vendor.check(self.target)
                self.assertEqual(outside.read_bytes(), original)
                path.unlink()
                path.write_bytes(original)

    def test_dangling_links_in_initial_directory_refused(self):
        self.target.mkdir(parents=True)
        for name in (*vendor.FILES, "manifest.json"):
            with self.subTest(name=name):
                path = self.target / name
                outside = Path(self.tmp.name) / "nonexistent"
                path.symlink_to(outside)
                with self.assertRaises(ValueError):
                    self.install()
                self.assertFalse(outside.exists())
                self.assertTrue(path.is_symlink())
                path.unlink()

    def test_symlink_destination_components_refused(self):
        outside = Path(self.tmp.name) / "outside"
        outside.mkdir()
        for relative in ("Libs", "Libs/libchev"):
            with self.subTest(relative=relative):
                link = self.addon / relative
                link.parent.mkdir(exist_ok=True)
                link.symlink_to(outside, target_is_directory=True)
                with self.assertRaises(ValueError):
                    self.install()
                self.assertEqual(list(outside.iterdir()), [])
                link.unlink()
        alias = Path(self.tmp.name) / "alias"
        alias.symlink_to(self.addon, target_is_directory=True)
        with self.assertRaises(ValueError):
            vendor.vendor(alias, self.revisions["first"])
        child = self.addon / "child"
        child.mkdir()
        with self.assertRaises(ValueError):
            vendor.vendor(alias / "child" / "..", self.revisions["first"])

    def test_invalid_source_leaves_existing_copy_unchanged(self):
        self.install()
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.install("legacy3")
        self.assertEqual(before, self.snapshot())

    def test_legacy_requires_explicit_flag(self):
        self.make_legacy()
        before = self.snapshot(self.legacy)
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(before, self.snapshot(self.legacy))
        self.assertFalse(self.target.exists())

    def test_verified_three_and_four_file_legacy_migrations(self):
        for label in ("legacy3", "legacy4"):
            with self.subTest(label=label):
                self.make_legacy(label)
                self.install(migrate_legacy=True)
                self.assertFalse(self.legacy.exists())
                vendor.check(self.target)

    def test_legacy_edited_files_preserved_even_with_rehashed_manifest(self):
        manifest = self.make_legacy()
        path = self.legacy / "ReportWindow.lua"
        path.write_text("local modifications")
        for rehash in (False, True):
            if rehash:
                manifest["files"]["ReportWindow.lua"] = vendor.digest(path.read_bytes())
                (self.legacy / "manifest.json").write_text(json.dumps(manifest))
            before = self.snapshot(self.legacy)
            with self.assertRaises(ValueError):
                self.install(migrate_legacy=True)
            self.assertEqual(before, self.snapshot(self.legacy))
            self.assertFalse(self.target.exists())

    def test_legacy_incomplete_manifest_cannot_hide_tracked_fourth_file(self):
        manifest = self.make_legacy()
        (self.legacy / "SelfTests.lua").unlink()
        del manifest["files"]["SelfTests.lua"]
        (self.legacy / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            self.install(migrate_legacy=True)
        self.assertTrue(self.legacy.exists())

    def test_legacy_extras_and_symlinks_are_preserved(self):
        self.make_legacy()
        extra = self.legacy / "user-notes.txt"
        extra.write_text("keep")
        with self.assertRaises(ValueError):
            self.install(migrate_legacy=True)
        self.assertEqual(extra.read_text(), "keep")
        extra.unlink()
        for name in (*vendor.LEGACY_FILES, "manifest.json"):
            with self.subTest(name=name):
                path = self.legacy / name
                data = path.read_bytes()
                outside = Path(self.tmp.name) / "outside"
                outside.write_bytes(data)
                path.unlink()
                path.symlink_to(outside)
                with self.assertRaises(ValueError):
                    self.install(migrate_legacy=True)
                self.assertTrue(path.is_symlink())
                self.assertEqual(outside.read_bytes(), data)
                path.unlink()
                path.write_bytes(data)

    def test_source_symlink_rejected(self):
        self.install()
        before = self.snapshot()
        with patch.object(vendor, "git", return_value=b"120000 blob " + b"a" * 40 + b"\tlibchev.lua\0"):
            with self.assertRaises(ValueError):
                vendor.source_payloads(self.revisions["second"])
        self.assertEqual(before, self.snapshot())

    def test_failed_migration_keeps_legacy(self):
        self.make_legacy()
        before = self.snapshot(self.legacy)
        with self.assertRaises(ValueError):
            self.install("legacy3", migrate_legacy=True)
        self.assertEqual(before, self.snapshot(self.legacy))
        with patch.object(vendor, "atomic_write", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.install(migrate_legacy=True)
        self.assertEqual(before, self.snapshot(self.legacy))

    def test_check_and_migration_are_mutually_exclusive(self):
        with patch.object(vendor.subprocess, "check_output", side_effect=AssertionError("no Git")):
            with self.assertRaises(ValueError):
                self.install(check_only=True, migrate_legacy=True)


if __name__ == "__main__":
    unittest.main()
