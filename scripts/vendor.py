#!/usr/bin/env python3
"""Vendor an immutable LibTogether revision; check copies without network access."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

SOURCE = Path(__file__).resolve().parents[1]
FILES = ("LibTogether.lua", "ReportWindow.lua", "LICENSE")
REPOSITORY = "https://github.com/AlexAllocated/LibTogether"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check(target):
    manifest = json.loads((target / "manifest.json").read_text())
    if manifest.get("repository") != REPOSITORY or set(manifest["files"]) != set(FILES):
        raise ValueError(f"Unexpected LibTogether manifest in {target}")
    for name, sha in manifest["files"].items():
        path = target / name
        if path.is_symlink() or digest(path.read_bytes()) != sha:
            raise ValueError(f"Modified embedded file: {path}")
    return manifest


def vendor(addon, ref, check_only=False):
    target = addon.resolve() / "Libs" / "LibTogether"
    # Do not follow a destination symlink out of the addon tree.
    if (addon.resolve() / "Libs").is_symlink() or target.is_symlink():
        raise ValueError(f"Refusing symlink destination: {target}")
    if check_only:
        manifest = check(target)
        print(f"{addon.name}: LibTogether {manifest['version']} @ {manifest['revision'][:12]} verified")
        return
    revision = subprocess.check_output(["git", "rev-parse", "--verify", ref + "^{commit}"], cwd=SOURCE, text=True).strip()
    payloads = {name: subprocess.check_output(["git", "show", f"{revision}:{name}"], cwd=SOURCE) for name in FILES}
    if target.exists():
        check(target)  # Preserve manual edits instead of silently overwriting.
    target.mkdir(parents=True, exist_ok=True)
    import re
    version = re.search(rb'VERSION = "([^"]+)"', payloads["LibTogether.lua"])[1].decode()
    manifest = {"schema": 1, "repository": REPOSITORY, "revision": revision, "version": version,
                "files": {name: digest(data) for name, data in payloads.items()}}
    for name, data in payloads.items():
        (target / name).write_bytes(data)
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    check(target)
    print(f"{addon.name}: embedded LibTogether {version} @ {revision[:12]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("addons", nargs="+", type=Path)
    parser.add_argument("--ref", default="HEAD", help="Commit or immutable release tag")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for addon in args.addons:
        if not addon.is_dir():
            parser.error(f"Not an addon directory: {addon}")
        vendor(addon, args.ref, args.check)


if __name__ == "__main__":
    main()
