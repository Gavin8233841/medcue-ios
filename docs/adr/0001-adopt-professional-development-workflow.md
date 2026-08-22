# ADR-0001: Adopt An Issue And Pull Request Driven Workflow

- Status: Accepted
- Date: 2026-08-04
- Decision owner: MedCue product owner

## Context

MedCue grew quickly through conversation-led, intuition-driven development.
Several rounds of architecture hardening improved the implementation, but
requirements, active work, technical decisions, verification evidence, and
release artifacts remained distributed across chats, giant logs, local files,
and multiple Git histories. The process no longer matched the product's size or
medical/privacy risk.

## Decision

MedCue will use a lightweight trunk-based workflow:

1. Material work starts with a GitHub Issue containing scope and acceptance
   criteria; meaningful features use a PRD in that Issue, and medium, large,
   cross-module, or high-risk changes add a risk-scaled design and implementation
   task plan in the Issue or a linked specification.
2. Work proceeds on one short-lived branch per coherent Issue.
3. Changes reach `main` through a Pull Request with automated and manual
   evidence.
4. CI, review, and required device verification form the merge gate.
5. ADRs record durable architecture decisions; GitHub Issues hold the active
   backlog; `docs/PROJECT_STATUS.md` holds current verified state.
6. Engineering agents proactively discover and report issues, but do not expand
   the active scope without making the change visible.

Before this workflow is used for feature delivery, the unrelated remote `main`
and working-branch histories must be normalized through a separately reviewed
operation tracked in
[GitHub Issue #1](https://github.com/Gavin8233841/medcue-ios/issues/1).

### Implementation note (2026-08-22)

Issue #1 fulfilled this prerequisite and established the authoritative `main`
without rewriting this historical decision. The current repository keeps the
sanitized archive/audit refs and does not restore raw pre-normalization history.
This note records the implementation state; it does not claim that prior
clones, caches, or provider retention copies were purged.

## Consequences

- Product intent and completion evidence become traceable.
- The product owner can describe needs naturally while the agent owns technical
  formalization and risk discovery.
- Changes may take a short specification step before coding, reducing rework and
  unreviewed scope growth.
- The current GitHub plan cannot enforce protected branches, so the PR rule is
  initially procedural unless the account is upgraded.
- Historical logs remain available but stop acting as the backlog.

## Rejected Alternatives

- Continue conversation-only development: fast locally, but no durable scope,
  review, or release evidence.
- Adopt a heavyweight enterprise framework: excessive for one product owner and
  engineering agents.
- Use long-lived feature branches or Git Flow: unnecessary coordination and
  integration cost for this team shape.
