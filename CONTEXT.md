# 产品上下文与发布范围（Product Context and Release Scope）

## Product

MedCue is a native iPhone and Apple Watch medication-management product. It
helps a person maintain a medication plan, handle scheduled doses, review
adherence and supply, inspect medication risks, and prepare concise follow-up
information for a clinician or pharmacist.

MedCue is not a diagnostic, prescribing, or autonomous treatment system.

## Current Release Scope / 当前发布范围

The current release target is student-competition review plus controlled
physical-device demonstration and Beta testing. MedCue does not claim App Store,
commercial, or clinical-production readiness at this stage.

Commercial-production hardening is a future trigger, not part of the current
definition of done, unless an already identified high risk affects competition
users, their data, or the honesty of product claims. Competition rules,
intellectual-property and dependency-license obligations, baseline medication
safety, privacy, and data integrity remain mandatory now.

## Primary Actors

- **Medication user**: records and reviews their own medication routine.
- **Clinician or pharmacist**: receives user-selected follow-up information but
  does not operate the app as a clinical record system.
- **Product owner**: decides user value, priority, intended behavior, medical
  claims, privacy posture, cost, and release scope.
- **Engineering agent**: converts product intent into specifications, code,
  tests, review evidence, and proactively reported risks.

## Domain Terms

- **Medication**: a user-managed medicine profile, including identity,
  lifecycle state, source, photo, and optional package metadata.
- **Medication plan**: the intended course dates, dose, delivery method, and
  reminder schedule for one medication.
- **Dose task**: one scheduled opportunity to take or use a medication.
- **Logical dose group**: task records that represent the same intended dose and
  must be handled consistently across app and system surfaces.
- **Dose action log**: the durable audit record for taken, delayed, skipped,
  corrected, reopened, or archived dose behavior.
- **Medication label**: user-reviewed source text from a label, instruction, OCR,
  or barcode-assisted import.
- **Risk card**: a traceable, non-diagnostic warning derived from available
  medication information and user-confirmed context.
- **Medication stock**: the user's latest physical quantity checkpoint and a
  non-authoritative consumption projection.
- **Visit summary**: a user-selected snapshot for follow-up communication; it is
  not a medical record or diagnosis.
- **AI context scope**: the explicit categories of local data a user authorizes
  for one online medical-assistant workflow.

## Invariants

1. The iPhone is the primary source of medication truth.
2. Persistence succeeds before success UI, notifications, Watch snapshots, or
   Live Activity completion.
3. The same logical dose action is idempotent across in-app, notification, and
   Live Activity entry points.
4. Imported or recognized medication information is reviewed by the user before
   persistence.
5. AI output cannot create, stop, replace, or change medication or dosage.
6. HealthKit and weather signals provide context only and are not interpreted as
   diagnosis, efficacy, or prescribing advice.
7. Cloud context sharing is opt-in, scoped, and revocable.

## Platform Roles

- `swift-core/`: portable domain rules and calculations.
- iOS app: SwiftUI presentation, SwiftData persistence, application commands,
  and platform adapters.
- Apple Watch and Widget: focused display and low-risk interaction using iPhone
  snapshots.
- Notifications and Live Activities: system entry points that must preserve the
  same committed action semantics.
- CloudBase Broker: constrained cloud-AI adapter; the current static client
  token is suitable for controlled competition and device-Beta testing, not
  production user or device identity.
