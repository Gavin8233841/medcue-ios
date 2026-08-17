# MedCue Project Status

Last audited: 2026-08-17
Working branch: `codex/main-current-progress`
Implementation baseline commit: `REDACTED_HEX40`
Runtime checkpoint immediately before this governance commit:
`REDACTED_HEX40` (`Stabilize reminder reconciliation
reference time`). The final governance commit will have a new exact HEAD and
must be revalidated independently; this line is historical checkpoint context,
not the final release SHA.

This is the single current engineering-status document. GitHub Issues already
hold active work; ordinary branch and Pull Request delivery begins after
repository history is normalized. Older TODO files, handoffs, and
`PROJECT_UPDATE_LOG.md` are historical evidence, not the active backlog.

## Executive Summary

MedCue has a strong native product and engineering base: portable domain logic,
explicit SwiftData transactions, schema migration, multi-device integration,
medical-response safeguards, a constrained Token Broker, and substantial
automated coverage. The July architecture work materially reduced the largest
View files; the product owner reported a substantial improvement after retesting
one previously affected medication-plan-save path on a physical iPhone.

The immediate workflow blocker is governance: GitHub does not yet represent one
authoritative history. Application responsibility, measured performance, and
release security still contain material work and must not be hidden behind the
governance progress.

## Current Delivery Checkpoints

First establish one authoritative `main`. Delivery then proceeds through two
bounded GitHub Milestones:

1. [Controlled-device Beta hardening](https://github.com/Gavin8233841/medcue-ios/milestone/1)
   closes the current medication-action, Broker, capability-honesty,
   cancellation, critical-journey, and physical-device evidence gaps.
2. [Competition source re-evaluation vNext](https://github.com/Gavin8233841/medcue-ios/milestone/2)
   completes the scoped AI architecture and observation work, then produces a
   reproducible source checkpoint from an exact reviewed revision.

Neither checkpoint claims App Store or commercial-production readiness.

## Verified Baseline

- The implementation baseline contains 348 tracked files, including 214 Swift
  files and 58,836 tracked Swift lines. The current P0 work adds documentation
  and GitHub templates, exact CI-parity fixes from the old remote lineage, and
  stronger committed-diff verification. Its pre-commit full-gate run also
  exposed wall-clock drift in reminder reconciliation, so the working tree now
  includes a captured operation-time fix and behavior tests. This is a
  runtime-source correction and requires new exact-revision evidence.
- Six Xcode targets: iOS app, Live Activity extension, Watch app, Watch widget,
  hosted unit tests, and UI tests.
- Swift 6.0 project language mode; iOS 17.0 and watchOS 10.0 deployment targets.
- The 2026-07-28 local full gate for the implementation lineage recorded Swift
  Core `152/152`, iOS hosted tests `165/165`, XCUITest smoke `2/2`, and Broker
  tests `17/17`.
- GitHub Actions run `30330080655` passed on the unrelated old remote `main` on
  2026-07-28 and recorded `148/148` hosted tests. It does not verify the current
  implementation branch.
- On 2026-08-04 the staged governance tree passed the non-build gate with zero
  warnings and Broker `17/17` using the bundled Node.js runtime. This is
  pre-commit evidence, not an exact-revision result. The checkpoint's exact-SHA
  full CI evidence is recorded in Issue #1 only after the Gate 1 sanitized
  preparation ref is pushed, so no raw identifier-bearing tip is published.
- On 2026-08-07 four focused reminder-command/coordinator suites passed 14 tests
  after the operation-time correction. These are local worktree results; the
  full native gate and exact-head CI remain required on the final sanitized
  revision.
- The user verified the previously reported medication-plan-save frame drops
  were substantially improved on a physical iPhone and verified the Broker path
  with a non-medical request.
- Full evaluation source package:
  `artifacts/MedCue-source-final-evaluation-20260728-2055-v11.zip`, SHA-256
  `db4b7cdb1e0bfecfbf3df8fa78376cc0770c438f8952bc90d2e8a3dc3a05f3de`.

The package is intact and contains no audio, video, unapproved external contest
media, secrets, local models, or databases. It does contain tracked historical
screenshots and App/Watch icon PNGs. Its latest privacy text and package hash
were recorded in two legitimate but previously uncommitted documentation
changes, so it was not fully reproducible from the prior commit alone.

## What Is In Good Shape

- Domain logic is separated into `swift-core` and has broad behavior coverage.
- Most critical writes use application commands, explicit commit/rollback, and
  post-commit side effects.
- Versioned SwiftData schemas and migration tests exist.
- A persistence integrity auditor checks manual UUID references.
- iPhone remains the primary source of truth for Watch, Widget, notifications,
  and Live Activities.
- AI consent, scoped context, endpoint allowlists, no-redirect iOS online
  transport, response safety checks, Keychain storage, release scanning, and the
  Broker form a credible controlled-competition/device-Beta safety posture.
- The original 2,200-6,000 line entry Views have been materially decomposed at
  the file level; state and workflow ownership still needs further migration.
  `LocalMedicalAIClient` is now 195 lines and delegates response policy and model
  runtime concerns. The 1,400-line source-size regression gate passes.
- CI executes Core, Broker, iOS, Watch, privacy, and sensitive-artifact checks.

## P0 Governance Risks

### 1. GitHub has two unrelated histories across three published branches

Remote `main` is `f4f9c9c9`; the authoritative implementation baseline on
`codex/main-current-progress` is `712f41f0`. The current governance work builds
on that baseline. `git merge-base` finds no common ancestor. The remote default
branch contains an earlier packaged-source lineage, while the working branch
contains later module splits, tests, and internal evidence. A normal merge or
rebase is not safe.

The remote also publishes `codex/docs-and-signing` at `e75127d0`, a direct
child of the old `main` with 15 documentation/governance files. It preserves
useful work but also keeps the old ancestors reachable in an ordinary clone.
There are currently three remote branch tips and no tags. Normalization must
therefore preserve and sanitize the old-main tree, the authoritative target
tree, and the docs/signing tree; checking only `main` and the target branch is
insufficient.

On 2026-08-15 authenticated repository metadata and an unauthenticated fetch
both proved that the repository is public, contrary to the earlier private-plan
assumption. No forks are currently reported, but all three affected heads can be
fetched without credentials. Making the repository private is the immediate
containment recommendation and requires explicit product-owner approval. Ref
sanitization prevents future ordinary clones from reaching the affected objects;
it does not prove that GitHub caches, platform retention, or prior clones have
been purged. If complete removal is required, follow GitHub's sensitive-data
removal/support process after the refs are contained.

Both lineages also have reachable historical records containing persistent
physical-device identifiers; the implementation lineage additionally contains
personal device labels and user-specific absolute paths. Removing those values
only from the current tree would leave them reachable through ancestors and a
full clone. Issue #1 must therefore use two explicit approval gates: first
authorize an isolated, reproducible sanitization of both affected histories and
publish the three resulting tips only on new non-destructive preparation refs;
only then request approval to create a privacy-safe archive and update each
existing branch with its own exact lease. No identifier value belongs in the
Issue, CI logs, or validation report.

Before feature development resumes, preserve the old `main` with an explicit
archive reference, choose the working branch as the authoritative content, and
perform a reviewed history-normalization operation. This requires product-owner
approval because it changes the remote default branch history. The exact scope,
acceptance criteria, and safety hold are tracked in
[GitHub Issue #1](https://github.com/Gavin8233841/medcue-ios/issues/1).

The archive ref name remains
`refs/tags/archive/main-before-history-normalization-issue-1`, but its object is
not yet approved. The recommended archive target is a sanitized old-lineage SHA
that preserves the old tip tree without retaining identifier-bearing ancestors;
the current remote old-main SHA remains the exact `main` lease precondition. The
target and docs/signing branches retain independent exact lease preconditions.
An archive directly targeting the current old-main commit would keep the privacy
risk reachable and cannot satisfy the fresh-clone privacy acceptance criteria.

After any remote write with an ambiguous network result, do not retry blindly:
query the exact refs read-only. An archive equal to the approved sanitized-old
SHA is success; an absent archive with unchanged `main` is a stopped,
non-applied state; any other value is a conflict. A `main` ref equal to the
approved sanitized target continues to acceptance, the unchanged old-main SHA
is a stopped, non-applied state, and any third SHA is a conflict. If fresh-clone
or final exact-head CI acceptance fails, rollback restores the approved
sanitized old lineage with the reverse explicit lease
`--force-with-lease=refs/heads/main:<approved-sanitized-target-sha>`. The target
and docs/signing branches remain sanitized and must never be rolled back to their
identifier-bearing tips; any unexpected movement of any published ref stops
rollback for renewed review. Final fresh-clone acceptance inventories and scans
every remote head and tag, not only the default branch.

### 2. GitHub is not yet the work system

- Twenty-three Issues are open: one P0 governance blocker, seventeen P1 blockers
  for their named checkpoint, and five P2 architecture/performance items. Two GitHub
  Milestones separate controlled-device Beta hardening from competition source
  re-evaluation; Pull Requests, releases, and tags remain at zero.
- The current working commit has no GitHub Check Run.
- All existing CI runs were triggered by direct pushes to `main`.
- The repository is currently public and must not be described as private.
  Branch-protection/ruleset capability and cost must be re-audited after the
  visibility decision; the earlier private-plan upgrade result is stale.
- GitHub CLI authorization, the repository-local HTTPS credential helper,
  branch upstream, and future GitHub-linked commit identity are verified. The
  CLI executable is not yet on the shell `PATH`, and the obsolete global helper
  remains workstation maintenance outside this repository.
- The small project label set now supports feature, technical debt, governance,
  P0/P1/P2, product decision, blocked work, AI, privacy, platform, release, and
  device validation without introducing a large process taxonomy.

These facts do not invalidate the code, but they prevent a reviewable,
repeatable delivery process.

### 3. Current facts are fragmented

`PROJECT_UPDATE_LOG.md` is over 3,800 lines and `docs/11-development-todo.md` is
over 2,300 lines. Both contain many historical statements described as "current".
Several module READMEs and deployment prerequisites still report older test
counts, toolchains, or a pre-Broker architecture. They remain useful history
but must not guide new work without checking this status page and source.

## Release-Blocking Product Security Risk

The custom Live Activity URL accepts a task ID and action while treating
`operationID` and `expiresAt` as optional. `AppRootView.onOpenURL` forwards a
parsed request to the dose-action write path, which supplies fallback values and
can commit taken, delayed, or skipped state. A custom URL can be opened by
another process. Exploitation is not a blind write: another process would first
need a valid, still-actionable high-entropy task UUID. If it obtains one, however,
it does not need the original operation ID or expiry and can change medication
reminder state without in-app confirmation. There is no evidence this has been
exploited. The integrity impact is high while blind discovery likelihood is low;
the release-blocking engineering priority is P1, while the current
security-severity assessment is Medium. The route must fail closed before
release. The exact scope and acceptance criteria are tracked in
[GitHub Issue #2](https://github.com/Gavin8233841/medcue-ios/issues/2), blocked by
the authoritative-history work in Issue #1.

## P1 Engineering Risks

- The settings privacy screen revokes AI consent with a direct model mutation
  and generic save helper instead of the existing transactional conversation
  command. It needs one consistent write path and failure behavior
  ([Issue #12](https://github.com/Gavin8233841/medcue-ios/issues/12)).
- Local streaming cancellation ends the outer conversation task but does not
  currently propagate into the underlying llama token loop. The loop and stream
  ownership need cancellation coverage before long-running local inference is
  treated as bounded
  ([Issue #6](https://github.com/Gavin8233841/medcue-ios/issues/6)).
- There is no checked-in physical-device performance baseline, launch metric,
  memory budget, or regression threshold. Existing signposts cover only selected
  plan and visit-summary paths
  ([Issue #8](https://github.com/Gavin8233841/medcue-ios/issues/8)).
- XCUITest currently proves first launch and primary navigation, not the complete
  create-plan, record-dose, correction, migration, Watch, notification, Broker,
  or consent-revocation journeys
  ([Issue #7](https://github.com/Gavin8233841/medcue-ios/issues/7)).
- Persistent-store recovery lacks a complete read-only export, diagnostic, retry,
  and user-confirmed rebuild experience
  ([Issue #13](https://github.com/Gavin8233841/medcue-ios/issues/13)).
- Real-device coverage remains incomplete for permissions, AlarmKit,
  notification delivery, Live Activity process states, Watch disconnect/rejoin,
  Widget refresh, and the earlier unconfirmed memory termination report
  ([Issue #17](https://github.com/Gavin8233841/medcue-ios/issues/17)).
- Localized display text still participates in persisted and cross-process
  control state. Locale-independent semantics and legacy compatibility must be
  established before translation
  ([Issue #20](https://github.com/Gavin8233841/medcue-ios/issues/20)).
- English product surfaces remain incomplete across all four bundles, and the
  medical assistant's English/mixed-language safeguards are not yet equivalent
  to its Chinese boundary
  ([Issues #21](https://github.com/Gavin8233841/medcue-ios/issues/21) and
  [#22](https://github.com/Gavin8233841/medcue-ios/issues/22)).

## P1 Security And Release Risks

- Broker startup does not currently reject a missing client-token configuration.
  The request check compares against `Bearer ${config.clientToken}`, so a
  malformed `Bearer REDACTED_SECRET` request can cross that first gate when the
  environment is incomplete. The deployed environment is configured, but the
  implementation must fail closed at startup and have a regression test
  ([Issue #3](https://github.com/Gavin8233841/medcue-ios/issues/3)).
- The deployed Broker's static client token is not user/device identity. A
  commercial release needs App Attest/DeviceCheck or equivalent identity,
  short-lived credentials, per-subject quotas, revocation, and durable abuse
  controls.
- The Broker uses the default upstream redirect behavior, has no explicit
  provider-response byte limit, and is deployed on the end-of-life Node.js 18.15
  runtime. These must be closed before a production security claim.
- The DEBUG reminder/Live Activity smoke path logs medication-related identifiers
  and display text, while the Broker idempotency cache can retain complete prompt
  and answer entries beyond its declared expiry until the same key is read again.
  Logging must be content-free and cache expiry/capacity must be actively bounded
  ([Issue #23](https://github.com/Gavin8233841/medcue-ios/issues/23)).
- Release endpoint policy still permits explicitly configured direct Doubao and
  Baichuan adapters. Commercial distribution should compile out provider-master
  key paths and make the Broker the only cloud adapter.
- iPhone notifications and Live Activities can show medication and dose details
  on the lock screen, and system-surface dose actions do not require unlocking.
  A product decision and default privacy policy are required for the controlled
  device checkpoint
  ([Issue #14](https://github.com/Gavin8233841/medcue-ios/issues/14)).
- The account screen exposes Sign in with Apple and an automatic iCloud-backup
  preference. The production container uses SwiftData's default initializer, so
  the SDK selects its automatic CloudKit behavior; only the explicit test-store
  path uses `.none`. The preference itself is AppStorage/UI state and does not
  implement backup. The target has neither iCloud nor Sign in with Apple
  entitlement and has no verified backup, restore, conflict, deletion, or
  encryption behavior. The UI must not imply these capabilities currently
  protect records
  ([Issue #4](https://github.com/Gavin8233841/medcue-ios/issues/4)).
- WeatherKit is called from the app, but no WeatherKit entitlement is present.
  Account and weather UI must be aligned with capabilities and device evidence.
- Exported visit-summary PDFs need an explicit temporary-file protection,
  expiration, share-completion cleanup, and failure-cleanup policy
  ([Issue #15](https://github.com/Gavin8233841/medcue-ios/issues/15)).
- Third-party retention settings require account-owner verification for the
  controlled Beta. App Store Connect privacy answers become required only if
  App Store distribution enters the release scope.
- The writable GitHub deploy key and its private key remain in an ignored backup
  directory. Normal GitHub CLI/HTTPS access is now established. Confirm that no
  external deployment still depends on the key, revoke it, and remove the
  ignored private key through a separately approved cleanup task
  ([Issue #16](https://github.com/Gavin8233841/medcue-ios/issues/16)).
- Generated Chrome profiles under ignored `.codex-local` contain browser state
  and must never enter an archive or source package.
- Source-package generation is not scripted or tied to a commit. The later
  root-layout competition package is a partial review export, not a complete
  repository snapshot
  ([Issue #5](https://github.com/Gavin8233841/medcue-ios/issues/5)).
- The repository has no current authoritative dependency, license, and
  attribution inventory. The historical open-source reference log is evidence,
  not a complete current manifest. Competition packaging must identify exact
  obligations and include required notices
  ([Issue #5](https://github.com/Gavin8233841/medcue-ios/issues/5)).
- The ignored `llama.xcframework` installer pins a release tag but does not
  verify the downloaded archive's digest or signature. Commercial release needs
  the additional software bill of materials (SBOM), binary provenance, and a
  reproducible path from source revision to shipped binary.
- The current GitHub Action is pinned to a full commit SHA, but dependency
  update automation and broader security scanning are not configured.

## P2 Architecture And Product Engineering Gaps

- `AIAssistantView` still owns seven observed model collections, multiple
  persisted preferences, request tasks, image recognition, consent, recovery,
  and transport orchestration. Existing application modules reduced risk but
  the screen remains a broad invalidation and lifecycle surface
  ([Issue #10](https://github.com/Gavin8233841/medcue-ios/issues/10)).
- `AddMedicationView` still owns more than forty local state values plus camera,
  OCR/barcode, permissions, photo, save, and reminder flows
  ([Issue #18](https://github.com/Gavin8233841/medcue-ios/issues/18)).
- `TodayView` still owns substantial feedback and task lifecycle state after its
  domain projection and system synchronization were extracted
  ([Issue #19](https://github.com/Gavin8233841/medcue-ios/issues/19)).
- `LocalMedicalResponsePolicy` concentrates response rules outside the client,
  but callers still coordinate several ordered policy steps and no direct policy
  behavior tests were found. Its interface depth needs review, not line-count
  driven splitting
  ([Issue #9](https://github.com/Gavin8233841/medcue-ios/issues/9)).
- Visit-summary data performs six SwiftData fetches on `@MainActor`, and
  `RecordsView` synchronously rebuilds render state when its revision changes.
  These are measured-audit targets, not established causes of the earlier hitch.
- Every visited primary Tab remains retained for responsiveness, AI observes the
  full stored conversation, and the local-model runtime recreates model context
  per request. Their memory and latency trade-offs have no device budget yet;
  measurement must precede pagination, unloading, or runtime reuse changes
  ([Issues #8](https://github.com/Gavin8233841/medcue-ios/issues/8) and
  [#11](https://github.com/Gavin8233841/medcue-ios/issues/11)).

- Only five checked-in `#Preview` declarations were found, and there is no
  visual-regression harness.
- Accessibility labels are widespread, but stable identifiers and automated
  navigation do not yet cover the critical medication write journeys.

## Asset And Documentation State

- Source and machine-enforced checks are tracked in Git.
- Contest media, official documents, generated outputs, source ZIPs, backups,
  local models, credentials, and caches are intentionally ignored by exact
  repository patterns; newly introduced asset roots must be checked before any
  explicit staging operation.
- Ignored local data currently occupies several gigabytes across generated
  reports, browser profiles, Xcode/Swift caches, artifacts, and backups. No
  cleanup is authorized by this audit.
- Twenty-one tracked `IMG_*.png` files are historical screenshots/source-delivery
  evidence, not compiled App assets. Preserve them until a dedicated asset
  migration with a manifest is approved.
- The authoritative submitted PDF and portal receipt cannot be proven from the
  current local `outputs` directory; multiple files are named "final".

## Next Stage Order

1. Complete the local governance/runtime checkpoint and current-tree
   redaction, but do not push a new commit on either identifier-bearing lineage.
2. Obtain the first Issue #1 approval for isolated history sanitization, push
   the sanitized old-main, target, and docs/signing results only to three new
   preparation refs, and run `Native Verification` on the exact target head
   against the sanitized old-main base.
3. Request the second Issue #1 approval with all three sanitized SHAs, CI run,
   archive, three existing-branch leases, complete remote-ref inventory,
   fresh-clone plan, and rollback facts; only then execute normalization.
4. Start the first independent post-normalization work with Broker fail-closed
   (#3), AI consent transactionality (#12), and dose-action authorization (#2).
5. Resolve the approved capability-honesty decisions and remaining release
   blockers before performance-driven refactoring.
6. Work through the prioritized GitHub backlog using Issue -> branch -> Pull
   Request -> CI for every material change.
7. Establish measured physical-device performance and memory baselines in
   [Issue #8](https://github.com/Gavin8233841/medcue-ios/issues/8).
8. Deepen the AI session, medication creation/import, and Today dose-action
   modules with focused behavior tests, one Issue and Pull Request at a time.
9. Expand critical end-to-end tests and the real-device system matrix.
10. Close production identity, privacy, store-recovery, reproducible packaging,
   and release operations before describing the product as commercial-ready.

## Product-Owner Decisions Still Required

- Immediately approve making `Gavin8233841/medcue-ios` private to contain public
  access while the affected refs are sanitized. This does not replace either
  history-normalization approval gate.
- First approve isolated sanitization of both identifier-bearing histories and
  all three published branch tips; then approve the exact archive, three branch
  leases, remote-history normalization, and rollback plan in GitHub Issue #1
  before any existing remote ref is rewritten.
- After containment, decide whether paid branch-protection features are worth
  the cost based on a new capability check. They are not a prerequisite for
  adopting Pull Requests immediately.
- Decide the default Lock Screen medication-detail visibility and whether dose
  actions may occur without unlocking.
- Decide whether iCloud backup, Sign in with Apple, and WeatherKit will be fully
  implemented and verified or hidden until they are truthful capabilities.
- After dependency checks, approve revocation of the obsolete writable deploy
  key and separately approve explicit single-file cleanup of its ignored private
  key material.
- Verify provider retention settings for the controlled Beta and perform
  numbered physical-device acceptance scripts supplied by engineering. If App
  Store distribution enters scope, verify App Store Connect privacy answers
  before that release. Natural-language experience reports are sufficient for
  product acceptance; performance claims require measured evidence.
- Confirm product choices involving medical claims, privacy, external cost, and
  release scope. Engineering discovery, specifications, implementation, tests,
  and risk reporting remain the agent's responsibility.
