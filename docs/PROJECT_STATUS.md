# MedCue Project Status

Latest coordination audit: 2026-09-22
Current source checkpoint: `7de86b34df209bd6b33aca8495b9c9a5ec4e16ae`

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
  acceptance. #33 remains open for its explicit Topics decision. #20's local
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
explicitly marks absent or privacy-removed materials as unavailable. The
repository does not reconstruct `PROJECT_UPDATE_LOG.md`, old handoff files,
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

1. Keep the canonical `main` as the only feature-delivery starting point; do
   not import raw pre-normalization history or rewrite refs.
2. Require review and exact-head CI for each proposed merge; evidence from an
   earlier commit does not transfer to a new HEAD.
3. Work through the remaining GitHub Issues one focused branch and Pull Request
   at a time, with macOS/Xcode, device, account, and provider checks recorded
   where Windows cannot provide them.
4. Do not describe the competition/Beta scope as App Store, clinical, or
   commercial-production ready without the corresponding evidence.

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
