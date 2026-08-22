# MedCue Development Workflow

This is a lightweight professional workflow for one product owner working with
engineering agents. It keeps the controls that prevent expensive mistakes
without copying a large company's approval bureaucracy.

## Terms In Plain Language

- **Product brief**: a short statement of the user problem, target user, value,
  and success signal.
- **PRD (Product Requirements Document)**: product requirements document. It
  defines the problem, behavior, scope, user stories, acceptance criteria, and
  non-functional requirements for a meaningful feature.
- **RFC (Request for Comments)**: a design proposal used when several technical
  approaches need comparison before implementation.
- **ADR (Architecture Decision Record)**: a short permanent record of an
  important architecture decision, its alternatives, and consequences.
- **Issue**: the GitHub work item that owns a requirement, bug, or technical
  debt item.
- **Acceptance criteria**: observable conditions that must be true for the Issue
  to be complete.
- **Implementation task plan**: an ordered breakdown that maps requirements and
  design decisions to implementation and verification work.
- **PR (Pull Request)**: the reviewable code and evidence proposed for merge.
- **CI (Continuous Integration)**: automated tests and builds run by GitHub for
  each Pull Request.
- **Definition of Ready**: the minimum clarity required before implementation.
- **Definition of Done**: the evidence required before work is truly complete.

## Roles

### Product owner

Within MedCue's safety, evidence, privacy, and legal constraints, the product
owner decides priority, intended user experience, product scope, acceptable
cost, and release timing. Natural-language descriptions are sufficient; the
engineering agent must translate them into a professional specification and
explain any decision in plain language. The owner is not expected to prescribe
architecture, APIs, test strategy, or implementation details. Product choices
remain theirs; routine technical choices belong to the agent.

### Engineering agent

The agent investigates repository facts, identifies hidden risks, drafts the
Issue/PRD, proposes alternatives, implements sufficiently defined scope, adds
tests, runs verification, prepares the Pull Request, and reports residual risk.
It must challenge a materially worse approach with evidence and a concrete
alternative rather than optimize for agreement. It must identify any requested
medical claim or privacy choice that crosses the product's safety, evidence,
privacy, or legal constraints, and must not silently invent product behavior or
hide uncertainty.

The owner supplies direction and product judgment; the agent supplies
specification, technical judgment, evidence, and execution. Neither side
silently decides the other's material choices.

### Automated and manual evidence

CI proves repeatable software checks. Physical iPhone/Watch behavior, Apple
account settings, CloudBase operations, and visual quality require explicit
owner/device evidence when automation cannot reach them. App Store Connect
answers require that evidence only if App Store distribution enters scope.

## Choose The Smallest Useful Specification

| Change | Required artifact |
| --- | --- |
| Small, obvious bug | Bug Issue with reproduction and acceptance criteria |
| Routine feature | Feature Issue containing a concise PRD |
| Cross-module or high-risk feature | Requirements, design, and implementation task plan in the Issue or a linked spec; expand the design into an RFC only when alternatives matter |
| Durable architecture/data/security decision | ADR after the decision is accepted |
| Technical debt | Evidence-based debt Issue with impact and an exit condition |
| Emergency release fix | Incident/bug Issue, narrow PR, explicit follow-up debt |

Do not create an ADR for a reversible implementation detail. Do not write a
multi-page PRD for a one-line correction.

## Scale The Process To Risk

Priority determines when work happens; risk determines how much evidence it
needs. Do not use a P0/P1 label as a substitute for a security-severity or
change-risk assessment.

| Change risk | Minimum control |
| --- | --- |
| Routine and reversible, with no observable behavior change | Keep the diff focused, use an existing aligned Issue/PR when available, and run relevant quick checks during iteration. No separate PRD is required; merge still requires exact-revision green CI. |
| Standard product behavior | Use an Issue with acceptance criteria, a short branch and Pull Request, focused tests, and the full relevant CI gate. |
| Safety-critical: medication records/actions, medical AI, privacy, security, migration, or trusted system entry points | Add failure, rollback, misuse, and data-integrity analysis; require complete relevant CI, fresh-context independent review, and device/account evidence where applicable. |
| External or difficult to reverse: history rewrite, data destruction, credential rotation, paid service, or release | Write the exact execution, verification, and rollback plan and obtain product-owner approval before the external action. |

For a new trust boundary, external input, credential, health-data flow, or
medication write path, answer four questions in the Issue: what are we changing,
what can go wrong, how is it controlled, and how will the control be verified.
Do not require a full threat-model document for unrelated routine work.

## Delivery Flow

### 1. Intake and discovery

The agent restates the request as a user problem, checks the current source and
logs, identifies dependencies and risks, and asks only questions that change
product behavior. Newly discovered adjacent issues are recorded separately.

### 2. Definition of Ready

Implementation can start when the Issue has:

- a clear problem and intended outcome;
- scope and non-goals;
- observable acceptance criteria;
- product decisions resolved or explicitly deferred;
- medical, privacy, data, accessibility, performance, platform, competition,
  and intellectual-property/dependency-license impact;
- a test/verification plan;
- a priority and owner.

### 3. Design and task breakdown

For medium, large, cross-module, or high-risk work, keep three auditable layers
in the Issue or a linked specification:

- requirements define the intended behavior, scope, and acceptance criteria;
- design records boundaries, data and failure behavior, and alternatives only
  where they materially affect the result;
- tasks order the implementation and map each meaningful step to verification.

Scale all three layers to the change. A small bug or obvious correction may keep
them as a few Issue bullets and does not require separate documents.

### 4. Branch and implementation

With the authoritative `main` established:

```text
main -> codex/<issue-number>-<short-name> -> Pull Request -> main
```

Use short commits that each leave the branch understandable. Start with the
highest test seam that expresses user-visible behavior. Keep unrelated cleanup
out of the Pull Request.

### 5. Pull Request

Open a Draft Pull Request early for substantial work. The PR must link its
Issue, explain the solution and scope, map results to acceptance criteria, show
test/build/device evidence, and call out migrations, privacy changes, rollout,
rollback, and remaining risk.

### 6. Review and CI

The agent performs a correctness, regression, privacy, medical-safety,
performance, accessibility, and test-quality review. `Native Verification`
must be green. A failure is investigated and fixed; it is never waived by a
claim that a local build worked.

Repository visibility and branch-protection capabilities are verified against
current GitHub metadata before they are described here. Until an approved
ruleset is confirmed on the authoritative repository, this workflow is
enforced manually: no direct `main` push and no merge without green CI.

Classify review feedback so that review improves quality without chasing
perfection:

- **Blocker**: acceptance, correctness, safety, privacy, medical, data, or CI
  failure; it must be resolved before merge.
- **Required**: evidenced maintenance, test, documentation, or operability
  regression; it must be resolved or the scope must be changed explicitly.
- **Suggestion**: a useful improvement that does not block this change; record
  it separately when it is worth doing.
- **Question**: clarification needed to understand the change; it is not itself
  a defect.

### 7. Device acceptance

When platform behavior matters, the PR contains a short numbered test script.
The product owner reports the device, OS/build, steps, result, and relevant
observation. A subjective impression is recorded as such; a performance claim
requires a measurement.

### 8. Merge and release record

Prefer squash merge for one Issue -> one coherent commit after review and CI
are green. Delete merged branches. Close the linked Issue. User-visible
release changes go into a release note/changelog; durable decisions go into an
ADR; current engineering truth updates `docs/PROJECT_STATUS.md`.

## Session And Multi-Agent Harness

At task start or after context recovery, inspect the linked Issue/PR, exact
branch and HEAD, upstream, `git status`, and the current truth documents before
acting. A handoff must state the exact revision, dirty files, completed checks,
open blockers, and one next action. Persistent progress belongs in GitHub; use a
redacted ignored temporary handoff only when no suitable Issue or PR exists.

One coordinating agent owns scope and integration. Parallel work is appropriate
for bounded read-only investigation, testing, or explicitly disjoint files and
worktrees. Shared files have one writer; child-agent conclusions are evidence to
review, not text to concatenate blindly. High-risk changes receive an independent
review from a fresh context; ordinary changes do not require multiple-model
consensus.

Skills, plugins, connectors, and knowledge graphs accelerate discovery but do
not override source, tests, official documentation, or exact-revision evidence.
A generated graph must identify the revision and exclusions it represents. Keep
large generated graph artifacts local and ignored; rebuild them when useful, not
as a mandatory Pull Request gate.

## Definition Of Done

- Acceptance criteria are met and demonstrated.
- Focused tests and the full relevant quality gate pass.
- Failure, cancellation, rollback, migration, and idempotency paths are covered
  where applicable.
- Privacy, medical safety, accessibility, localization, and performance impacts
  are addressed.
- Applicable competition, intellectual-property, dependency-license, and
  attribution obligations are addressed.
- Documentation and operational steps are current.
- CI is green on the proposed revision.
- Required device/account checks are recorded.
- Residual risk and follow-up Issues are explicit.
- No secrets, user data, generated caches, or unapproved assets are included.

## Minimal GitHub Organization

Create labels only when they become useful. The currently available vocabulary
is:

- type: `bug`, `feature`, `technical-debt`, `documentation`, `governance`
- priority: `P0`, `P1`, `P2`
- state: `needs-product-decision`, `device-validation`, `blocked`
- area: `platform`, `ai`, `privacy`, `release`

Create `P3`, `ready`, and additional area labels only when the first real Issue
needs them; do not prebuild a large taxonomy.

Priority semantics:

- `P0`: blocks all safe delivery until resolved;
- `P1`: blocks the target release or milestone but not unrelated work;
- `P2`: important work to schedule soon;
- `P3`: evidence-backed longer-term improvement.

Use milestones for a concrete release or contest checkpoint, not as permanent
categories. Add GitHub Projects only when the Issue backlog is large enough to
benefit from a board.

## Documentation Ownership

- `README.md`: public product and build entry point.
- `CONTEXT.md`: product context, current release scope, language, and invariants.
- `docs/PROJECT_STATUS.md`: one current verified engineering snapshot.
- GitHub Issues: active requirements, bugs, and technical debt.
- Pull Requests: implementation and verification evidence.
- `docs/adr/`: durable decisions.
- `PROJECT_UPDATE_LOG.md` and old handoffs: historical audit only.

This structure replaces append-only vibe-coding logs with traceable decisions
without discarding their history.
