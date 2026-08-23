#!/usr/bin/env python3
"""Synthetic, data-free tests for the exact-source package boundary."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build-source-package.py"
VERIFIER = ROOT / "tools" / "verify-source-package.py"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("source_package_builder", BUILDER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load source-package builder")
SOURCE_PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SOURCE_PACKAGE)


def command(*args: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=check)


class SourcePackageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="medcue-source-package-test-"))
        self.repo = self.temp / "repo"
        self.repo.mkdir()
        command("git", "init", "-q", "-b", "main", cwd=self.repo)
        command("git", "config", "user.email", "test@example.invalid", cwd=self.repo)
        command("git", "config", "user.name", "Source Package Test", cwd=self.repo)
        self.write("README.md", "synthetic source\n")
        self.write("swift-core/Package.swift", "// swift-tools-version: 6.3\n")
        self.write("cloudfunctions/medcue-ai-broker/package.json", '{"engines":{"node":">=18"}}\n')
        self.write(".github/workflows/native-verification.yml", "name: synthetic\n")
        self.write("Packages/LlamaFramework/Package.swift", "// swift-tools-version: 6.3\n")
        self.write("cloudfunctions/medcue-ai-broker/index.js", "export {};\n")
        self.write("ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj", "// synthetic\n")
        self.write("tools/build-source-package.py", "# synthetic package entry\n")
        self.write("tools/test-source-package.py", "# synthetic test entry\n")
        self.write("tools/verify-source-package.py", "# synthetic verifier entry\n")
        self.write("tools/verify-native.sh", "#!/usr/bin/env bash\n")
        self.write("docs/THIRD_PARTY_NOTICES.md", "llama.cpp MIT; source-only notice.\n")
        self.write(
            "ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
            b"PNG synthetic iOS icon",
        )
        self.write(
            "ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Assets.xcassets/AppIcon.appiconset/Contents.json",
            '{"images":[{"filename":"AppIcon-1024.png"}]}\n',
        )
        self.write(
            "ios-app/MedicationAdherenceApp/MedicationAdherenceWatchApp/Assets.xcassets/AppIcon.appiconset/WatchIcon-1024.png",
            b"PNG synthetic Watch icon",
        )
        self.write(
            "ios-app/MedicationAdherenceApp/MedicationAdherenceWatchApp/Assets.xcassets/AppIcon.appiconset/Contents.json",
            '{"images":[{"filename":"WatchIcon-1024.png"}]}\n',
        )
        self.commit()

    def tearDown(self) -> None:
        shutil.rmtree(self.temp, ignore_errors=True)

    def write(self, relative: str, data: str | bytes) -> None:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(data, str):
            path.write_text(data, encoding="utf-8")
        else:
            path.write_bytes(data)

    def commit(self) -> str:
        command("git", "add", "-A", cwd=self.repo)
        command("git", "commit", "-qm", "synthetic source", cwd=self.repo)
        return command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()

    def run_builder(self, revision: str, output: Path) -> subprocess.CompletedProcess[str]:
        return command(
            sys.executable,
            str(BUILDER),
            "--revision",
            revision,
            "--output-dir",
            str(output),
            "--repository",
            str(self.repo),
            cwd=ROOT,
            check=False,
        )

    def test_reproducible_zip_manifest_and_non_overwrite(self) -> None:
        revision = command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()
        first = self.temp / "out-a"
        second = self.temp / "out-b"
        result_a = self.run_builder(revision, first)
        self.assertEqual(result_a.returncode, 0, result_a.stderr)
        result_b = self.run_builder(revision, second)
        self.assertEqual(result_b.returncode, 0, result_b.stderr)
        zip_a = next(first.glob("*.zip"))
        zip_b = next(second.glob("*.zip"))
        self.assertEqual(hashlib.sha256(zip_a.read_bytes()).digest(), hashlib.sha256(zip_b.read_bytes()).digest())
        verified = command(
            sys.executable,
            str(VERIFIER),
            str(zip_a),
            str(next(first.glob("*.zip.sha256"))),
            cwd=ROOT,
            check=False,
        )
        self.assertEqual(verified.returncode, 0, verified.stderr)
        with zipfile.ZipFile(zip_a) as archive:
            names = archive.namelist()
            self.assertIn("README.md", names)
            self.assertIn("SOURCE_MANIFEST.json", names)
            self.assertIn("SHA256SUMS", names)
            self.assertFalse(any(name.startswith("repo/") for name in names))
            manifest = json.loads(archive.read("SOURCE_MANIFEST.json"))
            self.assertEqual(manifest["sourceRevision"], revision)
            self.assertEqual(manifest["sourceTree"], command("git", "rev-parse", "HEAD^{tree}", cwd=self.repo).stdout.strip())
            sums = archive.read("SHA256SUMS").decode("utf-8").splitlines()
            self.assertTrue(all(len(line.split()) == 2 for line in sums))
        again = self.run_builder(revision, first)
        self.assertNotEqual(again.returncode, 0)
        self.assertIn("never overwritten", again.stderr)

        bad_digest = second / "bad.sha256"
        bad_digest.write_text("0" * 64 + f"  {zip_b.name}\n", encoding="ascii")
        rejected = command(
            sys.executable,
            str(VERIFIER),
            str(zip_b),
            str(bad_digest),
            cwd=ROOT,
            check=False,
        )
        self.assertNotEqual(rejected.returncode, 0)

    def test_dirty_and_untracked_checkout_fail(self) -> None:
        revision = command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()
        self.write("README.md", "changed\n")
        dirty = self.run_builder(revision, self.temp / "dirty")
        self.assertNotEqual(dirty.returncode, 0)
        self.assertIn("dirty", dirty.stderr)
        command("git", "checkout", "--", "README.md", cwd=self.repo)
        self.write("untracked.txt", "not committed\n")
        untracked = self.run_builder(revision, self.temp / "untracked")
        self.assertNotEqual(untracked.returncode, 0)

        command("git", "clean", "-qf", cwd=self.repo)
        self.write("README.md", "staged\n")
        command("git", "add", "README.md", cwd=self.repo)
        staged = self.run_builder(revision, self.temp / "staged")
        self.assertNotEqual(staged.returncode, 0)

    def test_forbidden_path_and_content_fail_closed(self) -> None:
        self.write("docs/delivery.zip", "not an archive\n")
        revision = self.commit()
        forbidden = self.run_builder(revision, self.temp / "forbidden")
        self.assertNotEqual(forbidden.returncode, 0)
        self.assertIn("forbidden archive", forbidden.stderr)

        command("git", "rm", "-q", "docs/delivery.zip", cwd=self.repo)
        private_path = "C:" + "\\Users\\fixture\\private.txt\n"
        self.write("docs/path.md", private_path)
        revision = self.commit()
        local_path = self.run_builder(revision, self.temp / "local-path")
        self.assertNotEqual(local_path.returncode, 0)
        self.assertIn("absolute local path", local_path.stderr)

        command("git", "rm", "-q", "docs/path.md", cwd=self.repo)
        self.write("tools/node_modules/cache.js", "synthetic cache\n")
        revision = self.commit()
        cache = self.run_builder(revision, self.temp / "cache")
        self.assertNotEqual(cache.returncode, 0)
        self.assertIn("cache", cache.stderr)

    def test_invalid_revision_head_mismatch_and_secret_fail(self) -> None:
        revision = command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()
        abbreviated = self.run_builder(revision[:12], self.temp / "short")
        self.assertNotEqual(abbreviated.returncode, 0)
        self.assertIn("full 40-character", abbreviated.stderr)

        old_revision = revision
        self.write("docs/new.md", "new revision\n")
        self.commit()
        mismatch = self.run_builder(old_revision, self.temp / "mismatch")
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertIn("does not equal requested revision", mismatch.stderr)

        token = "github" + "_pat_" + ("A" * 25)
        self.write("docs/secret.md", token + "\n")
        secret_revision = self.commit()
        secret = self.run_builder(secret_revision, self.temp / "secret")
        self.assertNotEqual(secret.returncode, 0)
        self.assertIn("secret-like value", secret.stderr)
        self.assertNotIn(token, secret.stderr)

    def test_historical_image_and_submodule_fail(self) -> None:
        self.write("docs/IMG_1234.png", b"synthetic historical evidence")
        revision = self.commit()
        historical = self.run_builder(revision, self.temp / "historical")
        self.assertNotEqual(historical.returncode, 0)

        command("git", "rm", "-q", "docs/IMG_1234.png", cwd=self.repo)
        command("git", "commit", "-qm", "remove synthetic image", cwd=self.repo)
        commit_sha = command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()
        command("git", "update-index", "--add", "--cacheinfo", f"160000,{commit_sha},module", cwd=self.repo)
        command("git", "commit", "-qm", "synthetic gitlink", cwd=self.repo)
        gitlink_revision = command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()
        entries = SOURCE_PACKAGE.parse_tree(self.repo, gitlink_revision)
        with self.assertRaises(SOURCE_PACKAGE.PackageError):
            SOURCE_PACKAGE.read_blobs(self.repo, entries)

    def test_path_validation_rejects_traversal_control_and_collision(self) -> None:
        folded: dict[str, str] = {}
        SOURCE_PACKAGE.validate_archive_path("docs/ok.md", folded)
        for path in ("../escape", "/absolute", "docs/../escape", "docs\\bad", "docs/bad\nname"):
            with self.assertRaises(SOURCE_PACKAGE.PackageError):
                SOURCE_PACKAGE.validate_archive_path(path, folded.copy())
        with self.assertRaises(SOURCE_PACKAGE.PackageError):
            SOURCE_PACKAGE.validate_archive_path("DOCS/OK.MD", folded)

    def test_verifier_rejects_duplicate_traversal_and_case_collision(self) -> None:
        def rejected_archive(name: str, entries: list[str]) -> subprocess.CompletedProcess[str]:
            archive_path = self.temp / f"{name}.zip"
            with warnings.catch_warnings(), zipfile.ZipFile(
                archive_path, "w", compression=zipfile.ZIP_DEFLATED
            ) as archive:
                warnings.simplefilter("ignore", UserWarning)
                for entry in entries:
                    info = zipfile.ZipInfo(entry, date_time=(1980, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.create_system = 3
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, b"synthetic")
            digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            digest_path = self.temp / f"{name}.sha256"
            digest_path.write_text(f"{digest}  {archive_path.name}\n", encoding="ascii")
            return command(
                sys.executable,
                str(VERIFIER),
                str(archive_path),
                str(digest_path),
                cwd=ROOT,
                check=False,
            )

        duplicate = rejected_archive("duplicate", ["README.md", "README.md"])
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn("duplicate", duplicate.stderr)
        traversal = rejected_archive("traversal", ["../escape"])
        self.assertNotEqual(traversal.returncode, 0)
        self.assertIn("unsafe", traversal.stderr)
        collision = rejected_archive("collision", ["README.md", "readme.MD"])
        self.assertNotEqual(collision.returncode, 0)
        self.assertIn("collision", collision.stderr)

    def test_unsupported_mode_fails(self) -> None:
        self.write("linked", "README.md")
        command("git", "add", "linked", cwd=self.repo)
        target_sha = command("git", "hash-object", "linked", cwd=self.repo).stdout.strip()
        command("git", "update-index", "--cacheinfo", f"120000,{target_sha},linked", cwd=self.repo)
        command("git", "commit", "-qm", "synthetic symlink mode", cwd=self.repo)
        command("git", "config", "core.symlinks", "false", cwd=self.repo)
        command("git", "reset", "--hard", "HEAD", cwd=self.repo)
        revision = command("git", "rev-parse", "HEAD", cwd=self.repo).stdout.strip()
        result = self.run_builder(revision, self.temp / "mode")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported Git file mode", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
