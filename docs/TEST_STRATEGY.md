# MedCue Test Strategy

MedCue uses risk-based evidence. Test counts and coverage percentages are
diagnostic signals, not proof that a medication workflow is safe or complete.

## Evidence Layers

| Layer | Primary purpose |
| --- | --- |
| Swift Core tests | Portable domain rules, time boundaries, planning, trends, inventory, risk, and medical-response behavior |
| iOS hosted tests | SwiftData transactions, migration, rollback, idempotency, commands, projections, adapters, and failure paths |
| XCUITest | A small set of deterministic critical user journeys and process-recovery behavior |
| Broker Node tests | Authentication gates, endpoint policy, request/response limits, timeout, cancellation, and provider failure behavior |
| Preflight and build gates | Target/configuration integrity, source boundaries, Release products, privacy manifests, Watch embedding, and sensitive artifacts |
| Physical-device evidence | Notifications, Live Activities, permissions, Watch/Widget behavior, signing, lock state, performance, and memory |
| Account/operations evidence | CloudBase deployment, App Store Connect, capabilities, provider retention, credentials, and rollback readiness |

## Risk-To-Test Map

- Pure domain rule: start in Swift Core with boundary and counterexample tests.
- SwiftData write or migration: use hosted tests for commit, rollback, retry,
  idempotency, old-schema data, and post-commit side-effect suppression.
- View or user journey: test the highest deterministic interface first; use UI
  automation only for behavior that lower layers cannot prove.
- Notification, Live Activity, Watch, Widget, permission, or lock-state change:
  combine hosted adapter/command tests with a numbered physical-device script.
- External input or trust boundary: cover malformed, missing, substituted,
  expired, replayed, unauthorized, cancelled, oversized, redirected, and failed
  inputs. Safety-critical changes receive an independent fresh-context review.
- Medical AI prompt, routing, context, or response-policy change: cover refusal
  to diagnose/prescribe/change dosage, unsupported assertions, consent scope,
  timeout, cancellation, fallback, and persistence ordering.
- Performance or memory change: measure a Release build on a named physical
  device, OS, fixed sanitized dataset, exact SHA, and repeated scenario. Source
  review or simulator impression is not performance evidence.
- Packaging or release change: verify the exact source revision, manifest,
  archive contents, hash, prohibited artifacts, install/upgrade behavior, and
  rollback record.

## Pull Request Expectations

- During implementation, run the smallest focused tests and
  `tools/verify-native.sh --quick` that can fail for the change.
- Before readiness, run all focused tests plus the complete relevant native gate.
  Broker changes also require `node --test` in
  `cloudfunctions/medcue-ai-broker`.
- Record commands, result counts, exact head SHA, CI URL, device/account evidence,
  and any untested boundary in the Pull Request.
- Do not accept generated summaries, screenshots, model scores, or a successful
  build as substitutes for acceptance criteria and behavior evidence.

## Current Baseline And Known Limits

Exact current counts and dates live in `PROJECT_STATUS.md`. Current UI automation
only proves first launch and primary navigation; it does not yet cover the
critical medication journeys. CI disables the real local llama binary and tests
the stub path. These boundaries must remain visible in Pull Requests and release
claims.

Active delivery gaps belong in GitHub Issues rather than this durable strategy.
The current UI-journey, contest-package, and physical-device evidence work is
tracked in [Issue #7](https://github.com/Gavin8233841/medcue-ios/issues/7),
[Issue #5](https://github.com/Gavin8233841/medcue-ios/issues/5), and
[Issue #17](https://github.com/Gavin8233841/medcue-ios/issues/17). Performance
and memory evidence remains in
[Issue #8](https://github.com/Gavin8233841/medcue-ios/issues/8). Do not introduce
an arbitrary coverage threshold, every-screen UI automation, or a broader
device matrix until evidence shows that its benefit exceeds its maintenance
cost.
