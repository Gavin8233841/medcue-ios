# MedCue Architecture

This document records intended engineering boundaries. Product language and
invariants remain authoritative in `../CONTEXT.md`; verified implementation gaps
remain in `PROJECT_STATUS.md`.

## System Shape

```text
complete experience       elder-friendly experience (planned)
          \                 /
           shared user intents and render projections
                         |
application commands and sessions
        |
SwiftData persistence + Apple platform adapters
        |
portable rules in swift-core

iPhone committed state
        |
controlled snapshots/actions
        +-- Watch and Watch Widget
        +-- notifications
        +-- Live Activities

MedicalAIClient seam
        +-- on-device model adapter
        +-- constrained cloud adapters, including the CloudBase Broker
```

## Product Experience Boundary

- The complete and elder-friendly experiences are two presentations of the
  same committed medication state. They must not fork medication, plan,
  dose-task, or action-log models into separate truth stores.
- Both experiences invoke the same tested application command for the same
  logical action. A different label, layout, or amount of detail cannot create
  different persistence or idempotency semantics.
- The elder-friendly experience is planned work, not a currently verified
  runtime capability. Its initial action set is taken, remind later, and request
  help. Intentional skip, reason entry, correction, and detailed review remain
  available through the complete experience.
- A missing action remains unconfirmed. Notification expiry, app termination,
  or process restart cannot silently convert it to intentional skip or taken.
- Same-device family-assisted setup may configure a phone number for an explicit
  system call. There is no remote family identity, Contacts upload, remote plan
  mutation, or clinician backend in the current architecture.

## Module Responsibilities

- `swift-core/` owns portable medication scheduling, adherence, inventory,
  trends, label interpretation, risk rules, and medical-response safety logic.
  It must not depend on SwiftUI, SwiftData, ActivityKit, WatchConnectivity, or
  network transport.
- `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/` owns rendering,
  experience selection, accessibility, navigation, and short-lived presentation
  state. A View should express user intent, not own a multi-step persistence or
  transport protocol.
- Application commands and session modules own validation, transaction order,
  idempotency, rollback, cancellation, and post-commit coordination.
- SwiftData models and persistence adapters own durable iPhone state. Manual UUID
  references are audited because the store does not enforce all relationships.
- Apple platform adapters own notifications, ActivityKit, HealthKit, WeatherKit,
  WatchConnectivity, Keychain, photos, and other framework-specific behavior.
- Watch, Widget, notifications, and Live Activities consume controlled snapshots
  or validated actions. They do not establish a second medication truth store.
- `MedicalAIClient` is the transport/runtime seam. Consent, authorized context,
  medical-response policy, and persistence order remain explicit application
  concerns regardless of which adapter answers.
- `cloudfunctions/medcue-ai-broker/` constrains cloud-model access. Its static
  client token is an access gate for controlled testing, not production identity.

## State And Write Boundaries

1. The iPhone SwiftData store is the primary source of medication truth.
2. A write validates the requested transition and logical-dose grouping before
   mutation.
3. All related model mutations commit explicitly or roll back together.
4. Success UI and external side effects occur only after a successful commit.
5. Retries use stable idempotency semantics and must not append duplicate action
   logs or repeat a logical dose transition.
6. Absence of a committed action preserves an unconfirmed task; expiry and
   restart behavior must be explicit and testable.
7. External inputs are untrusted until a documented trust boundary validates
   provenance, scope, expiry, action, and replay behavior.

## Dependency And Ownership Rules

- Prefer one directional dependency from presentation into application
  interfaces, then into persistence/platform adapters and portable domain rules.
- Do not move a broad group of View state into another type unless the new type
  hides lifecycle complexity behind a smaller state-and-intent interface and has
  behavior tests.
- Do not duplicate parsing, medical policy, transaction ordering, or source
  metadata conventions across Views and services.
- Add an abstraction when it protects a real invariant, reduces real complexity,
  or supports an established adapter seam. File count alone is not a reason.
- Keep system-framework types at adapter boundaries; pass stable IDs or
  explicitly sendable value projections across concurrency boundaries.

## Trust Boundaries

- Imported OCR, barcode, label, and image-derived medication data requires user
  review before persistence.
- Cloud AI receives only opted-in, explicitly scoped context. Revocation must
  follow the same transactional command path as other conversation persistence;
  the current settings-screen gap is tracked in
  [Issue #12](https://github.com/Gavin8233841/medcue-ios/issues/12).
- Custom URLs, App Intents, notifications, Live Activities, Watch messages, and
  web responses are external inputs. Each entry point must fail closed and reach
  the same validated command boundary.
- A future child or clinician surface is a new identity and data-sharing trust
  boundary. It requires an approved design for authentication, consent,
  revocation, least-privilege projections, audit, retention, and conflict
  handling before implementation.
- Secrets remain outside source, logs, packages, model prompts, and health data.
  Provider master credentials must not become production client credentials.

## Architecture Change Standard

An architecture change is complete only when responsibility and state ownership
are narrower, the public interface hides more complexity than it exposes,
observable behavior and failure paths are tested, and any performance claim is
measured on the relevant build and device. Source line limits are useful alerts,
not completion evidence.

Record a new ADR only for a durable decision with meaningful alternatives, such
as a new persistence model, cross-entry-point trust mechanism, or cloud identity
architecture.
