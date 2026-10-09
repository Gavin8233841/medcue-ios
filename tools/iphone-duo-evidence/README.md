# Issue 161: narrow cloud-native visual evidence

This additive workflow is owned by Issue 161 / PR 162. It does not replace or
weaken existing full verification. It runs only that same-repository branch on
public `Gavin8233841/medcue-ios`, using the event's exact head SHA, a standard
`macos-26` runner and preinstalled Xcode 26.6 / iOS 26 iPad simulator. It installs
nothing and requests no secret, OIDC or write permission. The helper checks live
public visibility before tests and again before artifact staging.

Public-repository standard hosted runners are free under the current official
[billing scope](https://docs.github.com/en/actions/concepts/billing-and-usage)
and [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
Private repository storage quotas are not asserted for this public workflow.
A private repository, missing preinstalled tools/runtime, unexpected paid/upgrade
requirement or expanded access is a stop condition, never a fallback request.
Native invocations preserve the existing verification script's fresh source-package
directory, disabled automatic package resolution/updates, simulator test-host
build setting and `MEDCUE_DISABLE_LOCAL_LLAMA=1` boundary.
There is a 40-minute job limit and 15-minute limit per native test invocation.

## Evidence contract

- Exact reviewed test-source SHA-256 fingerprints are checked before execution.
  A source change requires re-review and an explicit fingerprint update.
- Only the three `MedicationDetailAdaptiveLayoutTests` methods and three
  `AdaptiveWindowStateUITests` methods run. Each result bundle must have exactly
  3 passes, 0 failures and 0 skips, with exact suite/bundle/test identities and
  no repetitions. A failing xcodebuild status returns immediately unchanged.
  Up to 20 bounded diagnostic lines are reconstructed from fixed failure
  categories, four allowlisted source filenames/line numbers, exact test IDs
  and numeric/Boolean harness counters. Raw log lines, arbitrary messages,
  labels, values, UUIDs, paths and device names are never echoed.
- Only the 24 explicitly named real-detail synthetic screenshots are staged:
  eight states times top/information/bottom. UI-test attachments are not exported.
  The native export tool can emit automatic attachments for the selected hosted
  test into private temporary scratch; these are ignored and never published.
- Strict JSON duplicate-key/schema, name, path, regular-file, no-symlink,
  no-hardlink, count, uniqueness and size checks precede decoding. PNG dimensions
  must match 320/1024 by 900 points at an integral 1x/2x/3x scale. CRC, chunks,
  bounded zlib payload, scanline count and filter bytes are validated.
- A new core-chunks-only decode input removes ancillary metadata before ImageIO
  sees it. ImageIO decodes pixels and redraws into a fresh sRGB bitmap, then
  re-encodes to a new PNG. The output's ancillary chunks are stripped and its
  pixels validated again. No metadata is copied from the original source.
- Raw input screenshots and final staged evidence each have a 20,000,000-byte
  total ceiling. Only 24 fixed-name PNGs and a small README are uploaded, with
  one-day retention. No xcresult, log, database, manifest, device identifier,
  automatic screenshot or image-in-log fallback leaves the ephemeral runner.

## Native schema validation is intentionally conservative

Apple documents `xcresulttool help <command>` as the interface for command and
output format inspection in its
[Xcode 16.3 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes).
The runner reads actual command help and JSON schema before using the modern
`get test-results summary/tests` and per-test `export attachments` commands.
The helper supports one explicit tree/manifest contract; unknown formats,
unexpected test nodes, unidentified explicit images, missing fields, renamed
fields or export naming changes stop without publishing. It does not infer a
schema from arbitrary recursive keys or fall back to a legacy parser.

Linux tests use synthetic metadata/PNGs. They do **not** prove the installed
Xcode's schema or ImageIO execution. The first macOS run must establish those
facts. If it stops on the format boundary, inspect the native help/schema and
make a separately reviewed adapter update; do not broaden the parser to make
an artifact appear. The uploaded README records the exact source/toolchain,
iOS runtime and verified test counts, never a device ID.

These images prove native synthetic rendering only. They require human visual
review and are not evidence of Duo hardware, open/close posture, arbitrary
window resizing or medical outcomes. SDK availability is not runtime evidence.

## Dependencies and licenses

No new package or tool is installed. Python standard library, Apple ImageIO /
CoreGraphics and the already installed Xcode toolchain are used. Both pinned
GitHub actions were read at their exact official repository revisions, including
their MIT licenses (2026-10-09):

- [actions/checkout fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09](https://github.com/actions/checkout/blob/fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09/LICENSE)
- [actions/upload-artifact ea165f8d65b6e75b540449e92b4886f43607fa02](https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/LICENSE)

Their implementation is consumed as a pinned action, not copied into this
repository. Preserve each action's upstream license with any redistribution.

## Local checks

`python3 -m unittest discover -s tools/iphone-duo-evidence -p 'test_*.py' -v`

The fixture tests include complete selection, automatic-image exclusion,
traversal, symlinks/hardlinks, malformed and animated PNGs, bounded pixel decode,
metadata removal before native decoding, duplicate/missing images, incorrect
test identity, skips/failures/repetitions and unknown schemas. Native validation
and the unchanged full native gate remain required before completion.
