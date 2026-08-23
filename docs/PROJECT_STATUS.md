# MedCue Project Status

Last audited: 2026-08-23
Authoritative branch: `main`
Authoritative `main` observed at: `15517b3649639539c05015970d2f6088df7426f9`
Post-migration audit baseline: `280e5b3f8425f155d5e20a71841f4169a63bc59d`
Audit-baseline CI: [Native Verification run 32171788727](https://github.com/Gavin8233841/medcue-ios/actions/runs/32171788727)

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
- The audit-baseline tree contains 334 tracked files and 215 tracked Swift
  files. Its Swift sources contain 53,899 non-empty lines (`Length -gt 0`) and
  58,952 full physical lines.
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

Run `32171788727` completed successfully on `main` at
`280e5b3f8425f155d5e20a71841f4169a63bc59d` on 2026-08-18. Its recorded test
evidence is:

- Swift Core: `152/152`
- Hosted iOS: `166/166`
- XCUITest smoke: `2/2`
- Token Broker: `17/17`

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

### Reproduce The Audit-Baseline Counts

The following PowerShell command reads the named Git tree directly, so later
working-tree or `main` changes do not alter the result:

```powershell
$Revision = '280e5b3f8425f155d5e20a71841f4169a63bc59d'
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

Expected values are `334`, `215`, `53899`, and `58952`, respectively.

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
#35 / PR #38, the trusted CODEOWNERS bootstrap from PR #42, and the CI risk
lanes from Issue #39 / PR #40. PR #40 passed exact-head CI, Blocker 0 / Required
0 review, code-owner approval, and the post-merge exact-main gate above.

Issue #5 remains open and assigned to YZY. Its implementation is active in PR
#44 on `codex/5-reproducible-source-package-yzy1020`; that Pull Request owns the
source-package scripts and its listed documentation/tooling files until it is
integrated or handed off. The local finals baseline therefore remains a local
milestone while its overlapping documentation files wait for PR #44 to merge.

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

The open Issues carrying `blocked` are exactly:

- #10, AI request lifecycle behind a tested conversation session
- #11, bounded AI observation and on-demand conversation history
- #17, physical-device system acceptance matrix
- #18, Add Medication workflow ownership
- #19, Today dose lifecycle ownership
- #21, complete English product surfaces
- #22, bilingual Medication Assistant safeguards

Issue #1 is closed without `needs-product-decision`. Closed Issue #24 is a
milestone-free `duplicate` without `blocked`. Open Issue #25 carries the
evidence-backed `feature` type and has no invented priority or milestone.

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
- Consent revocation transactionality, persistent-store recovery, physical
  device evidence, locale-independent state, and measured performance remain
  tracked by Issues #12, #13, #17, #20, and #8/#11 respectively.
- These are product, medical, privacy, security, platform, and performance
  follow-ups. This governance change does not alter runtime behavior or claim
  that those risks are resolved.

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
