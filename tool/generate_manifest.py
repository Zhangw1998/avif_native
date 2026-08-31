#!/usr/bin/env python3
import gzip
import hashlib
import json
import shutil
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: generate_manifest.py <version> <owner/repository> <dist-directory>")

version, repository, dist_arg = sys.argv[1:]
dist = Path(dist_arg).resolve()
release = dist.parent / "release"
release.mkdir(parents=True, exist_ok=True)
artifacts = {}

for archive in sorted(dist.rglob("*.gz")):
    relative = archive.relative_to(dist)
    if len(relative.parts) < 3:
        raise ValueError(f"Expected <target>/<profile>/<library>.gz: {relative}")
    compressed_name = relative.name
    profile = relative.parts[-2]
    parent = relative.parts[-3]
    target = parent.removeprefix("native-")
    library_name = compressed_name[:-3]
    key = f"{target}-{profile}"
    release_name = f"{key}-{compressed_name}"
    archive_bytes = archive.read_bytes()
    library_bytes = gzip.decompress(archive_bytes)
    shutil.copyfile(archive, release / release_name)
    artifacts[key] = {
        "url": f"https://github.com/{repository}/releases/download/native-v{version}/{release_name}",
        "archiveSha256": hashlib.sha256(archive_bytes).hexdigest(),
        "librarySha256": hashlib.sha256(library_bytes).hexdigest(),
        "fileName": library_name,
    }

if not artifacts:
    raise RuntimeError("No compressed native libraries found")

(release / "manifest.json").write_text(
    json.dumps({"nativeVersion": version, "artifacts": artifacts}, indent=2) + "\n",
    encoding="utf-8",
)
