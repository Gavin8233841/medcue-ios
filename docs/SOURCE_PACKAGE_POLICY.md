# Reproducible Source Package

Issue #5 owns the source-package boundary. The package is a contest/reviewer
source handoff, not an App Store archive and not a redistribution of the local
model binary.

## Build

Run from a clean checkout on the exact commit to be packaged:

```powershell
$Revision = (git rev-parse HEAD)
python tools/build-source-package.py `
  --revision $Revision `
  --output-dir (Join-Path $env:TEMP "medcue-source-package-$Revision")
```

The script refuses abbreviated or uppercase revisions, a detached revision that
is not `HEAD`, dirty/staged/untracked content, output directories inside the
repository, existing output files, and any input that is not read from Git
objects. It creates:

- `MedCue-source-<sha12>.zip`, with repository entries directly at the ZIP root;
- `MedCue-source-<sha12>.zip.sha256`, an external SHA-256 for the complete ZIP.

The ZIP contains `SOURCE_MANIFEST.json` and `SHA256SUMS`. The manifest records
the full commit SHA, tree SHA, policy version, exact file list, modes, sizes,
hashes, dependency inventory, and asset inventory. `SHA256SUMS` covers every
payload entry and the manifest, but intentionally excludes itself to avoid a
self-reference. ZIP timestamps and compression settings are fixed so two clean
builds from the same Git tree have the same bytes.

## Allowlist And Exclusions

The package includes the buildable Xcode, SwiftPM, Broker, tests, validation,
CI, checklists, templates, and approved reviewer documentation roots. Root
README/context and license/notice files are allowed explicitly. The builder
rejects wrapper directories, traversal and control characters, case collisions,
symlinks, submodules, unusual modes, unapproved paths, secrets, local paths,
models, databases, archives, audio/video, and unapproved media. Historical
`IMG_*.png` delivery evidence is excluded; PNGs under tracked Asset Catalogs
remain allowed as product icons.

The repository intentionally omits `llama.xcframework`. The package records its
upstream release and license status in the manifest and includes the source-only
notice, but does not claim to contain or verify the binary. A device build must
follow `tools/install-llama-xcframework.sh` separately.

## Inventory And Release Review

`SOURCE_MANIFEST.json` lists the first-party SwiftPM package, Node runtime
contract, optional llama.cpp framework, tracked icons, fonts, and media. Unknown
or unapproved dependency/asset states fail the builder. The package includes
`THIRD_PARTY_NOTICES.md` for the documented source-only external dependency.
Competition rules, intellectual-property, dependency-license, and attribution
review must be recorded against the exact commit in the Pull Request. Commercial
SBOM and binary-signature hardening remain outside this Issue.

## Verification

```powershell
python tools/test-source-package.py
python tools/build-source-package.py --help
python tools/verify-source-package.py <zip-path> <zip-sha256-path>
```

On macOS/CI, also run `unzip -t` against the produced ZIP, verify every line in
`SHA256SUMS`, run Broker tests and the relevant native gate, and record the
exact source and output SHA-256 values. The source package does not provide
physical-device, Apple-account, provider-retention, or real-model evidence.
The existing `tools/verify-native.sh` gate runs the synthetic matrix, builds the
exact current commit, executes the read-only verifier, and runs `unzip -t`; it
retains its temporary output path in the log for audit instead of recursively
deleting verification data.
