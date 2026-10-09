# Issue 161: narrow cloud-native visual evidence

This additive workflow is owned by Issue 161 / PR 162. It does not replace or
weaken existing full verification. It runs only that same-repository branch on
public `Gavin8233841/medcue-ios`, using the event's exact head SHA, a standard
`macos-26` runner and preinstalled Xcode 26.6 / iOS 26 iPad (A16) simulator. It installs
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
- Three separately validated result bundles run only the three
  `MedicationDetailAdaptiveLayoutTests`, three `AdaptiveWindowStateUITests`, and
  two `MedicationDetailAccessibilityUITests` allowlisted methods. Each must have
  its exact 3/3/2 passes, zero failures, zero skips and zero expected failures,
  with exact suite/bundle/test identities and no repetitions. A failing
  xcodebuild status stops later suites and remains the final nonzero exit
  status after any safe diagnostic export. Missing AX coverage cannot be
  replaced by successful hosted rendering.
- Hosted detail tests check mounted-list geometry, scroll traversal, trait
  transitions, render success and unchanged synthetic store state. They do not
  assert accessibility text/control semantics, column arrangement or RTL
  mirroring. Their 24 samples cover eight states times top/middle/bottom,
  not every pixel of the scrollable content. The `middle` suffix intentionally
  makes no claim that an information section is visible.
- The two actual-app tests query public out-of-process XCTest accessibility,
  assert selected fixture text and enabled/hittable controls across real iPad
  portrait/landscape/restored transitions, and compare the limited store fields
  exposed by the existing read-only fixture. They do not activate detail
  actions, prove every stored field unchanged, or add RTL/long-text semantic
  coverage. Six explicit top-only screenshots provide visual samples; traversal
  and controls are verified through assertions, not those top images.
- Only complete passing-suite image sets are staged: 24 hosted PNGs when
  later native execution fails, or all 30 exact named synthetic PNGs when
  every suite passes. Per-test exports are
  routed to the matching validated hosted or actual-app result bundle. The
  export tool can emit automatic attachments into private temporary scratch;
  automatic screenshots/diagnostics are ignored and never published. Unknown
  explicit MedicationDetail/MedicationDetailAX attachment names fail closed.
- Up to 20 bounded diagnostic lines are reconstructed from fixed failure
  categories, five allowlisted source filenames/line numbers, exact test IDs
  and numeric/Boolean harness counters. Raw log lines, arbitrary messages,
  labels, values, UUIDs, paths and device names are never echoed.
- Strict JSON duplicate-key/schema, name, path, regular-file, no-symlink,
  no-hardlink, count, uniqueness and size checks precede decoding. Hosted PNGs
  must match 320/1024 by 900 points at an integral 1x/2x/3x scale. Actual-app PNGs
  must match exactly 1640x2360 portrait or 2360x1640 landscape native pixels,
  bound by each attachment's orientation name. These are pixel dimensions,
  not an extra scale multiplier (A16 UIKit is @2). Neither class of image can
  satisfy the other's dimensions. CRC, chunks, bounded zlib payload, scanline
  count and filter bytes remain validated.
- Destination selection requires the exact installed simulator device type
  `com.apple.CoreSimulator.SimDeviceType.iPad-A16`; a user-visible device name
  is not trusted as model identity. Missing/unavailable A16 or iOS 26 stops;
  no alternative model, download or paid runner is selected. The screen contract
  is sourced from [Apple iPad (A16) specifications](https://support.apple.com/en-us/122240),
  checked 2026-10-09, which state 2360-by-1640 native pixels. Native execution
  must still establish that this preinstalled simulator type is present.
- A new core-chunks-only decode input removes ancillary metadata before ImageIO
  sees it. ImageIO decodes pixels and redraws into a fresh sRGB bitmap, then
  re-encodes to a new PNG. The output's ancillary chunks are stripped and its
  pixels validated again. No metadata is copied from the original source.
- Raw input screenshots and final staged evidence each have a 20,000,000-byte
  total ceiling. Only 24 or 30 fixed-name PNGs, a small README, and reconstructed
  `evidence-status.json` are uploaded, with
  one-day retention. No xcresult, log, database, manifest, device identifier,
  automatic screenshot or image-in-log fallback leaves the ephemeral runner.

## Partial diagnostics never replace native acceptance

The fixed execution order remains hosted detail, window-state UI, then actual-app
accessibility UI. Every exit-zero suite must immediately pass the exact existing
summary/tree identity checks (including zero skips) before its images are eligible.
Execution stops at the first native nonzero exit; later suites are `not_run`.
A failed suite is never exported. In this order only complete hosted evidence
(24 images) or complete combined evidence (30 images) can exist; no arbitrary
partial image inventory or AX-only fallback is accepted.

The machine-readable report contains only reconstructed repository/SHA, fixed
A16 simulator scope, validated iOS runtime, native exit code, per-suite
`passed`/`failed`/`not_run`, verified pass/skip counts (null for unverified suites),
PNG count and `required_all_passed`. A partial README starts with `PARTIAL` and
states that required acceptance failed. This report describes these three A16
suites only, never ordinary iPhone unit CI or the full-native gate.

A native failure may still provide previously validated synthetic images for
human visual diagnosis. Any schema, identity, export, pixel, size, staging or
public-repository guard failure aborts all publication. Image validation and
privacy controls are identical for partial and complete evidence. No artifact
is made when the first suite fails. A timeout/tool exception also aborts
publication rather than guessing a completed subset.

The helper initializes the Actions output `evidence_ready=false` and rejects
stale final staging before native execution. Child processes do not receive
Actions output/environment command-file handles. Only after exact final
inventory, total-size and live public-repository checks, and atomic rename into
fresh final staging, does the helper set `evidence_ready=true`. The upload step
requires this output and a non-cancelled job. It does not use `continue-on-error`;
a failed native step and the job remain failed even when diagnostic upload
succeeds. No output signal is inferred from filesystem existence or native exit
zero. The original native failure code is retained after a successful partial
export, and PR acceptance still requires every required suite and full gate.

## Native schema validation is intentionally conservative

Apple documents `xcresulttool help <command>` as the interface for command and
output format inspection in its
[Xcode 16.3 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes).
The runner reads actual command help and JSON schema before using the modern
`get test-results summary/tests` and per-test `export attachments` commands.
On schema rejection, a bounded diagnostic (under 64KB combined) reports only
SDK-provided static schema JSON obtained with the fixed `--schema` commands,
without any result-bundle path. Actual result metadata, manifests and logs are
never sent through this diagnostic. It does not accept or guess a new schema.
The static schema adapter recognizes only the exact observed Xcode 26.6
`schemas.Summary` and `schemas.Tests` contracts. Canonical JSON fingerprints
cover every type, field, required list, enum and local reference. It does not
resolve arbitrary references or search recursively for matching keys. Any added
external reference, alias cycle, escaped/dangling pointer or unknown type fails.
The known `TestNode.children.items -> #/schemas/TestNode` edge is structural
recursion, never expanded by the adapter; the separate real-result traversal
still enforces its existing depth limit and exact test identities.

Observed static SDK provenance (not xcresult payloads):
- [Actual visual run](https://github.com/Gavin8233841/medcue-ios/actions/runs/37881518599/job/113662042845),
  checkout `743598a1ac158e769eeb1337553b43049c910fe8`.
- Real run.py step began 2026-10-09 03:56:08.421533Z, after the unit-test step.
- Summary schema log at 03:56:11.505016Z, original extracted JSON SHA-256
  `0842cd791603c9184f8287a14db249a9f824f8fa7b3b7797dbfa8d801929e4b7`.
- Tests schema log at 03:56:11.509240Z, original extracted JSON SHA-256
  `845dd3ca1936c50dab17e1cf945d221ad48f162121d36b41070011f77f218f10`.
- Fixtures contain only that public SDK structure. The production adapter uses
  canonical sorted compact ASCII JSON digests (without a trailing newline),
  rather than assuming diagnostic serialization matches native stdout bytes.

The helper supports one explicit tree/manifest contract; unknown formats,
unexpected test nodes, unidentified explicit images, missing fields, renamed
fields or export naming changes stop without publishing. It does not infer a
schema from arbitrary recursive keys or fall back to a legacy parser.

Linux tests use synthetic result metadata/PNGs plus the sourced static SDK
schema fixtures above. They do **not** prove actual native result/attachment
formats or ImageIO execution. A macOS run must still establish those facts. If it stops on the format boundary, inspect the native help/schema and
make a separately reviewed adapter update; do not broaden the parser to make
an artifact appear. The uploaded README records the exact source/toolchain,
iOS runtime and verified test counts, never a device ID.

These images, when produced by a successful native run, show synthetic native
render samples only. The separately passing actual-app tests provide the
bounded accessibility assertions described above; images alone do not. They require human visual
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
