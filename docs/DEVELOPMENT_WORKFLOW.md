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

### Active work coordination

GitHub is the durable coordination record. Issue assignees and labels show who
owns active work, the Issue owns scope and decisions, and the Pull Request owns
the current implementation and verification evidence. Codex conversations and
local handoff files are not long-term coordination records. These are minimum
controls; an agent may add checks when the evidence or risk warrants them.

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

Any tracked-file commit invalidates the prior author self-review and requires
new exact-head CI; it also invalidates an earlier approval. A body-only Pull
Request edit does not invalidate code CI, but the contributor must recheck every
revision and evidence reference. Running, queued, cancelled, failed, or old-SHA
CI is not successful evidence.

When this author gate passes, post one `READY FOR REVIEW` status containing the
full base and HEAD SHAs, CI URL, limitations, and remaining independent-review
or device requirements; then mark the Pull Request ready and remove
`state:in-progress`. If changes are requested, resume the active lease and repeat
the author gate after the last tracked-file change.

Contributors do not need to wake the coordinating agent for routine repository
research, implementation choices, tests, or review fixes. Wake the coordinator
for unresolved ownership overlap, a material scope or acceptance change,
requirements that cannot be satisfied together, a handoff, an unavailable
permission or external dependency, or a completed ready-for-review gate. Wake
the product owner only for product value or behavior, medical claims, privacy
posture, cost, account actions, release timing, or external/destructive choices.

The coordinating agent reviews the current cumulative HEAD, scope, and
integration evidence, but does not provide a second approval when the
autonomous merge gate is satisfied. After merge, verify the exact `main` SHA and `main` CI, confirm that
shared-file integration preserved the intended behavior, close the Issue, clear
coordination labels, and remove the branch when safe. A merge with failed or
pending post-merge evidence is not complete.

The approved autonomous merge gate permits the author to mark the Pull Request
Ready and squash merge without a second coordinator approval after the
cumulative self-review, Issue-specified fresh-context review, Blocker 0 /
Required 0, successful exact-head relevant CI, clean current-main integration,
and required device/account/external evidence or reasoned N/A are complete.
Every tracked-file commit invalidates prior review, approval, and CI evidence;
repeat the gate for the new HEAD. Stop and wake the coordinator or product
owner for unresolved product, medical, privacy/consent, cost, account,
credential, deployment, legal, or release decisions; hard-to-reverse actions;
missing required external evidence; overlap, scope expansion, conflict,
permission failure, or unauthorized trusted CI/release/packaging/permission
changes; unavailable specified model or fresh context; unsuccessful exact-head
CI; or any remaining Blocker or Required finding. High-risk work remains
eligible when its approved scope and additional failure, rollback,
data-integrity, independent-review, and applicable device/account evidence are
complete.

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
and 13:49 for a Broker-only Pull Request. The Issue #39 Pull Request records
the new exact-head docs, Broker, and full-lane durations after they complete;
these historical values are not reused as evidence.

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

Pull Request #42 established a `.github/CODEOWNERS` trusted-ownership root:
changes under `.github/` and `tools/` require review by a maintainer other
than the author, and the two active maintainers provide reciprocal coverage.
Verified against the GitHub API on 2026-08-23, the repository still has no
enforced branch-protection ruleset on `main`. A `pull_request` workflow is
therefore evaluated from the PR merge revision, so the static guard is not an
independently base-trusted security boundary. Until an approved ruleset is
confirmed on the authoritative repository, the workflow is enforced manually:
no direct `main` push and no merge without green CI. Fresh-context review of
workflow changes remains necessary and does not substitute for that
enforcement.

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

### Shared-file ownership recorded on 2026-08-23

The 2026-08-22 Draft Pull Request trio recorded below has merged into `main`
(#26, #30, #31), so its per-PR section ownership is closed and retained as
historical integration evidence only.

The active shared-file ownership snapshot, verified against open Pull Requests
on 2026-08-23:

- PR #49 (Issue #47, source-package hardening, branch
  `codex/47-source-package-hardening-main-yzy1020`) owns
  `docs/SOURCE_PACKAGE_POLICY.md`, `docs/TEST_STRATEGY.md`,
  `tools/build-source-package.py`, `tools/test-source-package.py`, and
  `tools/verify-source-package.py`. Any other work needing those files
  integrates serially after PR #49. Its predecessor PR #48 was closed
  unmerged on 2026-08-23 and no longer holds any file ownership.
- The Issue #45 finals-baseline documentation set is disjoint from that list:
  `docs/FINALS_PRODUCT_PLAN.md`, `docs/PROJECT_STATUS.md`,
  `docs/DEVELOPMENT_WORKFLOW.md`, `docs/adr/0002-xcode-27-native-mcp-toolchain.md`,
  `docs/26-agent-chat-experience-uplift-plan-20260823.md`, and
  `docs/27-catpaw-parallel-collaboration-prompt-20260823.md`.

Historical record from 2026-08-22 (all three Pull Requests merged):

- PR #31 replaced only two fulfilled history-normalization prerequisites in the
  pre-existing branch and merge guidance.
- PR #30 added the Active work coordination protocol and its label vocabulary;
  it also changed `.github/pull_request_template.md`.
- PR #26 added the Controlled Demo build workflow in this file and changed the
  Demo app, scheme, project, tests, and preflight implementation.

Whenever multiple Pull Requests touch this file, each remaining Pull Request
must rebase or reapply its owned change, inspect the complete cumulative file
diff, and rerun exact-head CI before merge. A conflict-free merge alone does
not prove that all owned sections were preserved.

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
- `docs/PROJECT_STATUS.md`: one current verified engineering snapshot.
- GitHub Issues: active requirements, bugs, and technical debt.
- Pull Requests: implementation and verification evidence.
- `docs/adr/`: durable decisions.
- `PROJECT_UPDATE_LOG.md` and old handoffs: historical audit only.

This structure replaces append-only vibe-coding logs with traceable decisions
without discarding their history.
