# MedCue Project Status

Last local-candidate update: 2026-09-15
Authoritative integration branch: `main` (not re-audited in this local update)
Historical main audit: 2026-08-23 @ `d6aa4af85f225028fc3f912391328e1f745d0b34`
Audit-baseline CI: [Native Verification run 32640833807](https://github.com/Gavin8233841/medcue-ios/actions/runs/32640833807)

This is the engineering-status document. GitHub Issues hold the active backlog,
Pull Requests hold implementation and review evidence, and accepted ADRs hold
durable decisions. The local candidate below is not an integrated `main`
revision. This docs-only update follows the candidate code SHA; it does not
change the validated code and needs its own exact-revision documentation
checks. The 2026-08-23 GitHub, count, and CI statements below it are a historical
exact-revision snapshot, not a claim about today's remote state.

## 2026-09-15 Local Candidate: Issue #46 Notification Postpone

- Local branch: `codex/46-notification-postpone-fix`; exact validated code commit:
  `e19571b64cfdfb46ddb22d6c343b1c379f157288`; parent:
  `6e7633ec2296d237d57ff9304704a6dba893341e`. The code worktree was clean
  after verification, before this two-document update. This is a
  local committed code candidate, not pushed or merged; exact-HEAD remote CI
  for this SHA has not been verified.
- A fresh-context independent review of the cumulative parent-to-code-commit diff
  reported 0 Blocker, 0 Required, and 1 Advisory: a real notification callback
  and actual delivery still need separate evidence. The review does not approve
  a release or turn Simulator checks into device proof.
- Exact-HEAD focused notification/platform tests passed 9/9; the non-build
  `tools/verify-native.sh --quick` checks passed. Evidence is retained locally
  under `.codex-local/notification-postpone-test/` as
  `exact-head-focused-xcodebuild.log` and `exact-head-quick.log`.
- The default complete Route A `tools/verify-native.sh` passed on a fresh,
  synthetic-only iPhone 17 Pro Simulator: Swift Core 150 tests, hosted iOS 218,
  UI tests 24/24, unsigned iPhone Release build and artifact assertions,
  Watch Simulator Debug build, and watchOS device-SDK Release build. The
  exact-HEAD log is
  `.codex-local/notification-postpone-test/full-native-retry-e19571b.log`.
  The first run failed before UI assertions because the new Simulator denied
  the UI runner launch as Busy; after boot initialization, the isolated UI
  suite and then the uninterrupted default full gate passed. The first-run
  log remains at `.codex-local/notification-postpone-test/full-native-e19571b.log`.
  The older shared Simulator database was not cleared or reset.
- This local run used Xcode 27.0 (Build `27A5237l`), Apple Swift 6.4, an iOS
  26.5 Simulator runtime, and the script's documented Watch SDK overrides to
  the installed 27.0 SDKs. An extra Broker `node --test` run passed 28/28
  under local Node 24.14.0; it is not Node 18.15.0 CI evidence. Physical-device
  behavior, real notification delivery, account/competition acceptance, and
  this SHA's remote CI remain unverified.

## Historical Verified Snapshot (2026-08-23)

- At the audit baseline, `main` was the repository default branch and was
  synchronized with the exact baseline revision above.
- At this audit, the repository was private. This records GitHub visibility
  at that time only; it does not claim that previous clones, caches, or
  provider retention have been purged.
- The canonical history-normalization prerequisite in [Issue #1](https://github.com/Gavin8233841/medcue-ios/issues/1)
  was complete. The sanitized lineage and the audit-baseline tree were
  preserved by the published archive and audit/preparation refs listed below.
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
history-normalization operation. At this audit, the following refs served as
sanitized audit or archive references:

- `refs/tags/archive/main-before-history-normalization-issue-1` ->
  `e8e0fa84523e859a2990161fc8aa1eda1c5a8b66`
- `codex/issue-1-old-main-sanitized-prep` ->
  `e8e0fa84523e859a2990161fc8aa1eda1c5a8b66`
- `codex/docs-and-signing` ->
  `9f663159bb1a746b1fd7b1fa6fe2cb4e32b73765`
- `codex/issue-1-target-sanitized-prep-v2` ->
  `280e5b3f8425f155d5e20a71841f4169a63bc59d`

These refs document the reviewed lineage and are not an invitation to import
raw pre-normalization history. The audit-baseline tree did not restore removed logs,
handoffs, assets, placeholders, databases, models, secrets, or device-specific
data. GitHub ref sanitization also cannot prove that every prior clone, cache,
backup, or hosting-provider retention copy has been removed.

## Historical Delivery State (2026-08-23)

The repository uses the Issue -> branch -> Pull Request -> CI workflow. At this
audit, open work remained in the GitHub backlog; normalization was no longer a
delivery blocker. The 2026-08-22 Draft PR trio (#26 Controlled Demo, #30
coordination protocol, #31 post-migration truth) had merged, followed by
risk-tiered Native Verification lanes (Issue #39 / PR #40), a trusted
CODEOWNERS root for `.github/` and `tools/` (#42), log-privacy sanitization
(#43, closing Issue #23), and the reproducible exact-commit source package
(#44). PR #49 was open at this audit (Issue #47, source-package hardening,
branch `codex/47-source-package-hardening-main-yzy1020`) and owned
`docs/SOURCE_PACKAGE_POLICY.md`, `docs/TEST_STRATEGY.md`,
`tools/build-source-package.py`, `tools/test-source-package.py`, and
`tools/verify-source-package.py`; other work was then expected to integrate
serially behind it on those files. Its predecessor PR #48 had closed unmerged
on 2026-08-23 and was superseded by PR #49. The shared-file ownership and
cumulative-diff rule are recorded in `docs/DEVELOPMENT_WORKFLOW.md`.

At this audit, the open Issues carrying `已阻塞` were:

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

## Audit-Baseline Engineering Shape And Remaining Risk

- Portable domain logic, SwiftData transactions and migrations, iPhone-primary
  system snapshots, consent-scoped AI context, response safety checks, and the
  constrained Broker were the audit-baseline architectural boundaries.
- Live Activity URL authorization was tracked by Issue #2.
- Broker fail-closed startup and bounded provider responses were tracked by
  Issue #3.
- Consent revocation transactionality, persistent-store recovery, physical
  device evidence, locale-independent state, and measured performance were
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

The repository ignores local-only output roots `/.codex-build/`,
`/.verify-native-output/`, and `/.codex-local/`, standalone `*.xcresult/`
result bundles, and
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
