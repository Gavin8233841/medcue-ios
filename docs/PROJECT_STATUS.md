# MedCue Project Status

Last audited: 2026-08-23
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
selected base and escalation requests. If the base time has passed but the
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
persistent failure warning.
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
After the cleanup and budget fixes, four focused suites passed 38 tests with
zero failures on the same Simulator, including crossing the base and escalation
windows before and during queue execution, request-time selection and
submission order across medications, delivered-notification cleanup, and
preservation of an open task's displayed reminder.
Full current-head CI remains pending.
This is not exact-head CI, physical-device
delivery, or a claim that the OS accepted or delivered every request. PR #94
remains Draft pending final gates, independent review and parent/main
integration; #17 owns the real notification and AlarmKit device matrix.
