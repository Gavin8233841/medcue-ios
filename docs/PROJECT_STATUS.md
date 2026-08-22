# MedCue Project Status

Last audited: 2026-08-22
Authoritative branch: `main`
Authoritative revision: `280e5b3f8425f155d5e20a71841f4169a63bc59d`
Exact-head CI: [Native Verification run 32171788727](https://github.com/Gavin8233841/medcue-ios/actions/runs/32171788727)

This is the single current engineering-status document. GitHub Issues hold the
active backlog, Pull Requests hold implementation and review evidence, and
accepted ADRs hold durable decisions. Historical notes and local files do not
override the exact repository revision or GitHub evidence.

## Current Verified Snapshot

- `main` is the repository default branch and is synchronized with the exact
  revision above.
- The repository is private. This records current GitHub visibility only; it
  does not claim that previous clones, caches, or provider retention have been
  purged.
- The canonical history-normalization prerequisite in [Issue #1](https://github.com/Gavin8233841/medcue-ios/issues/1)
  is complete. The sanitized lineage and the current tree are preserved by the
  published archive and audit/preparation refs listed below.
- The current tree contains 334 tracked files, 215 tracked Swift files, and
  53,899 tracked Swift lines (`git ls-files` plus line counting at the exact
  revision).
- The project contains six Xcode targets: the iOS app, Live Activity extension,
  Watch app, Watch widget, hosted unit tests, and UI tests.
- The project uses Swift 6.0 language mode with iOS 17.0 and watchOS 10.0
  deployment targets.

## Exact-Revision Evidence

Run `32171788727` completed successfully on `main` at
`280e5b3f8425f155d5e20a71841f4169a63bc59d` on 2026-08-18. Its recorded test
evidence is:

- Swift Core: `152/152`
- Hosted iOS: `166/166`
- XCUITest smoke: `2/2`
- Token Broker: `17/17`

This evidence is exact-head CI evidence for the canonical `main`. It does not
certify physical-device behavior, Apple account configuration, provider
retention, App Store Connect answers, or commercial-production readiness.

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

The repository now uses the Issue -> branch -> Pull Request -> CI workflow.
Open work remains in the GitHub backlog; normalization is no longer a delivery
blocker. Draft PR #30 owns the active-work coordination additions in
`.github/pull_request_template.md` and its new coordination section in
`docs/DEVELOPMENT_WORKFLOW.md`. Draft PR #26 owns the controlled-demo build
changes. Neither PR is modified by this Issue.

The open Issues carrying `blocked` are exactly:

- #10, AI request lifecycle behind a tested conversation session
- #11, bounded AI observation and on-demand conversation history
- #17, physical-device system acceptance matrix
- #18, Add Medication workflow ownership
- #19, Today dose lifecycle ownership
- #21, complete English product surfaces
- #22, bilingual Medication Assistant safeguards
- #23, health-content retention and logging boundaries; its current dependency
  is open Issue #3, not completed Issue #1

Issue #1 is closed without `needs-product-decision`. Closed Issue #24 is a
milestone-free `duplicate` without `blocked`. Open Issue #25 carries the
evidence-backed `feature` type and has no invented priority or milestone.

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

## Next Stage

1. Review and merge the focused governance PR after exact-head CI and review.
2. Keep the canonical `main` as the only feature-delivery starting point; do
   not import raw pre-normalization history or rewrite refs.
3. Work through the remaining GitHub Issues one focused branch and Pull Request
   at a time, with macOS/Xcode, device, account, and provider checks recorded
   where Windows cannot provide them.
4. Do not describe the competition/Beta scope as App Store, clinical, or
   commercial-production ready without the corresponding evidence.
