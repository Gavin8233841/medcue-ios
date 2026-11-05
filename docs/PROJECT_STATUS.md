# MedCue Project Status

Last full audit: 2026-08-23
Targeted governance/ownership check: 2026-09-07 (local working tree only)
Authoritative branch: `main`
Authoritative `main` observed at: `d6aa4af85f225028fc3f912391328e1f745d0b34`
Post-migration audit baseline: `280e5b3f8425f155d5e20a71841f4169a63bc59d`
Audit-baseline CI: [Native Verification run 32171788727](https://github.com/Gavin8233841/medcue-ios/actions/runs/32171788727)
Latest full coordination audit: 2026-09-22; targeted update: 2026-09-27 (#28)
Verified source checkpoint for the #4 update below: `main@74fb171088a80c38872c51fcae85c05721dc10f0`

## 2026-11-05 Existing-demo artwork upgrade correction

The earlier `43de6b7` checkpoint replaced bundled photos but existing device
records still supplied their saved `photoData`; normal startup did not invoke
the explicit Demo rebuild. This explains the old packaging and missing D3.
Startup now performs a one-time, versioned refresh of existing demo artwork:
ibuprofen, paracetamol and vitamin D receive the current bundled image; missing
known demo images are filled. No tasks, plans or non-demo photos are rebuilt.
The version is recorded after a successful save, and unrelated pending edits
prevent the refresh. The new regression covers old images, absent D3, retained
non-demo/saved loratadine photos, retained task IDs/status, and repeat execution.
All 348 hosted app tests passed on these changes. Device installation and
visual acceptance are separate from this source/test checkpoint.


## 2026-11-05 Current competition integration candidate (#166 / #167)

Current candidate: `codex/finals-baseline-integration`, reconciling the preserved
competition workline with authoritative `main@4d9c6d50d46a5735dc014da5434e1063d8cf7493`.
The historical snapshots below retain their original revision scope.

- All merge markers resolved. Main's explicit model cancellation/resource
  ownership, consent-filtered environment context, dose transactions, recovery
  retry and reminder-read failure handling are retained alongside the current
  MiniCPM 2B prompts/history, Markdown, Foundation Models custom provider,
  demo gallery/reset, Today and elder presentation.
- Today settled surfaces no longer use the system gradient that produced a grey
  lower half. The runtime toggle uses a native interactive Glass capsule; concise
  “本机模型 / 云端模型” rows replace repeated Beta/privacy descriptions. A generic
  SF Symbols `sparkles` icon identifies local generation, without implying use
  of Apple's system model. Existing authorization and download actions remain.
- Owner-supplied Chinese ibuprofen/paracetamol photos replace the foreign
  packaging. The latest Doublewhale D3 resource matches the supplied image.
  An explicit Demo restart refreshes these packaging images and eye drops;
  other locally selected demo photos and non-demo records retain their existing
  preservation behavior. Packaging images are not instruction/dose evidence.
- Source-package policy permits only five exact demo-photo paths and byte
  hashes, referenced by their catalogs; arbitrary media remains rejected.
  Ten package regression tests, 165 Swift core tests, 347 hosted app tests,
  38 broker tests and the Simulator app build passed on the integrated contents.
- Full UI/device and current-revision hosted CI/review are pending at this
  source checkpoint. The local full gate currently stops at its clean-checkout
  requirement because pre-existing untracked local skills/workspace files are
  preserved. This does not claim a full local gate or a main merge.


## 2026-09-27 Local-model journey attempt (#28)

At `main@ed67bf82cb582f482b87454ffa9012d239764b99`, a dedicated iPhone 17 Pro / iOS 26.5 Simulator installation with a locally supplied real llama runtime reached the in-app 265.3 MB download and displayed progress. The download failed below 1 MB and the app offered retry. An independent range request to the pinned upstream source received only 69 KB in about 41 seconds before timing out. The functional journey therefore has **not** reached installation, relaunch persistence, explicit local selection, or an offline guarded response. The runtime's official archive digest also remains unverified. The product owner authorized Simulator substitution for the functional Issue journey; no physical-device result is claimed. The exact steps, redacted result matrix, and remaining decision are in [the #28 runbook](ISSUE28_LOCAL_MODEL_ACCEPTANCE.md) and [Issue checkpoint](https://github.com/Gavin8233841/medcue-ios/issues/28#issuecomment-5853320437).

## 2026-09-27 Competition/Beta capability scope (#4)

The product owner chose to hide unverified Apple sign-in, automatic iCloud
backup, and WeatherKit entry points for the current competition/Beta build.
The account page now explains that medication data remains on this iPhone and
must not be assumed backed up or recoverable. Existing local account/backup
preferences remain stored but no longer imply success in the interface.
Today and the AI assistant no longer instantiate the weather service or request
location. The dormant weather adapter and location purpose string remain in
source; re-enabling them requires entitlement, privacy, account, and runtime
evidence. This is a source-scope update, not backup, restore, or device proof.

## 2026-09-26 GitHub Topics completion (#33)

The public repository description remains Chinese-first with an English
explanation. Its Topics were set to `ios`, `watchos`, `swiftui`, `swiftdata`,
`medication-management`, and `medication-reminders`, then read back through the
GitHub API. These describe verified platforms, implementation, and medication
organization features; they do not claim diagnosis, prescribing, or release
readiness. PR #53 already delivered the bilingual README, templates, labels,
and Issue migration. The earlier #33 Topics blocker below is historical.

## 2026-09-22 Current Coordination Snapshot

- GitHub visibility was read back as **PUBLIC**. The private-visibility statement
  in the historical 2026-08-23 snapshot below is not current.
- [PR #84](https://github.com/Gavin8233841/medcue-ios/pull/84) merged the Broker
  input/HTTP failure boundary into `baeabcade7b040301f7b8ac13e9a3a89bb1008e7`; #80 closed.
  PR HEAD `45edd7a` passed 31/31 strict Node tests, independent security review,
  and its exact-head Broker CI. Post-merge full CI is tracked separately in
  [run 35692029084](https://github.com/Gavin8233841/medcue-ios/actions/runs/35692029084).
  That post-merge run succeeded; this does not claim CloudBase deployment.
- 34 Issues remain open, all assigned to a milestone. Of these, 13 carry the
  technical-debt label and 7 the defect label. These are tracker categories,
  not an estimate of 34 independent defects or a completion percentage.
- 10 implementation PRs remain open (excluding this status-document update).
  Superseded #63 and #79 were closed without deleting their
  branches; #90 is the single delivery candidate for #61.
- Exact-head required CI succeeded for #78 (`6e7633e`), #87 (`5d3f154`),
  #88 (`8a9ca69`) and #90 (`004e44e`). These PRs remain unmerged. #86
  (`c9ad98e`) failed its required result after UI-job timeout; child #87's
  successful run does not satisfy its parent's integration gate.
- #17 remains open: merged evidence documentation is not physical-device
  acceptance. At this 2026-09-22 snapshot, #33 still awaited a Topics decision;
  the 2026-09-26 update above resolves it. #20's local
  work does not establish merged migration acceptance.
- #83 now has [PR #92](https://github.com/Gavin8233841/medcue-ios/pull/92)
  at `cf761441589964dcd8d93d281fe61833f3fb5944`: strict Node tests 38/38,
  fresh-context security review with no Blocker/Required findings, and
  [exact-head Broker CI](https://github.com/Gavin8233841/medcue-ios/actions/runs/35692799471)
  passed. It merged into the current source checkpoint and #83 closed.
  [Post-merge full CI](https://github.com/Gavin8233841/medcue-ios/actions/runs/35693333809)
  succeeded on the exact merged source checkpoint, including all native builds
  and Swift Core, hosted iOS and UI test lanes.
  No provider deployment is claimed.
- #81's final `8a9ca69` cumulative fresh-context data-safety review completed
  with no Blocker/Required findings. Its remote full CI is green, but no local
  full-gate completion log bound to this final HEAD was found. Reminder shared
  files have one writer: hand off this stable checkpoint to #89, then #82.
  Broker #83 is a separate line.
  Existing contributor ownership of #47/#61/#62/#16 is preserved.

This snapshot is a source/integration status, not release, device, VoiceOver,
telephone, notification-delivery, or representative-user acceptance. Current
GitHub Issue and PR state supersedes these timestamped counts.

## 2026-09-17 Local Candidate: Issue #85 Complete-Mode Dynamic Type

- Branch: `codex/85-complete-dynamic-type`; base:
  `c9ad98ebe60c91b2e7ede5f7dc4e53589b9e3a8b` (PR #86).
  This is a serial UI child of the #46 / #55 workline, not integrated main.
- Accessibility text sizes now use a vertical timeline header/action layout,
  single-column medication metrics, expanded runtime selector descriptions,
  naturally sized records previews and seven readable calendar rows. Local-data
  and profile-entry descriptions wrap; decorative icons retain bounded sizes.
  Default text retains the compact page structure.
- Inline confirmation buttons now include their whole background in the
  tappable label, with minimum height 44 pt (60 pt at accessibility sizes).
  Cancel/confirm callbacks and medication commit/delay semantics are unchanged;
  no consent, download, persistence, reminder or AI-request command changed.
- The synthetic iPhone 17 Pro twice stalled while scrolling an expanded AX5
  confirmation (runs 07 and 08, including an isolated retry). A process sample
  showed main-thread SwiftUI lazy-layout updates. Resolving the finite outer
  Today sections with VStack removed that reproduced stall: the same journey
  passed in run 09, then the final SE journey also passed. This is simulator
  regression evidence, not a physical-device performance measurement.
- Final layout inputs: `.codex-local/issue85/final-layout-inputs.json`.
  SE run 10 passed UI 5/5 (default and AX5 five-tab tours, content/navigation
  journey, touch-preference persistence, elder entry). iPhone 17 Pro run 09
  passed the AX5 journey 1/1; run 11 passed tours/settings 3/3. Tests check
  medication text geometry, metric width, seven distinct date rows, actual
  navigation/back, confirmation cancellation with zero medication writes,
  and the full settings-entry description.
- Earlier same-workline evidence is separately scoped: run 05 passed SE AX5
  profile/settings 1/1; run 06 passed ElderModeTests 17/17 and UI 6/6.
  These precede only the final outer Today stack adjustment. They are not a
  second final-revision full-suite claim. Failed/interrupted runs are retained.
- Twenty final five-tab screenshots cover two screen sizes and two text sizes;
  focused action screenshots and the earlier failure evidence are retained.
  Preflight, Swift source-size and diff-whitespace checks pass. The expected
  missing Debug AI configuration warning applies to this explicitly marked
  synthetic simulator test host. Existing staged-hook checks apply; the PR #77
  reusable scripts are absent on this branch.
- No new full `verify-native.sh` result, exact-head remote CI, physical
  VoiceOver, notification/phone delivery, or release is claimed. PR #86's
  run 35102932986 completed 29 UI tests without assertion failures but the
  job exceeded its 25-minute budget; its required gate remains failed.
  Keep this stacked child Draft until parent and integration gates are met.
  Issue #52 retains broader detail-page/long-content visual coverage and
  cross-page data/end-to-end acceptance. The assistant's horizontally scrolling
  quick-question chips still warrant an AX layout follow-up; this candidate
  fixes the runtime selector and does not declare every assistant control
  visually complete.

## 2026-09-16 Local Candidate: Issue #55 Elder Interaction

- Branch: `codex/55-elder-no-scroll`; base:
  `ebf0a0c364a9bdeb263a76ddedd291013f2cd9c0`. This is a serial UI follow-up
  to Issue #46 / PR #78. The unchanged base was published as
  `codex/46-notification-postpone-fix` for a focused stacked Draft PR;
  publishing that reference is not integration or release.
- Three elder actions and confirmation controls now occupy a fixed bottom safe
  area. Medication identity remains independently scrollable, photos open in a
  stable detail sheet, and a task change restores the next identity to the top.
  Success feedback follows the current identity. Text scales continuously and
  secondary text has stronger contrast. Medication commit, delay, consent and
  phone-opening semantics are unchanged.
- Help settings no longer open the keyboard immediately. While editing, the
  save control stays above it; successful persistence dismisses the keyboard.
  Editing clears stale success feedback, and an unsaved draft does not expose
  a remove-saved-contact action.
- Synthetic SE (375x667 pt), Xcode 27 / iOS 26.5:
  `regression-07` passed ElderModeTests 17/17 and UI 28/29. Its single
  failure was the unfiltered accessibility audit's contrast check. The final
  delta changes only three secondary foreground colors; `focused-09` then
  passed 3/3 (unfiltered system audit, maximum text, and dark appearance).
  Earlier failures are retained, not reclassified as passing.
- A separate synthetic iPhone 17 Pro run, `normal-08`, passed 3/3 for
  default-mode entry, AX5 confirmation/photo controls, and AX5 next-task
  identity after scrolling. This shares the regression-07 geometry; it predates
  only the three final foreground-color changes.
- Logs, xcresults and SHA-256 input manifests are retained under
  `.codex-local/elder-ux/`; the final code/test inputs are
  `focused-09-inputs.json`. Preflight and Swift source-size checks pass;
  preflight reports the expected absence of Debug-only AI configuration on
  this explicitly marked synthetic test host. Existing staged-hook checks
  apply; the unmerged PR #77 reusable checker is absent at this revision.
- This is focused local evidence, not a new full `verify-native.sh` gate,
  exact-head remote CI, physical VoiceOver, real notification/phone delivery,
  or competition acceptance. The earlier #46 full gate does not validate this
  changed UI. At that candidate date the child PR remained Draft; current integration and
  release evidence belongs in the linked Issue and PR.
- The complete-mode AX5 five-tab tour passed reachability checks but exposed
  visible truncation/overlap in manual screenshot review. Those unfixed
  production layouts are tracked in Issue #85, linked to the visual-baseline
  Issue #52; this elder candidate does not declare those pages visually valid.


## Historical Audit Baseline (2026-08-23)

Last audited for the historical baseline below: 2026-08-23
Authoritative branch: `main`
Audit baseline: `d6aa4af85f225028fc3f912391328e1f745d0b34`
Audit-baseline CI: [Native Verification run 32640833807](https://github.com/Gavin8233841/medcue-ios/actions/runs/32640833807)

This is the single current engineering-status document. GitHub Issues hold the
active backlog, Pull Requests hold implementation and review evidence, and
accepted ADRs hold durable decisions. Historical notes and local files do not
override the exact repository revision or GitHub evidence. The SHA above is the
exact baseline used for this post-migration audit, not a prediction of a later
merge commit. The authoritative working revision is the commit currently
resolved by `main`; every evidence claim below remains scoped to its named SHA.
Unless explicitly dated otherwise, repository, ruleset, and Issue-label snapshots
below belong to that audit. Read back live GitHub state before relying on them
for a new operation; the targeted update is not a full source or release audit.

## 2026-11-05 Chat material and waiting presentation

Owner-approved follow-up to Issue #167. The composer now uses neutral regular
Liquid Glass with a light primary tint, matching the native tab-bar and message
surface family, plus regular-material fallback. The image accessory uses a
system fill instead of its near-opaque white background.

Read the owner-authorized local CatPaw `MessageViews/FeedbackViews.swift` and
`ChatMessageList.swift`. Independently adapted its text-highlight/three-dot
presentation pattern with native SwiftUI phase animations. The compact local
and cloud waiting views share this presentation and retain their actual status
text and local elapsed time. System/app Reduced Motion renders a static version.
No repeating Timer or additional UI dependency was introduced. Model generation,
response validation and consent paths are unchanged.

The existing memory-only chat fixture has an explicit waiting preview with a
short synthetic transcript. Shallow/light and dark waiting screenshots, keyboard
avoidance, history hiding/restoration and draft preservation passed. Full Route A
verification passed with 156 core tests, 202 hosted unit tests, seven UI tests,
app Release and both Watch builds. The signed device build was installed in
place and normal launch succeeded. These tests made no cloud/model requests;
the screenshots are synthetic Simulator UI evidence. Source self-review and
independent review remain scoped separately from the unresolved main integration
under Issue #166. Evidence is in the ignored `round2/chat-material-*` files.

## 2026-11-05 Today settled state and elder hold controls

Issue #167 is a bounded presentation update on the preserved competition
workline. Today now uses a modular settled card when no open task remains,
distinguishes all-taken completion from ignored/no-plan states, and exposes
expandable, correctable records. An absent next reminder is hidden. Weather
concerns are reached from Profile and load only when opened. System typography,
native Glass controls, and a one-shot circle/check confirmation animation are
used. Reduced Motion keeps the settled illustration static.

The four-character elder capsule opens a mode confirmation. Both the elder exit
and Settings mode picker also require confirmation. Elder completion and delay
controls require a cancellable 1.2-second hold with fill progress. The elder
screen has no skip control, and help opens on a normal tap. Idle hold captions
are hidden; pressing shows the cancellation hint. Native light impact feedback
marks press start and recognition, without implying that a record was saved.
Completion opens a confirmation before invoking the existing dose command;
existing early-dose confirmation remains applicable. Accessible activation uses
an explicit confirmation alternative. Existing commit-before-feedback/system
sync behavior is unchanged. Notification settings use one contextual entry and
refresh status on entry and foreground return, preserving the permission primer.

Simulator build, native quick checks, 156 core tests, 202 hosted iOS unit tests,
and two focused UI regressions passed. Those UI tests use the existing isolated
in-memory gallery fixture, covering all-ignored settled state, record disclosure,
mode-confirmation cancellation, short/released holds, completed hold confirmation
and help opening on a single tap. The fixture resets its presentation mode at startup
so a launch-argument override cannot freeze mode switching. These are synthetic
Simulator observations, not physical-dose acceptance. The first full gate
reached the UI suite with one failure because the native chat controls inherited
the scroll container identifier. Its fixture test now finds the actual text field
and app send button, retaining the same keyboard, scroll and draft-preservation
assertions. The rerun passed all six UI tests and the full Route A gate,
including unsigned app Release and both Watch builds. All 28 broker tests passed.
The final D3 replacement and read-only elder fallback were added after the UI
test build and are covered by the subsequent app Release and signed physical
device builds. The competition-phone build was installed
in place and launched normally; Device Hub visibly showed the new elder controls.
Physical haptic feel remains owner acceptance.

The 2026-11-05 owner-supplied Doublewhale D3 photo replaces the bundled artwork.
New/reset demo data use this photo. Existing photos remain preferred; an existing
demo D3 with no stored image can display the asset on the elder page without a
database write. No medication strength, dose or instruction fact is inferred
from this presentation asset. Local evidence is under
`.codex-local/local-ai-repair-20261028/round2/today-*`.

Main integration is still blocked under Issue #166. Read-only merge-tree confirms
22 conflicted paths against main 4d9c6d5. Fresh-context comparison also identified
main-only runtime cancellation/resource ownership, authorized-context filtering,
response-boundary, startup recovery and reminder-read-failure changes that must
be reconciled with the latest competition features. Choosing one whole side
would lose accepted behavior. This UI checkpoint does not establish main merge
readiness or waive the full gate and current-revision independent review.

## 2026-11-03 Booth demo recovery and photo-first medication gallery

The owner selected C (real-package cards), then narrowed Duo to a simple
sidebar/gallery layout and one image-bearing Keynote cover capture. Medication
content now appears directly without the repeated overview/group disclosure:
compact windows use a photo grid; regular width uses a compact summary/status
sidebar and two-column gallery. Existing native navigation, segmented controls,
Glass button adapter and background thumbnail decoder are reused. No new UI
framework, schema, reminder semantics or AI changes were introduced.

Demo recovery now rebuilds only demo content with a single final save, retaining
non-demo records, model files and authorization. Existing demo photos are carried
across by stable medication UUID, with bundled fallback images for fresh data;
the owner's newly supplied eye-drop photo replaces the artificial-tear image.
Media attribution is recorded in DEMO_MEDIA_CREDITS.md. Recovery stays inside the
process and refreshes the intro identity and tab content after successful save;
failures roll back. Fixed completion-overlay waits were removed and onboarding
copy was shortened for actual import, records, health context and local/cloud AI.

Five focused model-container/demo tests passed, including repeated same-ID
recovery, retained user medication and retained custom photo bytes. Native quick
checks and Simulator/device builds passed. Independent fresh-context review
Required findings were resolved. Two actual demo-button recoveries on the existing
test phone Simulator returned to a new intro without process exit; skipping
showed Today directly. The gallery then exposed four real-photo items, including
the new eye-drop photo. Competition-phone in-place install and normal launch
were checked; its data were not reset. Physical-device manual gallery acceptance,
Duo hardware behavior, OCR reliability and AI-answer quality are not established
by this UI work. Final Duo capture uses Simulator synthetic demo data, not a
physical-device claim; no continued large-font or multi-device acceptance lane.

A DEBUG Simulator-only `--medication-gallery-preview` uses an in-memory demo
container and initially selects the gallery for the cover. It bypasses startup
reminder reconciliation, Live Activity consumption, Watch publishing, URL actions
and stored elder-mode selection. It is ignored on physical devices and Release.
Cover arguments also include `--seed-demo-data`. This is an explicitly synthetic
Simulator presentation, not evidence of medication actions or device health data.

Evidence: `.codex-local/local-ai-repair-20261028/round2/booth-*`; cover image:
`.codex-local/local-ai-repair-20261028/round2/Keynote-Duo-medication-gallery-Simulator.png`.

## 2026-11-02 Minimal elder presentation integration

Restored the existing `appExperienceMode` setting and root navigation switch on
the latest development workline. Settings → 使用模式 selects 完整模式/适老模式;
the elder page presents one pending task, larger medication photo/name/dose and
high-contrast completion/delay/help controls. Photo downsampling and button
presentation reuse Issue #46 (`codex/46-elder-mode-m1`). Switching returns to
Today. Both modes use the same TodayView snapshot, confirmation, persistence,
feedback and system-surface action paths; no old reminder implementation,
authorization logic, database migration or additional task store was imported.

This is a bounded presentation restoration, not the whole historical elder M1:
help opens existing usage guidance; post-completion corrections use complete
mode. Existing undo banners remain available only when produced by their current
action path. Action controls are disabled during existing feedback; notification
presentation reuses the complete page's capture-only filter.

Simulator build, native quick checks and 16 focused persistence/projection tests
passed. Fresh-context independent review Required findings were resolved.
An existing non-recording test simulator/library was reused: Settings switched to
elder; one completion advanced to the next task; delay confirmation shifted
13:00 to 13:30; switching back to complete Today showed the same delayed task and
one completed item. Original recording target/library was not operated. Evidence
and retained Simulator package receipt are in
`.codex-local/local-ai-repair-20261028/round2/elder-current/` and sibling
`elder-integration-*`/`elder-ui-*` files. No physical-device acceptance, four-device
synchronization, remote CI or main merge is claimed by this local check.

## 2026-11-01 Bounded startup responsiveness repair

The owner observed two white-screen/unresponsive launches on the competition
phone, recovering after removing the app from the app switcher. Source review
identified the full nine-table persistence-integrity audit running synchronously
on MainActor at startup. Local-model weights are not loaded on ordinary startup;
model availability only checks file metadata. No matching MedCue crash report was
available on the connected phone; the available October 31 jetsam report did not
include MedCue. These observations do not establish the white-screen root cause.

Startup now reserves its single integrity-audit run on MainActor, then performs
the same read-only audit on a utility worker with a separately created context
and autosave disabled. Only the Sendable report crosses back for count-only
logging. Main-context models, medication writes, reminder scheduling and AI
behavior are unchanged. Independent fresh-context review found no Required or
Blocker issues. Six focused tests passed, including committed-record readback,
no mutation and once-only execution; simulator/device builds and native quick
checks passed. The first test compile required a missing test-module import,
which was corrected before the successful run.

The build was installed in place on the competition phone; normal launch was
accepted and its process remained running at the follow-up check. This is not a
measured first-frame improvement or manual acceptance that the intermittent
white screen is eliminated. No reset, sample insertion, model transfer or AI
network request was performed. Existing test simulator/build caches were reused.
Evidence: `.codex-local/local-ai-repair-20261028/round2/startup-audit-*`.

## 2026-11-01 HealthKit simulator authorization unblock

The recording build log explicitly disabled signing (`CODE_SIGNING_ALLOWED=NO`).
Source HealthKit entitlement, project entitlement path and read-purpose string
were already configured; none was added and no device signing account changed.
A simulator Debug build with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`
succeeded using the existing local-model DerivedData namespace. Its executable
contains `com.apple.developer.healthkit=true` in the simulator Mach-O
`__TEXT,__entitlements` section, and deep signature validation passed. The empty
`codesign -d --entitlements` signature slot alone is not evidence of missing
simulator entitlements.

The permission primer additionally now captures the displayed authorization gate
before SwiftUI's alert presentation Binding is cleared. Cancellation still does
not request or record authorization; only the user's continue action invokes the
existing system request. The scope of HealthKit reads and completion semantics
are unchanged. Fresh-context independent review found no Required/Blocker issues;
simulator build and native quick checks passed.

On the explicitly handed-off ordinary recording simulator, updated in place
without reset, reseed or sample edits: cancellation retained the not-authorized
state, and accepting subsequently displayed the real system Health access panel.
RocketSim's accessibility tree continued exposing the underlying MedCue screen,
so automated system-switch interactions were not verified. Follow-up identified
that this was the older chat simulator, not the sample-bearing recording target.
Its later completed authorization and zero-sample refresh do not establish a
failure on the sample-bearing target.

The existing target referenced by
`.codex-local/yzy-rerecord-20261027/standard-elder-current-20261030/main-target-private.json`
was then booted and updated in place with the retained `1de1c5f` package. Read-only
verification found exactly the existing synthetic heart rates 72/76/70 on
October 30/31 and November 1, all inside the 56-day query window. This target's
MedCue screen still states that its authorization request has not completed.
No additional authorization request was made per the handoff constraint; sample
readback remains blocked by the target/authorization mismatch. No samples or
medication records were changed, no simulator was reset, and Duo was not operated.
The sample-bearing target is left on MedCue's Apple Health page.

The retained simulator package, binary hashes, authorization-panel screenshot and
scope receipt are under
`.codex-local/local-ai-repair-20261028/round2/healthkit-primer-fixed/`.
This fixes the local recording build/primer path, not physical-device HealthKit
acceptance or a main merge. Reproduce the simulator build with the existing
project/scheme, Debug, generic iOS Simulator, arm64, the retained DerivedData,
`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`; never use the unsigned recording
command for permission acceptance.

## 2026-10-31 Prompt/history echo follow-up

The owner reported an evening greeting replaying old dialogue and prompt text.
The previous five-case smoke did not cover this polluted-history condition.
Local prompts previously placed the current question before history, facts and
instructions; the runtime's head/tail truncation could also discard that middle
question for long inputs. This is an identified structural weakness, not proof
of the exact token truncation in the screenshot.

The minimal fix sends standalone greetings without old assistant prose or
personal-record context. Other questions retain recent history as delimited
background and place the current user question last. There is no fixed answer,
post-generation echo deletion or new content blacklist. Two focused regressions
cover a greeting after stale welcome text and a follow-up retaining its history.
Synthetic device cases 52/53 cover the same greeting and an English discomfort
question after repeated welcome/disclaimer history; they do not read user data.

The policy/parser harness passed 33 tests, signed iPhone Debug build and native
quick checks passed, and independent fresh-context source review found no
Blocker/Required findings. The new package installed successfully. Device
inference launch was rejected because the phone was locked; the two-case runtime
acceptance is pending unlock and is not claimed complete. Evidence is under
`.codex-local/local-ai-repair-20261028/round2/prompt-echo-*`.

## 2026-10-31 Owner-selected development checkpoint and workspace audit

The owner designated this workline as the latest local App development checkpoint:
`codex/finals-baseline-integration@dca427d881c606c286f16897b562822bc24ceeb9`.
Use the canonical checkout described in `TOOLING_AND_PLUGIN_PLAN.md`; recording
and further development should resolve this branch explicitly instead of guessing
from App version 1.0(1) or another historical worktree. This designation does not
replace authoritative `main` or imply that the two branches are integrated.
Local `main@4d9c6d50` and this checkpoint diverge by 49 main-only / 8 workline-only
commits; merge/review/CI gates still apply before shared integration.

The read-only audit found 37 registered worktrees, 12 with uncommitted or
untracked content. The canonical directory uses about 73.65 GiB including its
nested worktrees; it must not be added again to those nested sizes. Much of the
space is historical build output, test evidence and recording materials, rather
than source. No worktree is declared disposable solely because its tracked
content is clean. Unique and detached history, ignored artifacts, and ongoing
recording use must be preserved before retirement.

The detailed local inventory and first proposed cache-only removal plan are at
`.codex-local/local-ai-repair-20261028/round2/WORKTREE_CLEANUP_REVIEW.md`.
After explicit owner approval of the path-scoped list, all 38 cache directories
were revalidated against the approved plan, checked for open-file use, removed,
and verified absent. They held about 3.77 GiB of allocated storage; observed free
space increased about 3.66 GiB during removal (not an APFS reclamation guarantee).
The active model build cache, source, models, recordings, logs and result bundles
were preserved. No worktree or branch was removed. The local receipt is
`.codex-local/local-ai-repair-20261028/round2/cache-cleanup-receipt-20261031.json`.

The source checkpoint rebuilt successfully as signed iPhone Debug and installed
on the connected competition device. After the owner unlocked it, five synthetic
requests completed using the real MiniCPM5-2B runtime: `hi` produced a greeting;
`lets speak English` returned "Let's speak English."; both vague discomfort
requests asked where/when symptoms started; the environment shortcut stated that
weather/environment data was absent, without the repeated welcome paragraph.
The brief "您好" remained on one discomfort reply; the full boilerplate did not.
Raw and processed text matched in all five cases. Elapsed times were 0.85-1.79
seconds. These cases verify the reported narrow gaps, not general answer quality,
sustained conversation-language switching, cloud behavior or access to real
weather data. No new inference constraints, canned replies or post-generation
rewriting were added during this audit. The app then launched normally again;
ordinary medication records were neither read into these tests nor changed.
The exact executable hash/source checkpoint and synthetic outputs are retained
in `latest-owner-device-receipt.json` and `latest-owner-device-results.txt` under
`.codex-local/local-ai-repair-20261028/round2/`.

## 2026-10-30 Duo assistant parallel workspace capture

The current Markdown chat screen had no auxiliary-column branch. Restored the
existing AssistantReadingLayout width budget and kept one chat/composer subtree;
wide layouts place runtime selection and vertical consultation topics beside the
current conversation. Narrow/accessibility layouts retain inline controls.
Simulator build and non-build quick gate passed; 84 layout-budget combinations
and open/closed fallback checks passed. The reused Duo displayed a real new cloud
reply to a natural today-records question, then retained the same conversation
through a recorded silver 3D closed-to-open transition. No phone install or release
claim. Supplemental real replies produced headings/numbered lists, but described
skipped tasks as missed/unprocessed; those takes are excluded from recommended
media and further model requests were stopped. Media and exact local binary hash: `.codex-local/yzy-rerecord-20261027/duo-markdown-20261030/Duo三维采用索引.md`.

## 2026-10-31 Targeted response gaps and simulator recording banner

Based on `946ee4a`, tightened prompt/context only for the reported local turns:
welcome language is reserved for pure greetings, explicit English requests take
priority, and standalone vague discomfort receives symptom clarification rather
than boilerplate. Specific symptoms/mixed record questions retain the original
context path. Pure language switches omit unrelated medication data; requesting
English for a medical question does not discard its records. No fixed response,
post-generation sentence deletion, or replacement answer was added.

Device synthetic raw generations showed “我不舒服” asking where/when symptoms
started; “我不好” asking for details; a no-weather quick prompt stating that
weather data was absent without the welcome paragraph. Initial English output
was an undesirable meta-description; shortening the task guidance yielded the
raw response “Let's speak English.” in the one-case recheck (0.84 seconds).
These are narrow cases, not a general quality/accuracy score. Ordinary user data
was not seeded or logged. The targeted policy/parser harness passed 31 tests;
simulator and signed iPhone Debug builds and quick checks passed. Independent
source review closed the vague-discomfort and mixed-English-context findings.

For the owner's explicitly authorized recording unblock, simulator Debug/Demo
builds accept `--recording-hide-reminder-banner`. This hides only the Today-page
ordinary-notification failure banner. Real scheduler errors remain unchanged;
physical devices and normal launches are unaffected. This is a recording-only
presentation option, not a repaired or validated notification delivery claim.
The budget wording in the supplied screenshot is absent from this branch, so
that recording binary may have a different source revision. Build this source
checkpoint before expecting its flag to work; do not reset a recording library.

Recording operator command (replace the placeholder with the existing selected
recording simulator; do not create a new simulator):

```sh
xcrun simctl launch --terminate-running-process <recording-simulator-udid> com.gwyy.appcontest2026.medicationadherence --recording-hide-reminder-banner
```

The simulator-only flag compiled successfully; it was not manually applied to
another thread's active recording simulator. No new simulator, model download,
real cloud call, push or main-merge claim in this local checkpoint. Evidence is
in the ignored `round2/targeted-turn-*` namespace. The owner retains manual
acceptance of arbitrary conversation quality and recording footage.

## 2026-10-30 Markdown, short conversation context and factual record summaries

Owner approved a small working loop rather than prepared answers or a new data
platform. Source investigation established that the app already reads authorized
SwiftData medication/task records, but local generic summaries collapsed all
medication counts into a total; request models carried no prior turns; output
normalization replaced table pipes with commas, and the stream parser collapsed
newlines. These were integration limitations as well as small-model limits.

- Adapted the owner-authorized local CatPaw Markdown parser, bounded render cache
  and views into `MedCueMarkdown*.swift`. Assistant bubbles now render headings,
  emphasis, lists, quotes and horizontally scrollable tables; user bubbles keep
  plain typed text. No dependency download or web/HTML renderer was added.
- Finalization can preserve Markdown after checking normalized visible content.
  Single emphasis and link-label splitting are covered by treatment-command
  regressions. Stream cleanup preserves line breaks; a character-by-character
  regression checks table/paragraph integrity. The default core plaintext review
  API remains available. Old messages whose pipes/newlines were destroyed are
  not reconstructed; newly generated messages use the new path.
- Requests have optional short conversation turns: the app includes at most
  four visible messages, 240 characters each, only for the same provider and
  matching consent scope. Local conversations are not included in cloud turns.
  Reasoning and system messages are excluded; prior answers are explicitly
  background, not authoritative current medical facts. This is short context,
  not long-term memory or a vector database. No schema migration was needed.
- Local “今天吃了什么” facts use recorded taken events for today, with explicit
  profile/record authorization checks; unshared data remains unknown. Recent
  generic summaries give per-medication counts rather than an ambiguous total.
  No generated response can write a medication action. Model wording quality is
  still limited and this work is not a broad accuracy guarantee.
- Composer appearance/disappearance now has a 0.22-second move/fade transition.
  Signed device and simulator builds, 34 focused core tests and 27 policy/parser
  tests passed. Independent review closed the Markdown-scan and unauthorized
  zero-count findings. No real cloud inference request was made.
- Three synthetic device generations completed (roughly 0.93–2.74 seconds):
  recent-turn reference retained the English names, today's taken query named
  ibuprofen once, and per-drug counts were ibuprofen 1 / loratadine 0. The initial
  table output exposed stream newline flattening and prompted the final parser
  fix; the final one-case recheck preserved valid multiline Markdown and correct
  per-drug counts in 1.76 seconds. Final installation and normal phone launch
  succeeded. Synthetic fixtures do not seed the
  ordinary database and are not scripted response fallbacks.
- Reused the existing `iPhone 17` simulator for the table-render screenshot,
  then shut it down. No new simulator was created; the earlier dedicated chat
  simulator remains deleted. The screenshot is clearly labeled synthetic UI
  evidence, not a real patient/model inference screenshot. Animation smoothness
  has not been separately measured on the physical phone.

Ignored receipts: `.codex-local/local-ai-repair-20261028/round2/context-markdown-*`.
No Git commit/push, PR, release or full native/CI integration claim.

## 2026-10-30 Cloud greeting and first-entry follow-up

The owner confirmed the previous local/UI build behaves well on the official
competition iPhone. Cloud screenshots showed “hi” eliciting a medication-count
summary; that came from the separate cloud prompt still requiring an authorized
medical-data answer. The shared cloud prompt builder now handles standalone
chat greetings/capability questions without medication/environment/import
context and asks the model to respond naturally. Mixed medical questions keep
the prior data path and boundaries; no scripted answer or server deployment was
introduced. Removed the unsupported “依法提供医疗服务能力” role claim.

Cloud waiting UI now uses the same understated progress row as local generation.
First-entry work yields before legacy maintenance, weather refresh is delayed
300ms and cancellable, and rendering reuses one visible-message projection.
These reduce eager/repeated work; no device timing or measured latency gain is
claimed. The owner's personal-phone first-entry lag was not profiled.

Seven focused core prompt tests passed, including populated-context greetings
and mixed personal-record questions. Native signed Debug build, quick preflight
and diff checks passed; independent source review found no Required. To conserve
traffic, no real cloud inference request, model download, or broad test rerun
was performed. Cloud answer quality still requires a live owner check after the
updated app is installed. All prior unrelated dirty changes were preserved.

At the owner's explicit cleanup request, the dedicated simulator created by
this task, `MedCue-ChatUI-20261030`, was shut down and deleted; its exact device
folder was confirmed absent. Screenshots/test receipts remain in the existing
ignored `round2/chat-polish-*` evidence namespace. Other recording simulators
and build/model directories were not deleted. Prefer reuse on subsequent work.

Receipts: `.codex-local/local-ai-repair-20261028/round2/cloud-followup-*`.
No commit, push, PR or public release claim.

## 2026-10-30 Chat UI polish and keyboard/scroll interaction

Local finals working tree: `codex/finals-baseline-integration`, base
`9d0892ae2787c32f655399a42c8ac8e612aebf02` plus preserved uncommitted changes.
Owner acceptance target: no composer/keyboard overlap, automatically hide the
composer while browsing older messages and restore at the latest message,
retain drafts, reduce taps, improve message appearance and text interactions.

- Composer now occupies the bottom safe area; the keyboard “收起” toolbar was
  removed, keyboard submit can send, and the tab bar hides while editing.
  History mode removes the native input control, rather than merely making it
  transparent (which left an accessible/hittable native field in UI tests).
  The external draft binding survives removal. Returning to the bottom restores
  the composer without a “继续提问” button. On iOS 18+, scroll phase includes
  deceleration and distance uses native scroll geometry. iOS 17 retains the
  geometry/drag fallback; short-fling inertia on that fallback is not verified.
- Rounded material message surfaces, a subdued user tint, smaller neutral
  source/time footers and a single navigation subtitle replace repeated
  assistant disclaimers/bright role headings. Message actions include copy,
  selectable text, quote-to-draft (preserving an existing draft), share and
  the existing archive command. Actual answer checks/persistence are unchanged.
- Read local CatPaw `Views/ChatView.swift`, `ChatMessageList.swift`,
  `MessageViews/UserBubble.swift`, `AssistantDisplayItemView.swift` and
  `Theme/ChatTheme.swift`; reused its stable-input, soft-surface and disclosure
  patterns. That local version has no complete message-copy context menu;
  MedCue uses native SwiftUI menus. Also reviewed the primary
  [Exyte/Chat repository](https://github.com/exyte/Chat) for keyboard, scrolling
  and long-press interaction. No new chat dependency was installed or copied.
- Thinking remains off by default; the local runtime has a boolean thinking
  option, no low/medium/high effort API. UI now reports generation/loading
  instead of pretending every direct-mode request is deep thinking. Actual
  completed reasoning, if present, keeps its disclosure; unchecked deltas are
  still not displayed. This work does not claim a model-quality improvement.
  Reference: [official MiniCPM5 model card](https://huggingface.co/openbmb/MiniCPM5-2B).
- Added an explicit DEBUG-only `--assistant-ui-preview` fixture: an in-memory
  model container and synthetic messages, without ordinary database access,
  networking or inference. It is not an answer fallback and is never the normal
  app path. UI acceptance covers keyboard/send-button bounds, history hiding,
  automatic restoration, draft survival, sending and long-press text actions.
- Independent fresh-context source review closed the draft-overwrite Required
  finding; later targeted review found no new Required. No commit, push, PR,
  migration, model reimport or ordinary database seeding was performed.

Validation: both focused Simulator UI tests passed on the isolated iPhone 17 /
iOS 27.0 fixture (keyboard/history/draft/send and long-press/select-text).
`chat-polish-ui-accepted.log` records 2 tests, 0 failures; quick native preflight
passed with 0 warnings and `git diff --check` passed. Simulator screenshots use
synthetic UI text, not model answers or patient data.

Local evidence namespace: `.codex-local/local-ai-repair-20261028/round2/chat-polish-*`.
Signed iPhone build and installation passed. Normal launch was denied because
the connected phone was locked (`FBSOpenApplicationErrorDomain`, code 7);
manual physical-device UI acceptance is therefore pending owner unlock/open.
No fixture launch flag was used on the physical phone. The existing model and
ordinary app data were retained. `chat-polish-device-receipt.txt` records this
limitation; the installed build supersedes prior installed-build receipts.

Full native/CI integration gates and older-platform UI acceptance are not claimed.

## 2026-10-29 Follow-up: avoid unrelated medication material in capability answers

The owner reported that “你能干些什么” produced medication names and lengthy
label warnings. Both prompts encouraged natural conversation but the request
still supplied the complete personal-fact summary for that question.

- Standalone greeting/capability questions now omit personal medication/label
  facts from the model prompt. All other questions retain the prior context
  path, avoiding a broad intent classifier. Both prompts require answering the
  current question without unsolicited unrelated medication warnings. Responses
  remain model-generated; no prepared answer or output clipping was added.
- Independent review caught over-broad draft filtering that dropped personal
  record queries; the final implementation removes that filtering. Regression
  cases retain facts for medication counts, visit preparation, mixed capability
  and record questions, and explanations of personal records/risk cards.
- Final signed Debug build and installation succeeded; normal launch restored.
  With in-memory synthetic medication snapshots, the final device evaluation
  answered two capability phrasings, hi and sleep education without unsolicited
  medication facts/warnings (about 0.99–1.73 seconds). A fifth control query,
  “我的药品有哪些？”, still returned a generic clarification despite retained
  facts: incomplete answer, not a successful factual-retrieval result. No broad
  accuracy claim is made and this adjacent quality issue was not expanded here.
- The local policy/parser harness passed 24 tests in 2 suites. Final independent
  source review closed the Required finding. Quick checks and diff whitespace
  check passed. Full native/CI integration gate was not run. No user database
  seeding, model reimport, commit or push occurred.

Ignored local receipts: `.codex-local/local-ai-repair-20261028/round2/relevance-*`;
`relevance-device-final-output.txt` belongs to the final installed working tree.

## 2026-10-29 Offline conversation and chat-input usability

Local finals work continues on `codex/finals-baseline-integration`, base
`9d0892ae2787c32f655399a42c8ac8e612aebf02` plus the preserved dirty tree.
The owner authorized natural greetings/general health conversation and a small
camera/composer improvement for competition demonstration.

- Root cause of “hi → 资料不足”: both the request prompt and runtime system
  prompt treated all conversation as personal-record lookup. Both now permit
  natural greetings and general health knowledge without personal records;
  missing personal values invite a useful follow-up. No prepared response or
  greeting interception was added. Diagnosis/prescription boundaries remain.
- Image menu now offers camera capture and photo-library selection. Camera
  permission uses the existing helper; capture reuses `CameraPhotoCaptureSheet`
  and local Vision text recognition. Recognized text enters the editable draft,
  without automatic sending. No new dependency or image upload was introduced.
- Vertical conversation dragging dismisses the keyboard and collapses the
  composer to “继续提问”; tapping restores editing/focus. Draft changes and a
  new send restore the composer. The existing view/draft is retained. CatPaw's
  local chat implementation informed keyboard dismissal and view identity.
- Signed Debug iPhone build, quick native preflight (0 warnings), and the local
  policy/parser harness (22 tests, 2 suites) passed. Independent source review
  found no Required issue. This is not the full native/CI integration gate.
- The updated app was installed on the connected phone. Four synthetic,
  empty-context MiniCPM5-2B direct-mode cases completed in 0.91–1.73 seconds:
  “hi”, “你好”, sleep education, and today's heart rate. Actual “hi” output:
  “你好！很高兴为你服务。有什么健康或用药方面的问题想聊聊吗？”
  The heart-rate answer asked for a value rather than inventing one. The app
  then launched normally. The smoke did not seed the ordinary user database.
- Camera capture/permission denial and composer gestures compile but have not
  received manual device UI acceptance. Personal heart-rate retrieval was not
  added. The previous 35-case evaluation was not repeated after this prompt
  change; this four-case check establishes the reported conversation behavior,
  not broad factual accuracy. The existing 72-character local question limit
  still constrains long image-derived drafts.

Local receipts: `.codex-local/local-ai-repair-20261028/round2/chat-usability-*`.
The new build supersedes this thread's October 28 installed-build fingerprint;
old recordings/receipts remain evidence of their original artifacts. No model
reimport, database reset, commit, push, PR or release was performed.

## 2026-10-28 Local offline-response repair and model selection

Scope: local `codex/finals-baseline-integration` working tree based on
`9d0892ae2787c32f655399a42c8ac8e612aebf02` plus uncommitted changes; this is not
an exact-commit CI, integration or release claim. Pre-existing Xcode project and
workspace changes were preserved.

- The local app now defaults to MiniCPM5-2B Q4_K_M direct mode. The pinned
  official 1,561,318,368-byte model passed Mac SHA-256 verification, was imported
  to the connected iPhone, and the final default-path smoke identified that
  model and passed. The updated app was installed and normally launched.
- English names and ordinary formatting are allowed. Removed topic keyword
  matching, destructive answer cleanup and generic-question trend misrouting.
  Corrected chat control-token parsing, duplicate sampler acceptance and
  context/model release order. No fixed-answer fallback remains.
- Direct mode: 35/35 synthetic device cases completed and passed current
  boundary checks, about 0.49–3.50 seconds. Manual review showed better grounding
  than the old 0.5B, with terse or confused responses remaining. Completion is
  not a comprehensive factual-accuracy score.
- Thinking mode: 4/5 empty-context built-in cases completed, about 5.20–11.94
  seconds for successful cases; one `boundary-or-empty` failure. No quality gain
  sufficient to justify default thinking was established. Existing reasoning
  parsing/UI is retained; manual UI acceptance is unconfirmed.
- Policy/parser SwiftPM harness: 21 tests passed using exact source copies and
  a model-label stub without llama inference. Simulator XCTest did not establish
  its runner connection and is not claimed passed. Device build/inference,
  quick checks and independent source review are separate evidence. The full
  native gate and current-revision CI were not completed for this work.

Decision and durable evidence summary: [ADR-0003](adr/0003-use-minicpm5-2b-for-local-finals-evaluation.md).
Detailed ignored local receipts: `.codex-local/local-ai-repair-20261028/round2/验收结果.md`.
Old model files remain; weights, raw console/build logs and device identifiers
must not be added to Git or source packages. No push, PR, merge or publication
was performed.

## Current Verified Snapshot

- At the audit baseline, `main` was the repository default branch and was
  synchronized with the exact baseline revision above.
- The repository is private. This records current GitHub visibility only; it
  does not claim that previous clones, caches, or provider retention have been
  purged.
- The canonical history-normalization prerequisite in [Issue #1](https://github.com/Gavin8233841/medcue-ios/issues/1)
  is complete. The sanitized lineage and the current tree are preserved by the
  published archive and audit/preparation refs listed below.
- The audit-baseline tree contains 347 tracked files and 216 tracked Swift
  files. Its Swift sources contain 53,941 non-empty lines (`Length -gt 0`) and
  59,000 full physical lines.
- The project contains six Xcode targets: the iOS app, Live Activity extension,
  Watch app, Watch widget, hosted unit tests, and UI tests.
- The project uses Swift 6.0 language mode with iOS 17.0 and watchOS 10.0
  deployment targets.
- The local Xcode baseline is Xcode 27 Beta 5 (`27A5237l`) at
  `/Applications/Xcode.app`, selected through `xcode-select`, with Apple Swift
  6.4 and iPhoneOS/watchOS 27.0 SDKs. Xcode native MCP, Release, Controlled Demo,
  native RunProject, and the iOS 26.5 Simulator path were verified on 2026-08-23.
  This tool acceptance is not evidence for later source revisions or physical
  devices and should not be repeated unless a change requires it.

## Exact-Revision Evidence

Run `32640833807` completed successfully on `main` at
`d6aa4af85f225028fc3f912391328e1f745d0b34` on 2026-08-23 through the full
Native Verification lane (every main push uses the full Route A gate). Its
recorded test evidence is:

- Swift Core: `152/152`
- Hosted iOS: `168/168`
- XCUITest smoke: `2/2`
- Token Broker: `28/28`

This is exact-revision CI evidence for the audit baseline; it does not transfer
to a later `main` HEAD. It also does not certify physical-device behavior,
Apple account configuration, provider retention, App Store Connect answers, or
commercial-production readiness.

The prior CODEOWNERS bootstrap revision
`c8b9dffd2cfaa481f6e654ea399645a847745a73` completed Native Verification in
[run 32620495542](https://github.com/Gavin8233841/medcue-ios/actions/runs/32620495542).
This proves the full gate for that exact CODEOWNERS bootstrap revision; it does
not transfer to later local or Pull Request changes.

The CI risk-lane merge at
`c47416944790c5c4e7f1e3a03c4958473c1856fd` completed its push-triggered full
Route A gate successfully in
[run 32622093916](https://github.com/Gavin8233841/medcue-ios/actions/runs/32622093916)
on 2026-08-23. This is the exact post-merge evidence required by Issue #39; it
does not transfer to the local finals documentation branch.

The iOS DEBUG diagnostic-log privacy fix from Issue #23 / PR #43 merged at
`15517b3649639539c05015970d2f6088df7426f9`. Its push-triggered full Route A
gate and required-result job completed successfully in
[run 32624679340](https://github.com/Gavin8233841/medcue-ios/actions/runs/32624679340)
on 2026-08-23. The fix removes medication display text, task identifiers, and
due-time values from the reminder/Live Activity smoke success log; it does not
change reminder actions, persistence, or medical behavior.

Issue #5 / PR #44 merged at `main@d6aa4af85f225028fc3f912391328e1f745d0b34`
from exact PR head `1698eafdc6743412a7ca6edfb7c4eed17b39e72d`. Its exact-head
Native Verification passed in PR run 32638615264, and the post-merge main push
gate passed in [run 32640833807](https://github.com/Gavin8233841/medcue-ios/actions/runs/32640833807)
with the required-result job successful. Issue #5 is closed. The source-package
follow-up is recorded under Current Delivery State below; those historical CI
results do not certify its later revisions.

### Reproduce The Audit-Baseline Counts

The following PowerShell command reads the named Git tree directly, so later
working-tree or `main` changes do not alter the result:

```powershell
$Revision = 'd6aa4af85f225028fc3f912391328e1f745d0b34'
$TrackedFiles = @(git ls-tree -r --name-only $Revision)
$SwiftFiles = @($TrackedFiles | Where-Object { $_.EndsWith('.swift') })
$NonEmpty = 0
$Physical = 0

foreach ($Path in $SwiftFiles) {
  $Lines = @(git show "${Revision}:$Path")
  $NonEmpty += @($Lines | Where-Object { $_.Length -gt 0 }).Count
  $Physical += $Lines.Count
}

[pscustomobject]@{
  Revision = $Revision
  TrackedFiles = $TrackedFiles.Count
  SwiftFiles = $SwiftFiles.Count
  NonEmptySwiftLines = $NonEmpty
  PhysicalSwiftLines = $Physical
}
```

Expected values are `347`, `216`, `53941`, and `59000`, respectively.

## History And Privacy Boundary

Issue #1 established the authoritative `main` and completed the reviewed
history-normalization operation. The following refs remain as sanitized audit
or archive references:

- `refs/tags/archive/main-before-history-normalization-issue-1` ->
  `e8e0fa84523e859a2990161fc8aa1eda1c5a8b66`
- `codex/issue-1-old-main-sanitized-prep` ->
  `e8e0fa84523e859a2990161fc8aa1eda1c5a8b66`
- `codex/docs-and-signing` ->
  `9f663159bb1a746b1fd7b1fa6fe2cb4e32b73765`
- `codex/issue-1-target-sanitized-prep-v2` ->
  `280e5b3f8425f155d5e20a71841f4169a63bc59d`

These refs document the reviewed lineage and are not an invitation to import
raw pre-normalization history. The current tree does not restore removed logs,
handoffs, assets, placeholders, databases, models, secrets, or device-specific
data. GitHub ref sanitization also cannot prove that every prior clone, cache,
backup, or hosting-provider retention copy has been removed.

## Current Delivery State

The repository uses focused local milestones with GitHub integration gates.
Remote collaboration, durable backlog, Pull Request review, exact-revision CI,
and merge to `main` remain governed by `DEVELOPMENT_WORKFLOW.md`; normalization
is no longer a blocker.

`main` includes the Controlled Demo path, active-work coordination, Broker
security changes, bounded Broker idempotency-cache expiry/capacity from Issue
#35 / PR #38, the trusted CODEOWNERS bootstrap from PR #42, the CI risk lanes
from Issue #39 / PR #40, the iOS diagnostic-log privacy fix from Issue #23 / PR
#43, and the reproducible source package from Issue #5 / PR #44. The active
`main-trusted-delivery` ruleset still requires the exact Native Verification
required-result check, blocks branch deletion and non-fast-forward updates, and
requires review-thread resolution, but it no longer requires a Code Owner
approval for every Pull Request. Independent author/fresh-context review and
the relevant evidence gates remain required by the workflow.

On 2026-09-07, GitHub confirmed that [PR #48](https://github.com/Gavin8233841/medcue-ios/pull/48)
is closed without merging. [Issue #47](https://github.com/Gavin8233841/medcue-ios/issues/47)
remains open, assigned to `yzy1020`, with `state:in-progress`.
[PR #49](https://github.com/Gavin8233841/medcue-ios/pull/49) is its open Draft
Pull Request targeting `main`. It owns `docs/SOURCE_PACKAGE_POLICY.md`,
`docs/TEST_STRATEGY.md`, `tools/build-source-package.py`,
`tools/test-source-package.py`, and `tools/verify-source-package.py`.
The one-writer rule applies to those files; unrelated documentation need not
wait. Recheck the live file list before further work.

The local governance update retains the existing safety and merge requirements,
centralizes the complete autonomous merge gate in `DEVELOPMENT_WORKFLOW.md`,
and preserves the build-cache incident and prevention rules in
`TOOLING_AND_PLUGIN_PLAN.md`. It clarifies independent technical investigation,
proportional local checks, and skill prerequisites. This update is local to
`codex/finals-baseline-integration`; it does not claim a merged revision,
successful remote CI, or new device/account evidence.

### Accepted Finals Direction — Planning Only

- MedCue remains a general medication-management product. Elder-friendly mode
  is the flagship differentiated experience, not the only user narrative.
- Elder-friendly and complete experiences share one medication/action core.
  Missing response remains unconfirmed rather than inferred as intentional
  skip.
- Initial family help is same-device assisted setup. Remote child collaboration
  and a clinician mini-program remain future directions.
- AI is an enabling boundary, not the main download reason or a medication
  decision-maker.
- This direction does not claim that elder-friendly mode or any remote family
  or clinician surface is implemented.
The repository uses the Issue -> branch -> Pull Request -> CI workflow. Open
work remains in the GitHub backlog; normalization is no longer a delivery
blocker. The 2026-08-22 Draft PR trio (#26 Controlled Demo, #30 coordination
protocol, #31 post-migration truth) has merged, followed by risk-tiered Native
Verification lanes (Issue #39 / PR #40), a trusted CODEOWNERS root for
`.github/` and `tools/` (#42), log-privacy sanitization (#43, closing Issue
#23), and the reproducible exact-commit source package (#44). At this audit,
open PR #49 (Issue #47, source-package hardening, branch
`codex/47-source-package-hardening-main-yzy1020`) owns
`docs/SOURCE_PACKAGE_POLICY.md`, `docs/TEST_STRATEGY.md`,
`tools/build-source-package.py`, `tools/test-source-package.py`, and
`tools/verify-source-package.py`; other work must integrate serially behind it
on those files. (Its predecessor PR #48 was closed unmerged on 2026-08-23 and
is superseded by PR #49.) The shared-file ownership and cumulative-diff rule
are recorded in `docs/DEVELOPMENT_WORKFLOW.md`.

The open Issues carrying `已阻塞` are exactly:

- #10, AI request lifecycle behind a tested conversation session
- #11, bounded AI observation and on-demand conversation history
- #17, physical-device system acceptance matrix
- #18, Add Medication workflow ownership
- #19, Today dose lifecycle ownership
- #21, complete English product surfaces
- #22, bilingual Medication Assistant safeguards

Issue #23 (health-content retention and logging boundaries) is closed by PR
#43. Issue #1 is closed without `需要产品决策`. Closed Issue #24 is a
milestone-free `重复` without `已阻塞`. Issue #25 carries the evidence-backed
`功能` type and has no invented priority or milestone. Active leases
(`state:in-progress`) at this audit: #33 (Chinese-first GitHub surface), #45
(finals baseline documentation), #46 (elder-mode M1 prototype), and #47
(source-package hardening).

## Engineering Shape And Remaining Risk

- Portable domain logic, SwiftData transactions and migrations, iPhone-primary
  system snapshots, consent-scoped AI context, response safety checks, and the
  constrained Broker remain the current architectural boundaries.
- Live Activity URL authorization remains tracked by Issue #2.
- Broker fail-closed startup, bounded provider responses, and bounded
  idempotency-cache expiry/capacity are merged. Issue #23 / PR #43 also closed
  the remaining iOS DEBUG reminder/Live Activity diagnostic-log exposure; its
  exact post-merge evidence is recorded above.
- The finals direction adds planned dual-experience and unconfirmed-action
  invariants. Runtime implementation and evidence remain future milestone work.
- The Issue #14 privacy candidate uses generic iPhone system-surface text,
  requires unlock for notification dose actions, and removes direct Live
  Activity dose writes. Its legacy-content migration is implemented in the
  candidate branch; exact-head CI and Simulator system-surface checks remain
  open. See `docs/adr/0003-iphone-system-reminder-privacy.md`. Issue #2 remains
  open for the full authorization regression boundary, and Issue #17 retains
  real-device release evidence.
- Broker fail-closed startup and bounded provider responses remain tracked by
  Issue #3.
- Consent revocation transactionality, persistent-store recovery, physical
  device evidence, locale-independent state, and measured performance remain
  tracked by Issues #12, #13, #17, #20, and #8/#11 respectively.
- These are product, medical, privacy, security, platform, and performance
  follow-ups. This governance change does not alter runtime behavior or claim
  that those risks are resolved.
- The finals product direction, local-first boundary, elder-mode M1 gates, and
  the Xcode 27 native MCP toolchain decision are recorded in
  `docs/FINALS_PRODUCT_PLAN.md` and
  `docs/adr/0002-xcode-27-native-mcp-toolchain.md`.

## Documentation And Local Artifact Boundary

`docs/README.md` distinguishes current documents from historical evidence and
explicitly marks absent or privacy-removed materials as unavailable.
`FINALS_PRODUCT_PLAN.md` owns the accepted priority and milestone direction;
`TOOLING_AND_PLUGIN_PLAN.md` owns the current local tool boundary. The repository
does not reconstruct `PROJECT_UPDATE_LOG.md`, old handoff files,
removed Watch logs, contest assets, knowledge graphs, databases, local models,
or other sanitized inputs. Historical documents that remain tracked are audit
context only and may contain statements that were true only at their original
revision.

The repository ignores the verified local-only output roots `/.codex-build/`
and `/.verify-native-output/`, standalone `*.xcresult/` result bundles, and
database/store suffixes used by the native artifact scan: `*.sqlite`,
`*.sqlite-*`, `*.sqlite3`, `*.sqlite3-*`, `*.store`, and `*.store-*`.
Ignore rules reduce accidental staging risk; they do not replace release
scanning or review of intentionally added fixtures.

## Continuing Delivery

1. Start normal feature delivery from canonical `main`; do not import raw
   pre-normalization history or rewrite refs.
2. Require review and exact-head CI for each proposed merge; evidence from an
   earlier commit does not transfer to a new HEAD.
3. Work through one finals milestone at a time. Use GitHub for remote or durable
   ownership and for integration; record macOS/Xcode, device, account, and
   provider checks where Windows cannot provide them.
4. Do not describe the competition/Beta scope as App Store, clinical, or
   commercial-production ready without the corresponding evidence.

### 2026-11-03 Duo cover follow-up

- Limited Duo work to the medication sidebar and two-column photo gallery; no Duo hardware acceptance or expanded accessibility validation is claimed.
- Captured and visually checked the photo-bearing synthetic Simulator cover. Its explicit DEBUG Simulator preview reads bundled demo artwork; normal medication photos and device behavior are unchanged.
- Simulator build passed; fresh-context review found no Required or Blocker findings for this follow-up.

### 2026-11-03 D3 artwork and chat composer surface

- Added owner-supplied vitamin D artwork to the bundled demo mapping; existing selected photos remain preserved. No medication facts changed. Existing devices receive the missing artwork when preparing the next demo; this validation did not reset device data.
- Reused the existing native Liquid Glass surface for the chat composer, retaining its material fallback and existing input/focus/send behavior.
- Simulator and physical-device Debug builds and native quick checks passed. The connected competition phone accepted in-place install and normal launch. Fresh-context review found no Required or Blocker findings. Visual/keyboard interaction acceptance was not repeated: RocketSim reported a stale IPC socket; the test Simulator was shut down. No cloud/model calls were made.

### 2026-11-04 Foundation Models custom local provider

- The owner authorized only the minimal WWDC26 custom-provider integration. iOS 27+ production local chat and the synthetic smoke runner use LanguageModelSession through a private custom LanguageModel/LanguageModelExecutor, backed by the existing MiniCPM5-2B llama runtime. Earlier iOS uses the existing runtime directly. Each request creates a fresh text session and forwards the app's preassembled prompt, including its existing authorized context and history.
- Five focused Simulator tests passed for exact prompt/token-limit forwarding, stream snapshot deduplication, inference failure, split Unicode combining characters and cancellation reaching the backing runtime. Native quick checks and Simulator/device Debug builds passed. Independent fresh-context review closed the Unicode Required finding with no remaining Required or Blocker.
- Connected competition iPhone, iOS 27.3 build 24C5037i: synthetic case 36 returned a greeting in 9.66 s; case 45 returned a Markdown table consistent with the supplied two-medicine conversation/context in 2.48 s. These are smoke observations, not a comparative performance study. Existing user records were not changed by these synthetic requests.
- Apple SystemLanguageModel separately returned deviceNotEligible and unavailable session assets in the probe. Custom-provider inference succeeded on the same phone. This change does not claim Apple system-model access, Core AI migration, ANE acceleration or improved model quality.
- Local evidence is under `.codex-local/local-ai-repair-20261028/round2/fm-adapter-*`. This is local validation, not full native-gate/CI or main-merge acceptance. Existing Localizable.xcstrings changes and an independently observed project-file reorder are excluded from this commit.

### 2026-11-04 latest-app preservation and integration assessment

- Current development workline `codex/finals-baseline-integration` contains the booth photo gallery/demo recovery (`4185484`), deterministic synthetic Duo cover (`a3656ed`), D3/composer material (`042ca15`), custom Foundation Models provider (`3f5800d`), and transparent composer (`463e17d`). The latter passed Simulator compilation and native quick checks.
- Integration was assessed against `origin/main@4d9c6d50d46a5735dc014da5434e1063d8cf7493`. Main has 49 non-ancestor commits and the development workline has 20. Endpoint trees differ across 202 files; a read-only merge-tree check reports 22 conflicted paths. No merge has been performed.
- The 22 conflicts comprise five product/governance/media documents, four asset manifests, the Xcode project, ten application source files and two test files. Current demo/media, root/mode UI and chat behavior require semantic reconciliation. Main's consent/privacy, reminder transaction/idempotency, dose-unit preservation, build opt-in and trusted verification changes must be accounted for individually. Selecting one branch wholesale would discard accepted work.
- Remaining local Xcode edits are checkpointed separately. Parsing both project versions with plutil confirms identical project data despite object-order changes. Generated localization entries cover the new UI. Untracked agent/plugin/workspace metadata stays outside the checkpoint.
- Proposed integration order: preserve and remotely back up the latest-app workline; reconcile current-main engineering fixes and latest-app behavior in a separate candidate; review the cumulative diff; pass the full native gate, exact-revision CI and applicable independent/device checks before main merge. The conflict assessment is a preservation checkpoint, not integration acceptance.

### 2026-11-04 debugger white-screen and chat layout check

- Xcode showed the competition app paused at breakpoint 1.1 in NotificationService.swift line 270, during startup reminder reconciliation. A second LLDB attach was rejected because the process was already debugged. Deactivating Xcode breakpoints and continuing execution restored the Today screen in Device Hub. This observation establishes a debugger pause for the reported white screen.
- Changed the conversation container from VStack to LazyVStack so off-screen Markdown message bubbles are created on demand. No message content, model policy or stored records were changed. Native quick checks and the physical-device Debug build passed.
- Installed the incremental build, ended Xcode debugging, launched normally and observed Today, assistant-tab navigation and scrolling to the latest message on the physical phone. The reported approximately 1000 ms stalls were not instrumented before/after; no quantitative performance improvement or elimination of all stalls is claimed.
- Existing Xcode breakpoints were deactivated for demonstration/runtime verification. The source breakpoint locations were retained. No simulator was started for this check.
## Issue #89 Candidate: Schedule Failure Boundary (2026-09-22)

The `codex/89-schedule-failure` candidate is stacked on Issue #81's reviewed
checkpoint `8a9ca69f27b1948cbddf1e247bdd35c7a2f3f5d0`; it is not evidence that
the native parent chain has merged into main.

Global reconciliation prepares every applicable schedule before mutating any
task. Creation, plan editing and medication reactivation also prepare schedules
before inserting or updating models. A schedule failure is explicit, does not
save or apply system reminder effects, and does not roll back unrelated
unsaved edits. Startup retry and command failure messages expose this outcome.
Existing plan identity/time-zone policy and the legacy 21:00 fallback for
unparseable reminder times are preserved; genuinely ended courses still have
legitimate empty schedules.

The candidate's source passed 23 focused hosted tests across four suites on a
dedicated clean Simulator, including multi-plan failure, command failure,
unsaved-edit preservation and retry without duplicate tasks. Validation used
the existing CI-compatible `MEDCUE_DISABLE_LOCAL_LLAMA=1` configuration and
synthetic in-memory records; it does not validate local-model inference or
physical-device notification delivery. Exact final-commit full-gate, CI and
independent-review evidence belongs in the linked Issue/PR. #82 still owns
cross-await scheduling convergence and the global request budget.

## Issue #82 A Candidate: Ordered Reminder Effects (2026-09-22)

The `codex/82-reminder-serialization` candidate builds on PR #93 at
`928771223188b33fc1c9d5c4cb6c467c5154ec72`. Each process serializes complete
system-reminder operations, including suspension points. iPhone post-commit
and NotificationService paths share one owner; Watch compiles the same queue
source and owns its own instance. Cancelling a UI waiter does not cancel an
already committed reminder update.

Successful commands freeze reminder values and enqueue before deferred UI or
Live Activity work. Today, record correction, lifecycle changes, notification
and Live Activity actions submit whole reminder groups. Global reconciliation
alone prunes the global snapshot; a single-plan update preserves other plans.
Read/schedule/save failure boundaries from #81/#89 remain in place. Notification
and Live Activity delay snapshots now retain the plan's escalation setting.

Local candidate evidence: 32 focused hosted tests passed, including controlled
cross-instance reconciliation interleaving and existing failure/no-side-effect
checks; two portable queue tests (including replacement/cancellation cases)
and Watch Simulator Debug build passed. The complete native gate is delegated
to exact-revision CI rather than duplicating the whole UI/build matrix locally.
Final quick, review and CI evidence is recorded in the Issue/PR. This candidate
is not integrated main or physical-device delivery evidence. Issue #82 B still
owns actual-request budgets, partial failures and recovery.

## Issue #82 B Candidate: Actual Request Budget and Recovery (2026-09-25)

The iPhone post-commit and NotificationService paths now share one serialized
system scheduler. Its app policy of 60 counts pending notification and AlarmKit
requests, including other medications, base alerts, alarm delivery and
escalation. Post-commit iPhone entry points read a fresh committed global task
snapshot and replan all medication reminders, so an earlier new dose can
displace later requests across plans. Base and escalation requests are budgeted
by their actual due time across medications, with a stable task ID tie-breaker.
A second base notification channel receives only spare capacity after the
selected base and escalation requests, then runs at its own due time among all
selected requests. If the base time has passed but the
five-minute escalation is still ahead, the open task remains eligible for
escalation only. Replanning
preserves its existing base notification or alarm while replacing the future
escalation, and submits selected requests in global due-time order.
The scheduler rechecks both times after cancellation and permission waits and
before each add; if the base expires during an add attempt, its reserved slot
can still carry the future escalation and the missed base is reported.
Global cancellation reads both pending and delivered notifications. A delivered
reminder for a completed task is removed, while a delivered base or escalation
for an open overdue task remains available for action. The preservation set is
recomputed at cleanup time, including an open reminder that became due while
its committed snapshot waited in the queue. Snapshot capture time is retained
so an entire reminder window that closes before or during execution receives a
persistent failure warning. A base reminder that expires while queued also
receives partial-failure feedback when its escalation is still schedulable;
feedback describes only the requests that were actually arranged. The delivered
readback catches a completed task's notification that fires during cancellation,
and rechecks pending requests and AlarmKit state before deciding whether to
block replacement or count occupied slots. The readback requires two stable
clear rounds; unresolved requests after bounded retries retain a failure warning.
When a candidate has only one free slot, its selected base delivery takes
priority over its later escalation or a second base channel; the omitted
escalation is reported as a partial result. If a selected base alarm then fails, an ordinary
notification can reuse that reserved request slot as a fallback.
The policy is an app-side budget, not an assertion about an iOS system limit.

Cancellation is read back before replacement. A request that remains pending
blocks its own replacement; an AlarmKit read failure or unresolved cancellation
is reported rather than hidden. Base and escalation additions return distinct
failure outcomes, and an AlarmKit escalation failure can use a notification
within its reserved slot. A full startup reconciliation or the startup retry
alert can recover after partial success, using stable request identifiers.
The Today and Settings warning surfaces disclose an incomplete system update.
Startup reconciliation also reports an incomplete outcome when budget or
permission leaves a task unarranged, keeping the retry alert available.
System sync warnings use a separate key from notification authorization warnings,
so a permission refresh cannot erase an unresolved scheduling failure. If an
AlarmKit add fails or alarm authorization is unavailable, an ordinary-notification
fallback is reported as a partial result and remains eligible for retry. The
persistent warning names the missing selected alarm for both cases, including
batch paths that do not display individual scheduling results. Warnings are
tracked per task, so a successful local retry clears only the resolved task's
warning. Elder delay feedback shows the specific partial-result message.
The shared path now uses a MainActor service; real-device save responsiveness
after this change has not been measured and needs a device check before merge.
Global replanning cancels and replaces the selected reminders; interruption
between those system calls is recovered on next startup but needs device review.

Local candidate evidence before the escalation-window fix: 42 focused hosted
test functions (40 unit, two UI), 47 test runs and zero failures on an iPhone
17 Pro iOS 26.5 Simulator, covering
request-budget ordering, delivery availability, partial add retry, cancellation
readback, warning text in elder mode and existing reconciliation behavior.
After the cleanup and budget fixes, four focused suites passed 44 tests with
zero failures on the same Simulator, including crossing the base and escalation
windows before and during queue execution, request-time selection and
submission order across medications, delivered-notification cleanup and
pending-to-delivered readback races including a late retry round, accurate
partial-failure and startup-retry outcomes, and preservation of an open task's
displayed reminder.
Full current-head CI remains pending.
This is not exact-head CI, physical-device
delivery, or a claim that the OS accepted or delivered every request. PR #94
remains Draft pending final gates, independent review and parent/main
integration; #17 owns the real notification and AlarmKit device matrix.

## 2026-11-06 Rolling reminder window feedback correction

Normal distant-task deferral and a base reminder whose distant escalation lies
outside the finite scheduling window no longer count as system failures. The
scheduler still returns truthful per-task deferral details; full-capacity queues
with no assignments, expired bases, permission failures, add failures and cleanup
failures retain failure reporting. Successful subsequent reconciliation clears
old budget warnings. Today records also removes the outer white card around the
Glass disclosure control. A fresh independent source review found no remaining
Blocker/Required findings. Hosted tests passed with regression coverage for the
rolling boundary, expired deferred tasks, true failures and no available slots.
Physical installation/visual checks remain separate evidence.

## 2026-11-06 Elder recognition layout and direct medication entry

The integration adopted main's compact elder identity card, regressing the
previous centered photo/name/dose presentation. The standard elder view now
restores that hierarchy with a 200-point bounded photo, 34-point scaled name
and title-size dose. The existing three-action workflow remains connected.
The medication plus button opens the existing manual form directly, removing
the redundant picker with two unavailable routes. The first hosted run hit a
model cancellation timing failure; a repeat passed all 349 tests in 50 suites.
Device appearance is recorded separately from those test results.
