# Validation status — Issue #161

Date: 2026-10-09 UTC. Base: `4d9c6d50d46a5735dc014da5434e1063d8cf7493`.

## Candidate evidence before native CI

- Two existing product files changed; three independent test files added. No workflow, project-file, permission, medical rule, frozen path, or persistence-command change.
- `git diff --check` and repository Swift source-size check passed on the combined candidate.
- Independent static reviews closed identified source findings: stale scanner metadata filtering, real SwiftUI anchor coverage, wrapping long identity labels, same-process failure retry, honest log-association scope, strict iPad geometry assertions, and hosted-view fixture/AX checks.
- Static review does not establish Swift compilation, successful tests, visual quality, or hardware compatibility.
- This Linux authoring environment has no Swift/Xcode. The quick native preflight stopped at missing `plutil`; no native pass is claimed.

## New tests and execution requirements

| Suite | New methods | Intended execution | Current status |
| --- | --- | --- | --- |
| BarcodeScannerGeometryTests | 14 Swift Testing tests | Existing app-hosted unit-test lane | Authored and statically reviewed; not yet run |
| MedicationDetailAdaptiveLayoutTests | 3 XCTest tests, 8 host states | Existing app-hosted unit-test lane, ordinary iPhone destination | Authored and statically reviewed; not yet run |
| AdaptiveWindowStateUITests | 3 XCTest tests | iPad Simulator with measurable window rotation | Authored and statically reviewed; not yet run |

The current CI's iPhone UI destination will skip all three iPad-only tests. A green overall run cannot count those as coverage. Their acceptance requires 3 passed, 0 skipped on an appropriate iPad destination. No workflow changes are included.

The detail tests mount the real production view with synthetic in-memory SwiftData. A 1024-point hosted container is not a physical iPhone or Duo screen. AX labels/frames do not prove visible text is untruncated or buttons perform the intended action. Screenshots are attached to the test result for review, but the current workflow has no success-artifact upload; creation of attachments must not be reported as persistent external screenshot delivery.

Camera aspect-fill/format readiness and actual scanning require native camera evidence. iPad rotation does not establish folding, Split View, or Device Hub posture behavior. Duo SDK/runtime and physical-device evidence remain open.

## Frozen candidate content

These content hashes bind the completed static reviews, not successful native results. Later changes invalidate the corresponding prior evidence and require review again.

| File | SHA-256 |
| --- | --- |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/BarcodeScannerView.swift` | `af49f9a7b18349bebd0cffb6c258022c450f22a86ba99e6e21fc9c8c4f5bb030` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/MedicationDetailView.swift` | `8265cff9295f182de1a49f2bb80d8c7de11b69fb19d50cd89e6469bb366c9ae2` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/BarcodeScannerGeometryTests.swift` | `70bc00c5f6ba33bf094e61841bd5e8280b597e6694d52f0e781c366b30f0b842` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/MedicationDetailAdaptiveLayoutTests.swift` | `77b5993d9d70f09898d82aa9dc1e53ec599bcbd1caebaaef6a62e8569b9fedbb` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceAppUITests/AdaptiveWindowStateUITests.swift` | `114b4fe068a838395090932a68a563ca24cf4b4a5ae3b4067636564926beb9ed` |

## First native attempt and corrective candidate

Run [37875757005](https://github.com/Gavin8233841/medcue-ios/actions/runs/37875757005), attempt 1, failed in the main App Release build on 2026-10-09. `MedicationDetailView.detailPhotoActions` contained a local declaration followed by a view expression without an explicit return. No new native test suite executed; Broker tests passed 38/38. The failure is retained and is not reclassified as a successful validation.

The corrective candidate adds only `return` to that getter. Its source SHA-256 is `fff0e28dad70131c2d560108ac7d2bd15be4d1ef237e35f1d5e540b307d96ac5`; the earlier table binds the original candidate. All test contents and the scanner source are unchanged. A new commit and new CI result are required before claiming the compile error is resolved.

## Second native attempt and typed test constants

Run [37876262950](https://github.com/Gavin8233841/medcue-ios/actions/runs/37876262950), attempt 1, passed the native build suite and Swift Core 161/161, plus Broker 38/38. The iOS test targets then failed to compile two ambiguous `.infinity` expressions in `BarcodeScannerGeometryTests`; none of the 20 new tests executed. These were compile failures, not test skips.

The next candidate qualifies the two constants as `CGFloat.infinity` and the adjacent `.nan` as `CGFloat.nan`. Independent review confirmed exactly these three type qualifications, with all product code unchanged. New scanner-test SHA-256: `1b49285f0b77f346d3ba4652af10cf00620273b10c3ab82ba6db44750e885d15`. New-revision CI remains required; prior build results do not substitute for it.

## Third native attempt: product build and scanner proof; hosted AX gap

Run [37877340598](https://github.com/Gavin8233841/medcue-ios/actions/runs/37877340598), attempt 1, completed with overall failure at branch `539da969e24531ef1e1cd2b05515043eaa072707`; actual checkout was merge `851964685334967c3e8969e4c54ce0dd14b52753`, with the same tree `6f2e72d694b2486ddc82a6f908e0494d1977b06c`.

- All native build stages passed; Broker 38/38 and Swift Core 161/161 passed.
- All 14 new BarcodeScannerGeometryTests ran and passed. iOS Swift Testing total: 327/327.
- Hosted XCTest total: 7 executed, 4 passed and 3 new detail tests failed with `visibleAccessibilityDidNotStabilize`. Combined iOS unit count: 334 executed, 331 passed, 3 failed; the existing 317-test baseline passed.
- UI: 40 test entries, 37 baseline passes and 3 actual iPad-only skips on iPhone 17 Pro/iOS 26.5. This is not iPad coverage.
- No artifacts were uploaded. The AX-helper failure lacks enough observations to assign a product-layout root cause.

The follow-on candidate binds the synthetic test window to an existing foreground UIWindowScene and adds bounded AX/geometry diagnostics. It preserves the original three-second deadline, stable-array requirement, test assertions, fixture checks and screenshot names. New detail-test SHA-256: `3ef6800b9ad12809db196a835c07a34de6b4c100de4f203dddc12c9189ec523b`. It has only static review so far; it is not yet a proven fix.

## Additive iPad and image-evidence lane

Issue161 authorizes the new `adaptive-visual-evidence.yml` and `tools/iphone-duo-evidence/` slice. The existing full workflow/classifier is unchanged and still required. The additive lane only runs this public repository's same-branch PR162, on standard macos-26 with preinstalled Xcode26.6/iOS26 iPad, using read-only permissions and non-persistent checkout credentials.

The helper requires 3 real-detail tests plus 3 iPad window tests to execute and pass without skips; validates exact test identities and 24 explicit synthetic screenshots; rejects unknown schemas/paths/links/invalid PNGs; sanitizes into fresh staging; and retains at most20MB for one day. It does not publish raw result bundles, logs, device metadata, databases, or automatic screenshots. Test-source changes require a reviewed fingerprint update. Original test failures are retained, with only bounded reconstructed diagnostics.

Independent security review and 25 standard-library positive/negative tests passed in Linux. Actual macOS CLI/schema/ImageIO, iPad test execution, image generation and visual review remain pending. Any unknown format or failed test stops publication. This lane provides iPad rotation/native hosted-view evidence, not Duo posture or hardware certification.
