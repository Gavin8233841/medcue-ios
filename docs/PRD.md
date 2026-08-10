# MedCue product requirements

Status: current product scope for competition review and controlled physical-
device development. This document describes intended product behavior; source,
tests, and verification evidence determine what is implemented at a specific
revision.

## Product goal

Help a person organize a medication routine, record what happened, understand
their own adherence history, and prepare concise information for a clinician or
pharmacist follow-up.

MedCue is a medication organization and education tool. It does not diagnose,
prescribe, replace a clinician or pharmacist, or autonomously change a
medication or dosage.

## Primary users

- **Medication user:** manages medication profiles, schedules, reminders, dose
  events, stock estimates, and follow-up summaries.
- **Clinician or pharmacist:** receives information selected and shared by the
  user; does not operate MedCue as a clinical record system.
- **Product and engineering team:** uses the repository as the source of
  requirements, implementation evidence, and review history.

## In scope

1. Medication profiles, treatment periods, dose plans, reminder times, and
   inventory checkpoints.
2. Recording taken, delayed, skipped, corrected, reopened, and archived dose
   outcomes with an auditable history.
3. Today, records, calendar, adherence trends, risk review, and user-selected
   visit-summary export workflows.
4. iPhone-led notification, Live Activity, Apple Watch, and complication
   experiences using controlled snapshots and committed actions.
5. Optional HealthKit and weather signals as contextual information, not
   diagnosis or treatment advice.
6. Local OCR and barcode-assisted import only when the user reviews the result
   before it is persisted.
7. Optional local or cloud medical-assistant workflows with explicit consent,
   scoped context, transport validation, and response safety checks.

## Out of scope

- Diagnosis, prescribing, treatment selection, or autonomous dosage changes.
- A clinical record, clinician administration console, or emergency service.
- Treating HealthKit, weather, OCR, barcode, risk, trend, or AI output as an
  authoritative medical decision.
- App Store, TestFlight, commercial-production, or GitHub Actions distribution
  signing in the current development scope.

## Product invariants

- The iPhone is the primary source of medication truth.
- Persistence succeeds before success UI, notifications, Watch snapshots, or
  Live Activity completion.
- The same logical dose action remains idempotent across in-app and system
  entry points.
- Imported or recognized medication information is user-reviewed before it is
  saved.
- Cloud context sharing is opt-in, scoped, and revocable.
- AI output cannot create, stop, replace, or change medication or dosage.

## Observable acceptance criteria

- A user can create or edit a medication plan and see the resulting schedule
  reflected in the Today and records workflows.
- A dose action has one durable result and does not create duplicate history
  when the same logical action is delivered through more than one entry point.
- Watch and notification surfaces consume an iPhone-controlled snapshot and
  do not become an independent medication database.
- A failed save does not present a committed-success state or publish a
  post-commit system side effect.
- AI, import, HealthKit, and weather failures degrade safely without exposing
  credentials or presenting unsupported medical conclusions.
- The public repository can be cloned, its documentation navigated, and its
  unsigned verification path run without private certificates, tokens, model
  files, or user data.

## Decision ownership

The product owner decides user value, priority, intended experience, medical
claims, privacy posture, acceptable cost, and release timing. Engineering owns
the translation into source, tests, documentation, and evidence. A change that
affects medical safety, privacy, data integrity, or release claims requires an
explicit decision and regression evidence before it is treated as complete.
