# MedCue development workflow

MedCue uses an Issue -> focused branch -> pull request -> CI workflow. The
workflow keeps product decisions, implementation, and verification evidence
reviewable without mixing unrelated work.

## Before editing

1. Identify the user or engineering problem and intended outcome.
2. State in-scope and out-of-scope behavior.
3. Define observable acceptance criteria.
4. Check medical, privacy, data, accessibility, performance, platform,
   competition, and dependency-license risks.
5. Decide which evidence must come from tests, a physical device, Apple
   Developer account state, or another external system.

## Branch and pull request

- Start from the authoritative, up-to-date `main` after checking its history
  and working-tree state.
- Use one focused branch per coherent Issue, normally
  `codex/<issue-number>-<short-name>`.
- Do not push feature work directly to `main`.
- Keep functional code, documentation, and generated review material separated
  when their ownership or release path differs.
- Link the pull request to its Issue and include exact acceptance evidence,
  residual risk, rollback notes, and pending physical-device/account checks.

## Review levels

- **Routine:** focused tests and the relevant native gate.
- **Standard:** design, failure-path tests, native gate, and pull-request
  review.
- **Safety-critical:** fresh-context independent review for medication records,
  medical AI, privacy, migrations, authorization, or system-surface actions.
- **CI or release gate:** fresh-context security review because the workflow
  defines trusted evidence.

## Documentation ownership

- Product intent and non-goals: `docs/PRD.md`.
- Boundaries and state ownership: `docs/ARCHITECTURE.md`.
- Tests and evidence: `docs/TEST_STRATEGY.md` and the pull request.
- Durable alternatives and decisions: `docs/adr/`.
- Historical notes: dated documents under `docs/`, clearly marked as history.
- Current source behavior: source, tests, committed configuration, and exact
  verification output.

## Definition of done

A change is complete only when acceptance criteria are met, relevant tests and
native verification pass, public documentation is current, no secret or user
data is included, and required device/account evidence is either complete or
explicitly recorded as pending. App Store, TestFlight, and commercial release
steps are outside the current scope unless separately approved.
