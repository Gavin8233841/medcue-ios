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
- **Local milestone brief**: a compact description of one coherent local
  outcome, scope, acceptance criteria, evidence plan, ownership, and next gate.
  `FINALS_PRODUCT_PLAN.md` may own it; do not create a new file for every step.
- **Issue**: the GitHub work item that owns a requirement, bug, or technical
  debt item when remote coordination or durable backlog is needed.
- **Acceptance criteria**: observable conditions that must be true for the
  local milestone or Issue to be complete.
- **Implementation task plan**: an ordered breakdown that maps requirements and
  design decisions to implementation and verification work.
- **PR (Pull Request)**: the reviewable code and evidence proposed for merge.
- **CI (Continuous Integration)**: automated tests and builds run by GitHub for
  each Pull Request.
- **Integration checkpoint**: a coherent, locally verified revision worth
  pushing for review, collaboration, CI, or merge to `main`.
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
local specification or Issue/PRD, proposes alternatives, implements sufficiently
defined scope, adds tests, runs verification, prepares integration evidence,
and reports residual risk.
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
| Small, obvious local bug | Reproduction and acceptance criteria in the active local milestone; create an Issue if delegated, deferred, or needed as durable backlog |
| Routine locally owned feature | Concise PRD in the active local milestone; create or align an Issue before remote ownership or a Pull Request integration checkpoint |
| Cross-module or high-risk feature | Requirements, design, risk analysis, and tasks in a local spec; create or update an Issue before remote ownership or a shared high-risk integration checkpoint |
| Durable architecture/data/security decision | ADR after the decision is accepted |
| Technical debt | Evidence-based debt Issue with impact and an exit condition |
| Emergency release fix | Incident/bug Issue, narrow PR, explicit follow-up debt |

Do not create an ADR for a reversible implementation detail. Do not write a
multi-page PRD for a one-line correction. Use only applicable risk categories;
the lists below are prompts for judgment, not a requirement to fill empty
sections. A local read-only audit or documentation update can use a brief work
item in the task and local evidence without creating a new permanent plan.

## Scale The Process To Risk

Priority determines when work happens; risk determines how much evidence it
needs. Do not use a P0/P1 label as a substitute for a security-severity or
change-risk assessment.

| Change risk | Minimum control |
| --- | --- |
| Routine and reversible, with no observable behavior change | Keep the diff focused, use an existing aligned Issue/PR when available, and run relevant quick checks during iteration. No separate PRD is required; merge still requires exact-revision green CI. |
| Standard product behavior | Use a local milestone brief with acceptance criteria, a short branch, and focused tests; create or align an Issue before the Pull Request and relevant CI integration gate. |
| Safety-critical: medication records/actions, medical AI, privacy, security, migration, or trusted system entry points | Add failure, rollback, misuse, and data-integrity analysis; require complete relevant CI, fresh-context independent review, and device/account evidence where applicable. |
| External or difficult to reverse: history rewrite, data destruction, credential rotation, paid service, or release | Write the exact execution, verification, and rollback plan and obtain product-owner approval before the external action. |

For a new trust boundary, external input, credential, health-data flow, or
medication write path, answer four questions in the local specification and its
Issue before integration: what are we changing, what can go wrong, how is it
controlled, and how will the control be verified.
Do not require a full threat-model document for unrelated routine work.

## Delivery Flow

### 1. Intake and discovery

The agent restates the request as a user problem, checks the current source and
logs, identifies dependencies and risks, and asks only questions that change
product behavior. Newly discovered adjacent issues are recorded separately.

### 2. Definition of Ready

Implementation can start when the active local milestone or Issue has:

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
in the local specification, Issue, or a linked document:

- requirements define the intended behavior, scope, and acceptance criteria;
- design records boundaries, data and failure behavior, and alternatives only
  where they materially affect the result;
- tasks order the implementation and map each meaningful step to verification.

Scale all three layers to the change. A small bug or obvious correction may keep
them as a few Issue bullets and does not require separate documents.

#### User-interface copy and accessibility adaptation

- An elder or accessibility mode is a simplified task flow, not a uniformly
  enlarged copy of the complete interface. Keep semantic Dynamic Type support,
  reflow content at accessibility sizes, and remove nonessential hierarchy
  before adding more scale or more cards.
- User-visible copy communicates only the current task, user data, action,
  state, consequence, or a necessary recovery step. Do not expose design intent,
  implementation defaults, safety invariants, test assertions, or defensive
  programming explanations in the product interface.
- Text such as `现在只需处理一件事`, `无操作会保持未确认，不会自动记成忽略。`,
  and `这里不会推断为全部已服用` belongs in requirements or tests when needed,
  never in the interface. Preserve genuinely necessary medication, consent,
  error, and irreversible-action information at the point of decision.
- A user photo or other recognition aid supplements, but never replaces, a
  readable name and accessible text. Missing media falls back to a neutral
  visual without explanatory placeholder copy.
- Review the final string inventory and the same screen state at both the
  default and an accessibility content size. Do not compare screenshots from
  different device data, navigation states, or builds as if they were one
  responsive-layout result.

### 4. Branch and implementation

With the authoritative `main` established:

```text
main -> codex/<issue-number>-<short-name> or codex/<short-milestone>
     -> Issue integration checkpoint -> Pull Request -> main
```

Use short commits that each leave the branch understandable. Start with the
highest test seam that expresses user-visible behavior. Keep unrelated cleanup
out of the Pull Request.

### 5. Pull Request

Open a Draft Pull Request early for substantial shared or high-risk work. A
locally owned milestone may stay local until a coherent integration checkpoint.
At that checkpoint, create or align one Issue before pushing shared work. The
PR links its Issue, explains the solution and scope, maps
results to acceptance criteria, shows test/build/device evidence, and calls out
migrations, privacy changes, rollout, rollback, and remaining risk.

### Active work coordination

GitHub is the durable coordination record. Issue assignees and labels show who
owns active work, the Issue owns scope and decisions, and the Pull Request owns
the current implementation and verification evidence. Codex conversations and
local handoff files are not long-term coordination records. These are minimum
controls; an agent may add checks when the evidence or risk warrants them.

These coordination leases apply when work is remote, shared, deferred, or at an
integration checkpoint. They do not require a new Issue for every reversible
local step inside one already approved finals milestone. File-overlap checks and
the one-writer rule apply in both local and GitHub phases.

The `state:in-progress` label is a human work lease, not a technical lock.
Before editing, the contributor checks the Issue assignee, labels, latest
meaningful comments, current `main`, and the complete file lists of open Pull
Requests. The default boundary is one active writer per file. If an open Pull
Request already touches an intended file, stop and ask the coordinating agent
to record a serial integration order before editing. Use same-file parallelism
only as a narrow documented exception with disjoint sections and one named
integration owner.

To claim work:

1. Assign the Issue to one contributor and add `state:in-progress`.
2. Create a unique `codex/<issue-number>-<short-name>` branch from the current
   authoritative `main`.
3. Record the owner, branch, full base SHA, UTC start time, scope, exact intended
   files, and first check in one concise Issue comment.
4. Open a Draft Pull Request after the first coherent pushed checkpoint; open it
   earlier for high-risk work or known shared-file pressure.

If the scope or intended files expand, update the GitHub ownership record before
editing the new area. Keep `state:in-progress` while implementing or responding
to review, and use `已阻塞` only for a named dependency. A handoff records the
full base and HEAD SHAs, dirty files, pushed checkpoint, completed checks, open
Blocker/Required items, and one next action. Prefer a clean pushed checkpoint;
inaccessible dirty files do not authorize another agent to overwrite a worktree
or branch.

The contributor owns routine technical decisions, implementation, focused
checks, complete cumulative self-review, and current Pull Request body. Before
requesting formal review, use the strongest available model and reasoning
appropriate to the task risk, review the complete base-to-HEAD diff after the
last tracked-file change, and complete the Pull Request checklist. The current
HEAD must have successful relevant lane CI (and the full gate for native/full
changes and every main push), shared-file ownership must still be valid, and no
prior Blocker or Required item may remain open. Report unavailable checks and
reasoned N/A evidence without implying that missing evidence exists.

Revision invalidation is defined in the Autonomous Merge Gate below. Running,
queued, cancelled, failed, or old-SHA CI is not successful evidence.

When this author gate passes, post one `READY FOR REVIEW` status containing the
full base and HEAD SHAs, CI URL, limitations, and remaining independent-review
or device requirements. This status requests review; keep the Pull Request
Draft while required independent-review or device/account evidence is pending.
Mark it Ready and release `state:in-progress` only after the Autonomous Merge
Gate below is satisfied. If changes are requested, resume the active lease and
repeat the author gate after the last tracked-file change.

Contributors do not need to wake the coordinating agent for routine repository
research, implementation choices, tests, review fixes, or a completed
ready-for-review gate when the autonomous merge gate is satisfied. Wake the
coordinator only for unresolved ownership overlap, a material scope or
acceptance change, requirements that cannot be satisfied together, a handoff,
an unavailable permission or external dependency, or a high-risk exception
that the Issue/PR cannot resolve independently. Wake the product owner only
for product value or behavior, medical claims, privacy posture, cost, account
actions, release timing, or external/destructive choices.

The coordinating agent owns integration and exceptions, but does not provide a
second approval or routine cumulative-diff review when the autonomous merge
gate is satisfied. After merge, verify the exact `main` SHA and `main` CI,
confirm that shared-file integration preserved the intended behavior, close the
Issue, clear coordination labels, and remove the branch when safe. A merge
with failed or pending post-merge evidence is not complete.

### Autonomous Merge Gate

This is the complete repository definition of the gate referenced by
`AGENTS.md` and the Pull Request checklist. Local iteration and a review request
do not waive it.

After the last tracked-file change, the author must complete the cumulative
base-to-HEAD self-review, obtain a fresh-context independent review using the
Issue-specified model, and resolve every `Blocker` and `Required` finding. The
current HEAD must have successful exact-head relevant CI, a clean current-main
integration check, and all required device/account/external evidence (or a
reasoned `N/A` where the change cannot affect that boundary). The author may
mark the Pull Request Ready and squash merge without a second coordinator
approval only when all of those conditions and the Issue acceptance criteria
are satisfied. After merge, wait for and record the exact `main` CI result.

Every tracked-file commit invalidates prior review, approval, and CI evidence;
repeat the review and exact-head checks for the new SHA. Body-only Pull Request
edits do not invalidate code CI, but all revision and evidence references must
be rechecked.

Stop and wake the coordinator or product owner instead of merging when a
product, medical claim, privacy/consent, cost, account, credential, deployment,
legal, or release-time decision is unresolved; a destructive or hard-to-reverse
operation is requested; device, account, cloud, or other required external
evidence is missing; files overlap, scope materially expands, conflicts or
permissions block proof; a trusted CI, release-scan, packaging, permission, or
workflow rule is changed without Issue authorization; the specified model or
fresh-context review is unavailable; exact-head CI is not successful; or any
`Blocker`/`Required` finding remains. High-risk medication, medical-AI,
privacy, security, migration, authorization, and system-entry work is not
automatically prohibited, but it needs the approved scope plus its failure,
rollback, data-integrity, independent-review, and applicable device/account
evidence before this gate can pass.

### Controlled Demo builds

Use the shared `MedicationAdherenceApp-Demo` scheme only for an owner-controlled
MedCue demonstration device. Its `Demo` configuration inherits Release build
settings and adds `MEDCUE_DEMO` only to the main app target. It does not define
`DEBUG`, and the guarded build phase excludes `AISecrets.plist` from this
non-Debug artifact. The ordinary `MedicationAdherenceApp` Release path must not
show or execute the demo-data action.

The Demo scheme uses the same bundle identifiers as the ordinary app, so an
installation replaces the existing MedCue build on that device. Use a
controlled device without real medication or health data. On the first-launch
page, the `Demo` action replaces records already marked `isDemoContent`, keeps
non-demo records, writes the synthetic dataset, and exits successfully so the
app can reopen with a fresh model context. Relaunch, then finish or skip the
first-launch tour to view the data. The Help Center product tour exposes the
same refresh action in Debug and Demo builds.

This build path is not an App Store or ordinary Beta Release artifact. Do not
bundle credentials, local model files, user databases, device evidence, or
competition tooling/media with it.

### 6. Review and CI

#### Native Verification lanes

The Native Verification workflow validates the exact event base and checked-out
HEAD with full lowercase commit SHAs before selecting a lane. It covers the
complete changed-file set, including additions, modifications, deletions, and
renames. Missing or invalid inputs, unknown or mixed paths, workflow/tooling
changes, and classifier failures trigger a validated full-lane fallback. The
fallback re-derives the event base from trusted event context, rejects missing,
malformed, self-referential, or unavailable bases, and therefore cannot mask an
invalid input. The all-zero base is valid only for a new main push; every main
push uses the empty-tree SHA and the full Route A gate.

| Lane | Selection | Required checks |
| --- | --- | --- |
| Docs/governance | Every changed path is an approved documentation or governance path | Exact HEAD/base check, full diff whitespace check, and repository-structure check on Ubuntu |
| Broker-only | Every changed path is under cloudfunctions/medcue-ai-broker/ and is not workflow/tooling | Exact HEAD/base check, JavaScript syntax and JSON structure checks for existing changed files at any Broker depth, and Node 18.15.0 node --test on Ubuntu |
| Full Native Verification | Native, Watch, UI, project/package/configuration, trusted workflow/tooling, mixed, unknown, rename/deletion edge cases, or any main push | Exact HEAD/base check, Broker Node 18.15.0 tests, and the complete tools/verify-native.sh Route A gate on macOS |

Before this split, representative single-job Native Verification durations were
17:03 for a documentation/label main run, 19:03 for a governance Pull Request,
20:52 for a label-migration main run, 14:18 for another governance Pull Request,
and 13:49 for a Broker-only Pull Request. Issue #39 / PR #40 records two
exact-head docs probes at 4s and 7s, two Broker probes at 14s and 18s, and its
final full lane at 17:07. Those named runs are evidence only for their exact
revisions.

The workflow always publishes one Native Verification (required result)
aggregation job. It succeeds when classification succeeds and the selected lane
succeeds, or when classification fails but the validated full-lane fallback
succeeds; in either case all unselected lanes must be explicitly skipped. Runs
cancel obsolete work for the same event/ref; no result from an earlier SHA can
satisfy a later SHA. Pull Requests record actual selected-lane and full-lane
durations from their exact-head hosted runs; historical single-lane timing is
context, not a substitute for a new run. Because workflow files are trusted
evidence, any change under `.github/workflows/` remains a full-lane change and
requires fresh-context security review before approval.

At `main@d6aa4af85f225028fc3f912391328e1f745d0b34`, the active
`main-trusted-delivery` ruleset requires the Native Verification required
result, blocks branch deletion and force-push, and requires resolved review
threads. It does not require a Code Owner approval for every Pull Request;
contributors may use the autonomous-merge gate after their own cumulative and
fresh-context review. Base-branch `CODEOWNERS` remains an ownership signal for
protected files, and changes to workflows, release tooling, or other trusted
boundaries still require the risk-matched independent review and exact CI
evidence described above. Because a Pull Request can edit its own workflow
revision, the base-branch ruleset remains the trusted enforcement layer.

The agent performs a correctness, regression, privacy, medical-safety,
performance, accessibility, and test-quality review. `Native Verification`
must be green. A failure is investigated and fixed; it is never waived by a
claim that a local build worked.

Repository visibility, ruleset, CODEOWNERS, and required-check metadata must be
read back before a change relies on them. No direct `main` push and no merge
without the applicable green exact-head CI are allowed.

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

Prefer squash merge for one local milestone and its integration Issue -> one
coherent commit after review and CI are green. Remove a merged branch only
within existing owner authorization and after checking that no active work
depends on it; do not force-delete a branch or its worktree. Close the linked
Issue. User-visible release changes go into a release note/changelog;
durable decisions go into an
ADR; current engineering truth updates `docs/PROJECT_STATUS.md`.

## Session And Multi-Agent Harness

At task start or after context recovery, inspect the active local milestone and
any linked Issue/PR, exact branch and HEAD, upstream, `git status`, and current
truth documents before acting. A handoff states the exact revision, dirty files,
completed checks, open blockers, and one next action. Shared remote progress
belongs in GitHub; accepted finals priority belongs in
`FINALS_PRODUCT_PLAN.md`. Do not add a permanent daily progress log.

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

### Shared-file integration checkpoint on 2026-08-23

PR #26, #30, #31, #40, #43, and #44 are merged. PR #40 owns the Native
Verification lane and autonomous-merge rules now present in this file. The
finals baseline branch waited for PR #40 and merged exact
`main@c47416944790c5c4e7f1e3a03c4958473c1856fd` before adding local-milestone
rules, then merged Issue #23 / PR #43's exact
`main@15517b3649639539c05015970d2f6088df7426f9`, and finally merged Issue #5 /
PR #44's exact `main@d6aa4af85f225028fc3f912391328e1f745d0b34`.

Ownership rechecked on 2026-09-07: PR #48 is closed without merging. Issue #47 /
PR #49 continues source-package hardening as an open Draft Pull Request. Its
current files are `docs/SOURCE_PACKAGE_POLICY.md`, `docs/TEST_STRATEGY.md`,
`tools/build-source-package.py`, `tools/test-source-package.py`, and
`tools/verify-source-package.py`. Other documentation is not frozen by that
Pull Request. Read GitHub again before relying on this ownership snapshot.
Future same-file work must repeat the open Pull Request overlap check and review
the complete cumulative diff; a conflict-free merge alone is not evidence that
both rule sets survived.

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
- CI is green on the proposed integration revision; local intermediate commits
  carry the focused evidence defined by their milestone.
- Required device/account checks are recorded.
- Residual risk and follow-up plan items or Issues are explicit.
- No secrets, user data, generated caches, or unapproved assets are included.

## Minimal GitHub Organization

Create labels only when they become useful. The currently available vocabulary
is:

- type: `缺陷`, `功能`, `技术债务`, `文档`, `治理`
- priority: `P0`, `P1`, `P2`
- state: `需要产品决策`, `设备验证`, `已阻塞`
- coordination state: `state:in-progress`
- execution context: `execution:windows-capable`
- area: `平台`, `医疗 AI`, `隐私`, `发布`

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
- `docs/FINALS_PRODUCT_PLAN.md`: accepted finals focus, scope, milestones, and
  local/remote collaboration boundary.
- `docs/TOOLING_AND_PLUGIN_PLAN.md`: current workspace, Xcode, MCP, plugin, and
  local privacy boundary.
- `docs/PROJECT_STATUS.md`: one current verified engineering snapshot.
- GitHub Issues: remote ownership, durable backlog, bugs, and technical debt
  that must outlive the current local milestone.
- Pull Requests: implementation and verification evidence.
- `docs/adr/`: durable decisions.
- Removed daily logs and old handoffs: historical audit only; do not
  reconstruct them.

This structure replaces append-only vibe-coding logs with traceable decisions
without discarding their history.
