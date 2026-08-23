#!/usr/bin/env python3
"""Build a deterministic, provenance-bearing source package from Git objects.

The builder deliberately reads blobs from the requested commit instead of the
working tree.  It is a release/trust boundary: a dirty checkout, an unapproved
path, a non-regular entry, or an unrecognized sensitive value fails closed.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import sys
from typing import NoReturn
import zipfile
import zlib


TOOL_VERSION = "0.1.0"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
CONTROL_CHAR = re.compile(r"[\x00-\x1f\x7f]")
WINDOWS_LOCAL_PATH = re.compile(
    rb"(?<![A-Za-z0-9_])[A-Za-z]:[\\/](?!(?:Program Files(?: \(x86\))?|Windows)[\\/])",
    re.IGNORECASE,
)
PRIVATE_POSIX_ROOTS = tuple(b"/" + part + b"/" for part in (b"Users", b"home", b"private", b"Volumes"))
SECRET_VALUE = re.compile(
    rb"(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"
    rb"(?:AKIA|ASIA)[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|"
    rb"github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|"
    rb"xox[baprs]-[A-Za-z0-9-]{20,}|Bearer[ \t]+[A-Za-z0-9._-]{20,})"
)

ROOT_FILES = {
    ".gitignore",
    "AGENTS.md",
    "CONTEXT.md",
    "design-qa.md",
    "README.md",
    "README.zh-CN.md",
    "CHANGELOG.md",
    "LICENSE",
    "LICENSE.md",
    "LICENSE.txt",
    "NOTICE",
    "NOTICE.md",
    "NOTICE.txt",
    "ATTRIBUTION.md",
}
ALLOWED_PREFIXES = (
    ".github/",
    "checklists/",
    "cloudfunctions/medcue-ai-broker/",
    "coreai/",
    "docs/",
    "ios-app/",
    "Packages/",
    "swift-core/",
    "templates/",
    "tools/",
)
REQUIRED_PATHS = {
    ".github/workflows/native-verification.yml",
    "Packages/LlamaFramework/Package.swift",
    "README.md",
    "cloudfunctions/medcue-ai-broker/index.js",
    "cloudfunctions/medcue-ai-broker/package.json",
    "docs/THIRD_PARTY_NOTICES.md",
    "ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj",
    "swift-core/Package.swift",
    "tools/build-source-package.py",
    "tools/test-source-package.py",
    "tools/verify-native.sh",
    "tools/verify-source-package.py",
}
FORBIDDEN_SUFFIXES = (
    ".7z",
    ".avi",
    ".bin",
    ".bmp",
    ".bz2",
    ".cer",
    ".crt",
    ".db",
    ".dmg",
    ".docx",
    ".dump",
    ".gguf",
    ".gif",
    ".gz",
    ".heic",
    ".iso",
    ".jar",
    ".jpeg",
    ".jpg",
    ".jks",
    ".key",
    ".keystore",
    ".m4a",
    ".m4v",
    ".mkv",
    ".mlmodel",
    ".mobileprovision",
    ".mov",
    ".mp3",
    ".mp4",
    ".onnx",
    ".otf",
    ".p12",
    ".pdf",
    ".pem",
    ".pfx",
    ".pptx",
    ".rar",
    ".realm",
    ".sqlite",
    ".sqlite-shm",
    ".sqlite-wal",
    ".sqlite3",
    ".store",
    ".store-shm",
    ".store-wal",
    ".tar",
    ".tflite",
    ".tiff",
    ".ttf",
    ".tgz",
    ".wav",
    ".webp",
    ".xz",
    ".zip",
)
FORBIDDEN_COMPONENTS = {
    ".build",
    ".codex",
    ".codex-build",
    ".codex-local",
    ".git",
    ".hg",
    ".swiftpm",
    ".svn",
    "application support",
    "artifacts",
    "backups",
    "cookies",
    "deriveddata",
    "local storage",
    "node_modules",
    "outputs",
    "session storage",
    "xcuserdata",
}
FORBIDDEN_BASENAME = re.compile(
    r"^(?:AISecrets\.plist|\.env(?:\..*)?|.*\.gguf)$", re.IGNORECASE
)
HISTORICAL_IMAGE = re.compile(r"^IMG_[^/]+\.(?:png|jpe?g)$", re.IGNORECASE)
APP_ICON_PREFIXES = (
    "ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Assets.xcassets/AppIcon.appiconset/",
    "ios-app/MedicationAdherenceApp/MedicationAdherenceWatchApp/Assets.xcassets/AppIcon.appiconset/",
)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
WINDOWS_RESERVED_COMPONENT = re.compile(
    r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$", re.IGNORECASE
)


class PackageError(RuntimeError):
    """An input or policy violation that must stop packaging."""


def git(repo: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise PackageError(f"git {' '.join(args)} failed: {detail}")
    return result.stdout


def fail(message: str) -> NoReturn:
    raise PackageError(message)


def parse_tree(repo: Path, revision: str) -> list[dict[str, object]]:
    raw = git(repo, "ls-tree", "-r", "-z", "--full-tree", revision)
    entries: list[dict[str, object]] = []
    folded: dict[str, str] = {}
    for record in raw.split(b"\0"):
        if not record:
            continue
        try:
            metadata, path_bytes = record.split(b"\t", 1)
            mode, kind, object_sha = metadata.decode("ascii").split(" ")
            path = path_bytes.decode("utf-8")
        except (UnicodeDecodeError, ValueError) as exc:
            fail(f"cannot parse Git tree entry: {exc}")
        validate_archive_path(path, folded)
        entries.append({"mode": mode, "kind": kind, "sha": object_sha, "path": path})
    if not entries:
        fail("source revision has no tracked files")
    return entries


def validate_archive_path(path: str, folded: dict[str, str]) -> None:
    if CONTROL_CHAR.search(path) or "\\" in path:
        fail(f"forbidden control character or backslash in path: {path!r}")
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
        fail(f"unsafe archive path: {path!r}")
    key = path.casefold()
    if key in folded:
        fail(f"case-insensitive path collision: {folded[key]!r} and {path!r}")
    folded[key] = path


def allowed_path(path: str) -> bool:
    return path in ROOT_FILES or path.startswith(ALLOWED_PREFIXES)


def approved_app_icon(path: str) -> bool:
    return path.casefold().endswith(".png") and path.startswith(APP_ICON_PREFIXES)


def validate_png(path: str, data: bytes) -> None:
    if not data.startswith(PNG_SIGNATURE):
        fail(f"approved AppIcon is not a PNG file: {path}")
    offset = len(PNG_SIGNATURE)
    seen_header = False
    seen_data = False
    seen_end = False
    while offset < len(data):
        if offset + 12 > len(data):
            fail(f"approved AppIcon has a truncated PNG chunk: {path}")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            fail(f"approved AppIcon has a truncated PNG chunk: {path}")
        chunk_data = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : chunk_end])[0]
        if zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF != expected_crc:
            fail(f"approved AppIcon has an invalid PNG checksum: {path}")
        if not seen_header:
            if chunk_type != b"IHDR" or length != 13:
                fail(f"approved AppIcon is missing its PNG header: {path}")
            width, height = struct.unpack(">II", chunk_data[:8])
            if width <= 0 or height <= 0 or width > 4096 or height > 4096:
                fail(f"approved AppIcon has invalid PNG dimensions: {path}")
            seen_header = True
        elif chunk_type == b"IHDR":
            fail(f"approved AppIcon has duplicate PNG headers: {path}")
        if chunk_type == b"IDAT":
            seen_data = True
        if chunk_type == b"IEND":
            if length != 0 or chunk_end != len(data):
                fail(f"approved AppIcon has invalid trailing PNG content: {path}")
            seen_end = True
        offset = chunk_end
    if not (seen_header and seen_data and seen_end):
        fail(f"approved AppIcon has an incomplete PNG structure: {path}")


def forbidden_path(path: str) -> str | None:
    basename = path.rsplit("/", 1)[-1]
    if HISTORICAL_IMAGE.match(basename):
        return "unreferenced historical IMG_* delivery evidence"
    if FORBIDDEN_BASENAME.match(basename):
        return "secret, environment, or model artifact"
    lower = path.casefold()
    components = PurePosixPath(lower).parts
    if any(component in FORBIDDEN_COMPONENTS for component in components):
        return "cache, browser state, model, output, or historical artifact directory"
    if any(
        component.endswith((".app", ".dsym", ".framework", ".mlmodelc", ".mlpackage", ".xcarchive", ".xcresult"))
        for component in components
    ):
        return "generated application, framework, model, archive, or result bundle"
    if ".xcframework/" in lower:
        return "binary frameworks are external release inputs and are not bundled"
    if lower.endswith(".png"):
        if approved_app_icon(path):
            return None
        return "PNG is only allowed in approved AppIcon asset catalogs"
    if lower.endswith(".svg"):
        return "SVG media is not approved for this source package"
    if any(lower.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
        return "forbidden archive/media/database/credential extension"
    return None


def read_blobs(repo: Path, entries: list[dict[str, object]]) -> dict[str, bytes]:
    blobs: dict[str, bytes] = {}
    for entry in entries:
        path = str(entry["path"])
        sha = str(entry["sha"])
        kind = str(entry["kind"])
        mode = str(entry["mode"])
        if kind != "blob":
            fail(f"non-blob Git entry is not packageable: {path} ({kind})")
        if mode not in {"100644", "100755"}:
            fail(f"unsupported Git file mode for {path}: {mode}")
        if not allowed_path(path):
            fail(f"path is outside the approved source-package allowlist: {path}")
        reason = forbidden_path(path)
        if reason:
            fail(f"{path}: {reason}")
        data = git(repo, "cat-file", "blob", sha)
        if b"\0" in data and not approved_app_icon(path):
            fail(f"binary content is not an approved Asset Catalog icon: {path}")
        if approved_app_icon(path):
            validate_png(path, data)
        if not approved_app_icon(path) and (
            WINDOWS_LOCAL_PATH.search(data) or any(root in data for root in PRIVATE_POSIX_ROOTS)
        ):
            fail(f"absolute local path detected in tracked content: {path}")
        if SECRET_VALUE.search(data):
            fail(f"secret-like value detected in tracked content: {path}")
        blobs[path] = data
    missing = sorted(REQUIRED_PATHS - blobs.keys())
    if missing:
        fail(f"required build/review paths are missing: {', '.join(missing)}")
    if not any(approved_app_icon(path) for path in blobs):
        fail("required tracked Asset Catalog icons are missing")
    notice = blobs["docs/THIRD_PARTY_NOTICES.md"]
    if b"llama.cpp" not in notice or b"MIT" not in notice:
        fail("third-party notice does not document the optional llama.cpp MIT boundary")
    return blobs


def json_text(data: object) -> bytes:
    return (json.dumps(data, ensure_ascii=True, indent=2, sort_keys=True) + "\n").encode(
        "utf-8"
    )


def dependency_inventory(blobs: dict[str, bytes]) -> list[dict[str, object]]:
    package_json_path = "cloudfunctions/medcue-ai-broker/package.json"
    package_json: dict[str, object] = {}
    if package_json_path in blobs:
        try:
            package_json = json.loads(blobs[package_json_path].decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            fail(f"Broker package manifest is invalid JSON: {exc}")
    engines = package_json.get("engines", {})
    if not isinstance(engines, dict):
        fail("Broker package engines must be a JSON object")
    node_version = str(engines.get("node", "not declared"))
    for dependency_key in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        dependencies = package_json.get(dependency_key, {})
        if dependencies not in ({}, None):
            fail(f"unreviewed Broker {dependency_key} require inventory and license policy updates")
    for swift_manifest in ("swift-core/Package.swift", "Packages/LlamaFramework/Package.swift"):
        if re.search(rb"\.package\s*\(", blobs[swift_manifest]):
            fail(f"unreviewed external SwiftPM dependency in {swift_manifest}")
    llama_script = blobs.get("tools/install-llama-xcframework.sh", b"").decode(
        "utf-8", "replace"
    )
    release_match = re.search(r"LLAMA_CPP_RELEASE_TAG:-([^}\n]+)", llama_script)
    llama_release = release_match.group(1).strip() if release_match else "not declared"
    return [
        {
            "name": "MedicationAdherenceCore",
            "kind": "swiftpm-first-party",
            "source": "swift-core/Package.swift",
            "version": "local exact-revision",
            "license": "first-party repository source",
            "attributionStatus": "not-required-for-first-party-source",
        },
        {
            "name": "Node.js runtime",
            "kind": "node-runtime",
            "source": package_json_path,
            "version": node_version,
            "license": "runtime is not redistributed in this source package",
            "attributionStatus": "not-required-for-source-only-package",
        },
        {
            "name": "llama.cpp iOS XCFramework",
            "kind": "optional-binary-framework",
            "source": "tools/install-llama-xcframework.sh",
            "version": llama_release,
            "license": "MIT; external binary is not redistributed",
            "attributionStatus": "documented-in-docs/THIRD_PARTY_NOTICES.md",
            "packageStatus": "excluded-untracked-optional-runtime",
        },
    ]


def asset_inventory(blobs: dict[str, bytes]) -> dict[str, object]:
    icons = sorted(path for path in blobs if approved_app_icon(path))
    fonts = sorted(path for path in blobs if path.casefold().endswith((".ttf", ".otf")))
    media = sorted(
        path
        for path in blobs
        if path.casefold().endswith((".jpg", ".jpeg", ".gif", ".webp", ".mp3", ".mp4", ".mov"))
    )
    required_icon_roots = (
        "ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Assets.xcassets/",
        "ios-app/MedicationAdherenceApp/MedicationAdherenceWatchApp/Assets.xcassets/",
    )
    for required_root in required_icon_roots:
        if not any(path.startswith(required_root) for path in icons):
            fail(f"required product icon set is missing under {required_root}")
    icon_records = []
    for path in icons:
        contents_path = str(PurePosixPath(path).parent / "Contents.json")
        if contents_path not in blobs:
            fail(f"Asset Catalog icon has no Contents.json: {path}")
        try:
            contents = json.loads(blobs[contents_path].decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            fail(f"Asset Catalog Contents.json is invalid for {path}: {exc}")
        filenames: set[str] = set()

        def collect_filenames(value: object) -> None:
            if isinstance(value, dict):
                for key, nested in value.items():
                    if key == "filename" and isinstance(nested, str):
                        filenames.add(nested)
                    else:
                        collect_filenames(nested)
            elif isinstance(value, list):
                for nested in value:
                    collect_filenames(nested)

        collect_filenames(contents)
        if PurePosixPath(path).name not in filenames:
            fail(f"unreferenced Asset Catalog PNG is forbidden: {path}")
        icon_records.append(
            {
                "path": path,
                "sha256": hashlib.sha256(blobs[path]).hexdigest(),
                "source": "tracked first-party Asset Catalog",
                "version": "exact source revision",
                "license": "first-party repository asset",
                "attributionStatus": "not-required-for-first-party-asset",
            }
        )
    return {
        "icons": icon_records,
        "fonts": fonts,
        "fontsStatus": "none-tracked",
        "media": media,
        "mediaStatus": "none-tracked",
    }


def make_manifest(revision: str, tree: str, blobs: dict[str, bytes], entries: list[dict[str, object]]) -> dict[str, object]:
    files = []
    mode_by_path = {str(entry["path"]): str(entry["mode"]) for entry in entries}
    for path in sorted(blobs):
        files.append(
            {
                "path": path,
                "mode": mode_by_path[path],
                "size": len(blobs[path]),
                "sha256": hashlib.sha256(blobs[path]).hexdigest(),
            }
        )
    return {
        "schemaVersion": 1,
        "toolVersion": TOOL_VERSION,
        "sourceRevision": revision,
        "sourceTree": tree,
        "input": "clean exact Git commit objects; working-tree content is never read",
        "archivePolicy": {
            "rootLayout": "repository entries at ZIP root; no wrapper directory",
            "zipTimestamp": "1980-01-01T00:00:00Z",
            "compression": "deflate level 9",
            "pathChecks": ["traversal", "duplicates", "case-collisions", "control-characters"],
            "modeChecks": ["regular-files-only", "100644", "100755"],
            "sensitiveChecks": ["secrets", "models", "databases", "local-paths", "unapproved-media"],
        },
        "dependencyInventory": dependency_inventory(blobs),
        "assetInventory": asset_inventory(blobs),
        "files": files,
    }


def zip_bytes(payload: dict[str, bytes], mode_by_path: dict[str, str]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(payload):
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (int(mode_by_path.get(path, "100644"), 8) & 0xFFFF) << 16
            info.flag_bits = 0x800
            archive.writestr(info, payload[path])
    return buffer.getvalue()


def exclusive_write(path: Path, data: bytes) -> None:
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError:
        fail(f"refusing to overwrite existing output: {path}")
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
    except Exception:
        try:
            path.unlink()
        except OSError:
            pass
        raise


def build(repo: Path, revision: str, output_dir: Path) -> dict[str, object]:
    if not FULL_SHA.fullmatch(revision):
        fail("--revision must be the full 40-character lowercase commit SHA")
    repo = Path(git(repo, "rev-parse", "--show-toplevel").decode().strip()).resolve()
    output_dir = output_dir.resolve()
    try:
        output_dir.relative_to(repo)
    except ValueError:
        pass
    else:
        fail("--output-dir must be outside the Git repository")
    resolved = git(repo, "rev-parse", "--verify", f"{revision}^{{commit}}").decode().strip()
    if resolved != revision:
        fail(f"revision does not resolve to the requested exact SHA: {revision}")
    head = git(repo, "rev-parse", "HEAD").decode().strip()
    if head != revision:
        fail(f"working HEAD {head} does not equal requested revision {revision}")
    status = git(repo, "status", "--porcelain=v1", "--untracked-files=all").decode()
    if status:
        fail("working tree is dirty; staged, unstaged, and untracked content are rejected")
    entries = parse_tree(repo, revision)
    blobs = read_blobs(repo, entries)
    tree = git(repo, "rev-parse", f"{revision}^{{tree}}").decode().strip()
    manifest = make_manifest(revision, tree, blobs, entries)
    manifest_bytes = json_text(manifest)
    payload = dict(blobs)
    payload["SOURCE_MANIFEST.json"] = manifest_bytes
    mode_by_path = {str(entry["path"]): str(entry["mode"]) for entry in entries}
    mode_by_path["SOURCE_MANIFEST.json"] = "100644"
    sums = "".join(
        f"{hashlib.sha256(payload[path]).hexdigest()}  {path}\n" for path in sorted(payload)
    ).encode("utf-8")
    payload["SHA256SUMS"] = sums
    mode_by_path["SHA256SUMS"] = "100644"
    package_bytes = zip_bytes(payload, mode_by_path)
    digest = hashlib.sha256(package_bytes).hexdigest()
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = f"MedCue-source-{revision[:12]}"
    paths = {
        "zip": output_dir / f"{stem}.zip",
        "sha256": output_dir / f"{stem}.zip.sha256",
    }
    if any(path.exists() for path in paths.values()):
        fail("one or more output files already exist; output is never overwritten")
    created: list[Path] = []
    try:
        exclusive_write(paths["zip"], package_bytes)
        created.append(paths["zip"])
        exclusive_write(paths["sha256"], f"{digest}  {paths['zip'].name}\n".encode("ascii"))
        created.append(paths["sha256"])
    except Exception:
        for path in created:
            try:
                path.unlink()
            except OSError:
                pass
        raise
    return {
        "revision": revision,
        "tree": tree,
        "fileCount": len(blobs),
        "zip": str(paths["zip"]),
        "zipSha256": digest,
        "sha256File": str(paths["sha256"]),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True, help="full lowercase commit SHA; must equal HEAD")
    parser.add_argument("--output-dir", required=True, type=Path, help="external directory for non-overwritten outputs")
    parser.add_argument("--repository", type=Path, default=Path.cwd(), help="Git repository (default: current directory)")
    args = parser.parse_args(argv)
    try:
        result = build(args.repository, args.revision, args.output_dir)
    except PackageError as exc:
        print(f"source-package: ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=True, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
