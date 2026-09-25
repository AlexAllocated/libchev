#!/usr/bin/env python3
"""Vendor an immutable libchev revision; check copies without network access."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[1]
FILES_V1_0 = ("libchev.lua", "ReportWindow.lua", "SelfTests.lua", "LICENSE")
FILES = ("libchev.lua", "Debug.lua", "DebugWindow.lua", "ReportWindow.lua", "SelfTests.lua", "LICENSE")
VERSION_FILES = {"1.0.0": FILES_V1_0, "1.1.0": FILES, "1.1.1": FILES, "1.1.2": FILES, "1.1.3": FILES}
REPOSITORY = "https://github.com/AlexAllocated/libchev"
LEGACY_FILES = ("LibTogether.lua", "ReportWindow.lua", "SelfTests.lua", "LICENSE")
LEGACY_REPOSITORY = "https://github.com/AlexAllocated/LibTogether"
REVISION = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
HASH = re.compile(r"[0-9a-f]{64}\Z")
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\Z")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(path):
    """Check original components before normalizing, including dangling links."""
    absolute = Path(path).absolute()
    for component in (*reversed(absolute.parents), absolute):
        if component.is_symlink():
            raise ValueError(f"Refusing symlink path: {component}")
    return Path(os.path.abspath(absolute))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate manifest key: {key}")
        result[key] = value
    return result


def payload_version(data):
    match = re.search(rb'\bVERSION\s*=\s*"([^"\r\n]+)"', data)
    if not match:
        raise ValueError("Missing library VERSION")
    version = match[1].decode("ascii")
    if not VERSION.fullmatch(version):
        raise ValueError("Invalid library VERSION")
    return version


def version_files(version):
    try:
        return VERSION_FILES[version]
    except KeyError:
        raise ValueError(f"Unsupported libchev version: {version}") from None


def check(target, *, legacy=False):
    """Validate local bytes only; this deliberately never invokes Git/network."""
    target = safe_path(target)
    manifest_path = safe_path(target / "manifest.json")
    if not manifest_path.is_file():
        raise ValueError(f"Missing vendor manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(), object_pairs_hook=unique_object)
    fields = {"schema", "repository", "revision", "version", "files"}
    repository = LEGACY_REPOSITORY if legacy else REPOSITORY
    if (not isinstance(manifest, dict) or set(manifest) != fields
            or type(manifest["schema"]) is not int or manifest["schema"] != 1
            or manifest["repository"] != repository
            or not isinstance(manifest["revision"], str) or not REVISION.fullmatch(manifest["revision"])
            or not isinstance(manifest["version"], str) or not VERSION.fullmatch(manifest["version"])
            or not isinstance(manifest["files"], dict)
            or any(not isinstance(value, str) or not HASH.fullmatch(value)
                   for value in manifest["files"].values())):
        raise ValueError(f"Invalid or incomplete vendor manifest: {target}")
    allowed = ([set(LEGACY_FILES), set(LEGACY_FILES) - {"SelfTests.lua"}] if legacy
               else [set(version_files(manifest["version"]))])
    if set(manifest["files"]) not in allowed:
        raise ValueError(f"Invalid or incomplete vendor file set: {target}")
    expected = set(manifest["files"]) | {"manifest.json"}
    if {path.name for path in target.iterdir()} != expected:
        raise ValueError(f"Unexpected or missing vendor files: {target}")
    for name, sha in manifest["files"].items():
        path = safe_path(target / name)
        if not path.is_file() or digest(path.read_bytes()) != sha:
            raise ValueError(f"Modified embedded file: {path}")
    main_file = "LibTogether.lua" if legacy else "libchev.lua"
    if payload_version((target / main_file).read_bytes()) != manifest["version"]:
        raise ValueError(f"Manifest VERSION disagrees with library: {target}")
    return manifest


def git(*args):
    return subprocess.check_output(["git", *args], cwd=SOURCE)


def resolve_revision(ref):
    revision = git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}").decode().strip()
    if not REVISION.fullmatch(revision):
        raise ValueError("Git did not return a complete commit revision")
    return revision


def source_payloads(revision, *, legacy=False):
    names = LEGACY_FILES if legacy else FILES
    entries = git("ls-tree", "-z", revision, "--", *names).split(b"\0")
    tracked = {}
    for entry in entries:
        if entry:
            metadata, name = entry.split(b"\t", 1)
            mode, kind, _ = metadata.split()
            if kind != b"blob" or mode not in (b"100644", b"100755"):
                raise ValueError(f"Source is not a regular tracked file: {name!r}")
            tracked[name.decode("ascii")] = True
    main_file = "LibTogether.lua" if legacy else "libchev.lua"
    if main_file not in tracked:
        raise ValueError(f"Missing library source at {revision}")
    main_payload = git("show", f"{revision}:{main_file}")
    if legacy:
        expected = set(names)
        if "SelfTests.lua" not in tracked:
            expected.remove("SelfTests.lua")
    else:
        expected = set(version_files(payload_version(main_payload)))
    if set(tracked) != expected:
        raise ValueError(f"Incomplete library source at {revision}")
    return {name: main_payload if name == main_file else git("show", f"{revision}:{name}")
            for name in names if name in expected}


def verify_source(target, *, legacy=False):
    manifest = check(target, legacy=legacy)
    revision = resolve_revision(manifest["revision"])
    if revision != manifest["revision"]:
        raise ValueError("Vendor manifest does not name an exact commit")
    payloads = source_payloads(revision, legacy=legacy)
    if manifest["files"] != {name: digest(data) for name, data in payloads.items()}:
        raise ValueError(f"Vendor files disagree with historical Git revision: {target}")
    main_file = "LibTogether.lua" if legacy else "libchev.lua"
    if payload_version(payloads[main_file]) != manifest["version"]:
        raise ValueError("Vendor version disagrees with historical Git revision")
    return manifest


def atomic_write(path, data):
    safe_path(path)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".vendor-", delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            os.fchmod(output.fileno(), 0o644)
        except BaseException:
            temporary.unlink()
            raise
    try:
        safe_path(path)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def vendor(addon, ref, check_only=False, migrate_legacy=False):
    addon = safe_path(addon)
    if not addon.is_dir():
        raise ValueError(f"Not an addon directory: {addon}")
    target = safe_path(addon / "Libs" / "libchev")
    legacy = safe_path(addon / "Libs" / "LibTogether")
    if check_only and migrate_legacy:
        raise ValueError("--check cannot be combined with --migrate-legacy")
    old_manifest = None
    if legacy.exists():
        if not migrate_legacy:
            raise ValueError(f"Legacy directory exists: {legacy}; use --migrate-legacy to verify and migrate it")
        old_manifest = verify_source(legacy, legacy=True)
    if check_only:
        manifest = check(target)
        print(f"{addon.name}: libchev {manifest['version']} @ {manifest['revision'][:12]} verified")
        return
    installed_manifest = None
    if target.exists():
        # A rehashed manifest must not disguise edits during an upgrade either.
        installed_manifest = verify_source(target)
    revision = resolve_revision(ref)
    payloads = source_payloads(revision)
    if installed_manifest is not None and not set(installed_manifest["files"]).issubset(payloads):
        raise ValueError("Refusing a downgrade that would remove installed vendor files")
    version = payload_version(payloads["libchev.lua"])
    manifest = {"schema": 1, "repository": REPOSITORY, "revision": revision, "version": version,
                "files": {name: digest(data) for name, data in payloads.items()}}
    target.mkdir(parents=True, exist_ok=True)
    for name, data in payloads.items():
        atomic_write(target / name, data)
    atomic_write(target / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode())
    check(target)
    if old_manifest is not None:
        # Recheck before deletion; never recursively remove an unverified tree.
        if check(legacy, legacy=True) != old_manifest:
            raise ValueError("Legacy directory changed during migration; retained for review")
        for name in (*old_manifest["files"], "manifest.json"):
            safe_path(legacy / name).unlink()
        legacy.rmdir()
    print(f"{addon.name}: embedded libchev {version} @ {revision[:12]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("addons", nargs="+", type=Path)
    parser.add_argument("--ref", default="HEAD", help="Commit or immutable release tag")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--migrate-legacy", action="store_true", help="Verify historical LibTogether files, migrate, then remove the old copy")
    args = parser.parse_args()
    try:
        for addon in args.addons:
            vendor(addon, args.ref, args.check, args.migrate_legacy)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
