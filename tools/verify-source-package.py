#!/usr/bin/env python3
"""Verify a MedCue source ZIP and its external SHA-256 without extracting it."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import NoReturn
import zipfile


FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
SUM_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")
CONTROL_CHAR = re.compile(r"[\x00-\x1f\x7f]")
WINDOWS_RESERVED_COMPONENT = re.compile(
    r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$", re.IGNORECASE
)
MAX_ENTRIES = 10_000
MAX_ENTRY_SIZE = 32 * 1024 * 1024
MAX_TOTAL_SIZE = 128 * 1024 * 1024


class VerificationError(RuntimeError):
    pass


def fail(message: str) -> NoReturn:
    raise VerificationError(message)


def validate_path(path: str, folded: dict[str, str]) -> None:
    if CONTROL_CHAR.search(path) or "\\" in path:
        fail(f"unsafe control character or backslash in ZIP entry: {path!r}")
    pure = PurePosixPath(path)
    if (
        path.startswith("/")
        or pure.as_posix() != path
        or any(part in {"", ".", ".."} for part in pure.parts)
        or any(
            ":" in part
            or part.endswith((" ", "."))
            or WINDOWS_RESERVED_COMPONENT.fullmatch(part)
            for part in pure.parts
        )
    ):
        fail(f"unsafe ZIP entry path: {path!r}")
    key = path.casefold()
    if key in folded:
        fail(f"case-insensitive ZIP path collision: {folded[key]!r} and {path!r}")
    folded[key] = path


def parse_external_digest(zip_path: Path, digest_path: Path) -> str:
    try:
        lines = digest_path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        fail(f"cannot read external SHA-256 file: {exc}")
    if len(lines) != 1:
        fail("external SHA-256 file must contain exactly one line")
    match = SUM_LINE.fullmatch(lines[0])
    if not match or match.group(2) != zip_path.name:
        fail("external SHA-256 line has an invalid digest or ZIP filename")
    hasher = hashlib.sha256()
    try:
        with zip_path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                hasher.update(chunk)
    except OSError as exc:
        fail(f"cannot read ZIP archive: {exc}")
    actual = hasher.hexdigest()
    if match.group(1) != actual:
        fail("external ZIP SHA-256 does not match the archive")
    return actual


def verify(zip_path: Path, digest_path: Path) -> dict[str, object]:
    zip_path = zip_path.resolve()
    digest_path = digest_path.resolve()
    digest = parse_external_digest(zip_path, digest_path)
    try:
        archive = zipfile.ZipFile(zip_path)
    except (OSError, zipfile.BadZipFile) as exc:
        fail(f"cannot open ZIP archive: {exc}")
    with archive:
        infos = archive.infolist()
        if not infos or len(infos) > MAX_ENTRIES:
            fail(f"ZIP entry count must be between 1 and {MAX_ENTRIES}")
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            fail("duplicate ZIP entry names are forbidden")
        folded: dict[str, str] = {}
        mode_by_path: dict[str, str] = {}
        data_by_path: dict[str, bytes] = {}
        total_size = 0
        for info in infos:
            validate_path(info.filename, folded)
            if info.is_dir():
                fail(f"directory entries are not allowed: {info.filename}")
            if info.flag_bits & 0x1:
                fail(f"encrypted ZIP entries are not allowed: {info.filename}")
            if info.compress_type != zipfile.ZIP_DEFLATED:
                fail(f"unsupported ZIP compression for {info.filename}")
            if info.date_time != (1980, 1, 1, 0, 0, 0):
                fail(f"non-deterministic ZIP timestamp for {info.filename}")
            if info.file_size > MAX_ENTRY_SIZE:
                fail(f"ZIP entry exceeds size limit: {info.filename}")
            total_size += info.file_size
            if total_size > MAX_TOTAL_SIZE:
                fail("ZIP uncompressed payload exceeds size limit")
            mode = (info.external_attr >> 16) & 0xFFFF
            if mode not in {0o100644, 0o100755}:
                fail(f"unsupported ZIP file mode for {info.filename}: {mode:o}")
            mode_by_path[info.filename] = f"{mode:o}"
            data_by_path[info.filename] = archive.read(info)
        if archive.testzip() is not None:
            fail("ZIP integrity test found a corrupt entry")

    required = {"SOURCE_MANIFEST.json", "SHA256SUMS"}
    if not required.issubset(data_by_path):
        fail("ZIP is missing SOURCE_MANIFEST.json or SHA256SUMS")
    if "README.md" not in data_by_path or "tools/build-source-package.py" not in data_by_path:
        fail("ZIP root layout is missing required repository entries")
    try:
        manifest = json.loads(data_by_path["SOURCE_MANIFEST.json"].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"SOURCE_MANIFEST.json is invalid: {exc}")
    revision = manifest.get("sourceRevision")
    tree = manifest.get("sourceTree")
    if manifest.get("schemaVersion") != 1:
        fail("unsupported manifest schemaVersion")
    archive_policy = manifest.get("archivePolicy")
    if not isinstance(archive_policy, dict) or archive_policy.get("rootLayout") != "repository entries at ZIP root; no wrapper directory":
        fail("manifest root-layout policy is missing or unsupported")
    if not isinstance(manifest.get("dependencyInventory"), list):
        fail("manifest dependencyInventory must be an array")
    if not isinstance(manifest.get("assetInventory"), dict):
        fail("manifest assetInventory must be an object")
    dependency_inventory = manifest["dependencyInventory"]
    if not dependency_inventory:
        fail("manifest dependencyInventory must not be empty")
    for dependency in dependency_inventory:
        if not isinstance(dependency, dict) or any(
            not isinstance(dependency.get(field), str) or not dependency[field]
            for field in ("name", "kind", "source", "version", "license", "attributionStatus")
        ):
            fail("manifest dependency inventory entry is incomplete")
    asset_inventory = manifest["assetInventory"]
    icons = asset_inventory.get("icons")
    if not isinstance(icons, list) or not icons:
        fail("manifest icon inventory must not be empty")
    for icon in icons:
        if not isinstance(icon, dict) or any(
            not isinstance(icon.get(field), str) or not icon[field]
            for field in ("path", "sha256", "source", "version", "license", "attributionStatus")
        ):
            fail("manifest icon inventory entry is incomplete")
    if asset_inventory.get("fonts") != [] or asset_inventory.get("fontsStatus") != "none-tracked":
        fail("manifest font inventory is not the approved empty state")
    if asset_inventory.get("media") != [] or asset_inventory.get("mediaStatus") != "none-tracked":
        fail("manifest media inventory is not the approved empty state")
    if not isinstance(revision, str) or not FULL_SHA.fullmatch(revision):
        fail("manifest sourceRevision is not a full lowercase SHA")
    if not isinstance(tree, str) or not FULL_SHA.fullmatch(tree):
        fail("manifest sourceTree is not a full lowercase SHA")

    records = manifest.get("files")
    if not isinstance(records, list):
        fail("manifest files must be an array")
    manifest_paths: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            fail("manifest file record must be an object")
        path = record.get("path")
        if not isinstance(path, str) or path in manifest_paths:
            fail("manifest file paths must be unique strings")
        manifest_paths.add(path)
        if path not in data_by_path:
            fail(f"manifest references missing ZIP entry: {path}")
        data = data_by_path[path]
        if record.get("size") != len(data):
            fail(f"manifest size mismatch: {path}")
        if record.get("sha256") != hashlib.sha256(data).hexdigest():
            fail(f"manifest SHA-256 mismatch: {path}")
        if record.get("mode") != mode_by_path[path]:
            fail(f"manifest mode mismatch: {path}")
    source_entries = set(data_by_path) - required
    if manifest_paths != source_entries:
        fail("manifest file set does not equal the source payload set")

    try:
        sum_lines = data_by_path["SHA256SUMS"].decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        fail(f"SHA256SUMS is not UTF-8: {exc}")
    sum_paths: set[str] = set()
    for line in sum_lines:
        match = SUM_LINE.fullmatch(line)
        if not match:
            fail("SHA256SUMS contains an invalid line")
        expected, path = match.groups()
        if path in sum_paths or path not in data_by_path or path == "SHA256SUMS":
            fail(f"SHA256SUMS contains a duplicate or unknown path: {path}")
        sum_paths.add(path)
        if hashlib.sha256(data_by_path[path]).hexdigest() != expected:
            fail(f"SHA256SUMS digest mismatch: {path}")
    if sum_paths != set(data_by_path) - {"SHA256SUMS"}:
        fail("SHA256SUMS does not cover the complete payload")
    return {
        "sourceRevision": revision,
        "sourceTree": tree,
        "entryCount": len(data_by_path),
        "zipSha256": digest,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", type=Path)
    parser.add_argument("sha256", type=Path)
    args = parser.parse_args(argv)
    try:
        result = verify(args.zip, args.sha256)
    except VerificationError as exc:
        print(f"source-package-verify: ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=True, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
