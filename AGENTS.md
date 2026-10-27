# MedCue Agent Working Agreement

This file is the entry point for repository-specific working rules. Read the
parts of the following sources relevant to the task; do not reload every
operational document for an unrelated small change:

- `CONTEXT.md`: product scope, domain language, and safety invariants.
- `docs/FINALS_PRODUCT_PLAN.md`: accepted milestones and ownership boundaries.
- `docs/PROJECT_STATUS.md`: revision-scoped engineering evidence.
- `docs/DEVELOPMENT_WORKFLOW.md`: delivery process and the complete autonomous
  merge gate; read it before a shared integration checkpoint.
- `docs/TOOLING_AND_PLUGIN_PLAN.md`: tools, skill applicability, and build-cache
  safety; read the relevant sections before tool setup or native validation.

## 1. Start With The Problem

Before editing code for any non-trivial request, turn the request into a clear
work item containing:

- the problem and affected user;
- the intended outcome;
- in-scope and out-of-scope behavior;
- observable acceptance criteria;
- applicable medical, privacy, data, performance, accessibility, platform,
  competition, and intellectual-property/dependency-license risks;
- the validation plan and any decision that only the product owner can make.

Keep this proportional to the change and reuse the active milestone or Issue.
A few sentences can be enough; do not create a new document or fill unrelated
risk categories just to complete a template.

Do not ask the product owner to rediscover facts that the repository, tests,
logs, or platform documentation can answer. Ask concise questions only when a
real product choice or unavailable external evidence changes the result.

## 2. Exercise Independent Engineering Judgment

The product owner may describe needs in everyday language and is not expected
to provide software terminology, repository facts, architecture, or a test
plan. The agent owns translating that direction into an evidence-based work
item and recommending the best-supported approach, not merely executing the
first proposed implementation.

- **Proceed directly** when repository evidence makes the intent and acceptance
  criteria clear, the work is reversible and within the requested scope, and it
  does not make a material product, medical, privacy, data-loss, cost, account,
  or release decision.
- **Align first** when ambiguity changes observable behavior or scope, viable
  options have materially different product consequences, required external
  evidence is unavailable, or the work spends money, changes public or medical
  claims, changes privacy behavior, migrates or destroys data, changes a release
  commitment, or requires account-owner action.
- **Challenge the approach** when evidence shows that the requested method is
  unsafe, incorrect, unnecessarily costly or complex, likely to regress quality,
  or materially weaker than an available alternative. Explain the evidence,
  product consequence, recommended path, and decision needed in plain language.
- **Stop or refuse** when proceeding would violate product safety, privacy, data
  integrity, authorization, repository policy, or honest evidence reporting.
  Never claim completion or suppress a known risk to satisfy the owner.
- Do not turn routine technical choices into owner decisions. Investigate first,
  follow established repository patterns, state consequential assumptions, and
  record adjacent work separately.

When repository files do not answer a technical question, continue with
relevant official documentation, safe diagnostics, or a focused experiment.
Distinguish a hypothesis from a verified fact; do not invent an existing API,
identifier, result, or product requirement. Ask the owner only when their
judgment or unavailable access is actually needed, and continue independent work.

The agent owns technical due diligence, implementation quality, and
recommendations. The product owner retains final authority over product value,
priority, intended experience, acceptable cost, privacy choices within the
product safety boundary, and release timing.

## 3. Use GitHub As The Work System

- Keep one locally owned finals milestone on one focused branch and verify it in
  small steps. Use GitHub Issues for remote ownership, durable/deferred backlog,
  bugs or debt that must outlive the milestone, and integration coordination.
- Use one focused branch per coherent local milestone and one Pull Request per
  coherent Issue. Branch from the authoritative, up-to-date `main` as
  `codex/<short-milestone>` before the GitHub checkpoint, or
  `codex/<issue-number>-<short-name>` when an Issue already exists.
- Do not push feature work directly to `main`.
- Before pushing for shared integration or opening a Pull Request, create or
  align one Issue, link the Pull Request to it, and keep scope changes visible.
- Require green relevant CI, a completed review checklist, and the approved
  autonomous-merge gate before merge.
- Record durable architecture decisions in `docs/adr/`; do not bury them in a
  chat or a daily log.
- Use `PROJECT_UPDATE_LOG.md` only as a historical journal. It is not the
  backlog or the current source of truth.

The unrelated Git histories documented in `docs/PROJECT_STATUS.md` were
reconciled through [Issue #1](https://github.com/Gavin8233841/medcue-ios/issues/1).
Start new feature work from the authoritative `main`, do not import raw
pre-normalization history, and never force-push over an active contributor.

## 4. Coordinate AI Work Deliberately

- At the start of a task or after context recovery, confirm the active local
  milestone and any linked Issue or Pull Request, branch and upstream, exact
  HEAD, working-tree status, and the applicable product and engineering truth
  documents.
- One coordinating agent owns scope, integration, and exceptions. Delegate only
  bounded work with explicit ownership; parallel writers may touch only disjoint
  files or separate worktrees. The author reviews delegated results and the
  complete cumulative diff. Once the autonomous merge gate is satisfied, the
  coordinator adds neither a routine second diff review nor a second approval.
- Medication-record, medical-AI, privacy, migration, authorization, and other
  safety-critical changes require an independent fresh-context review before a
  Pull Request is ready. Routine changes do not require a review committee.
- CI workflows, verification gates, release scans, and packaging scripts also
  require fresh-context security review because they define trusted evidence.
- A handoff records the exact revision, dirty files, completed evidence,
  blockers, and one next action. Shared remote state belongs in the Issue or
  Pull Request; accepted finals priority belongs in `docs/FINALS_PRODUCT_PLAN.md`,
  not in another permanent handoff or daily progress log.
- Skills, plugins, MCP results, model scores, and generated knowledge graphs are
  aids, not sources of truth. Verify consequential claims against the exact
  source revision, tests, official platform documentation, or external system.
  Use only relevant skills with verified prerequisites, following
  `docs/TOOLING_AND_PLUGIN_PLAN.md`; a skill cannot expand user authorization.

## 5. Report Progress Consistently

For substantive progress updates and final handoffs to the product owner, use
the following concise Chinese labels as the default reporting structure:

- `本次目标：`
- `已经证实：`
- `当前阻塞：`
- `需要你决定（无特大风险的已自行决策）：`
- `下一步：`
- `过程中产生的更多想法和可能优化点：`
- `对你的建议或意见：`
- `其他额外备注：`

Normally keep each included field to one or a few lines. Omit fields with no
material information instead of adding empty placeholders, and do not repeat
the same fact under multiple labels. Put urgent medical, privacy, data-loss,
security, cost, account, or release risks and owner decisions before routine
status when their urgency requires it. Keep the report in plain language and
explain an unfamiliar abbreviation on first use.

If this structure would hide an important risk, fragment reasoning, or otherwise
reduce answer quality, state the specific reason briefly before temporarily
using a more suitable format. Resume the standard structure when that reason no
longer applies.

## 6. Implement In Small Verified Steps

- Prefer existing domain modules, application commands, adapters, and test
  seams over new abstractions.
- Add an abstraction only when it reduces real complexity, protects an
  important product invariant, or matches an existing extension seam.
- File size and line count are regression signals, not proof of modularity. An
  architecture exit condition must address responsibility and state ownership,
  interface depth, observable behavior tests, and relevant measured performance.
- Test externally observable behavior, failure paths, ordering, idempotency,
  cancellation, and rollback. Avoid tests that merely mirror implementation.
- During native-code iteration, run focused tests and
  `tools/verify-native.sh --quick` when prerequisites are available. For other
  changes, use the relevant checks required by the delivery workflow. After
  checks pass, repeat or broaden them only for a new change, failure, unresolved
  concern, or required integration gate.
- Before a Pull Request is ready, run every relevant lane check plus the full
  `tools/verify-native.sh` gate for native/full-lane changes and every `main`
  push. Broker changes also require `node --test` in
  `cloudfunctions/medcue-ai-broker`.
- Performance claims require measurements from the relevant device and build
  configuration. Simulator impressions and source review are not measurements.
- A SwiftData write is complete only after an explicit successful commit.
  User-visible success and system side effects must follow that commit.

## 7. Preserve Product Safety

- MedCue supports medication organization and education. It does not diagnose,
  prescribe, or autonomously change medication or dosage.
- Keep the iPhone as the primary source of truth. Watch, Widget, notifications,
  and Live Activities consume controlled snapshots or committed actions.
- Cloud AI is opt-in and receives only explicitly authorized context.
- Never print, inspect unnecessarily, commit, package, or transmit secrets,
  tokens, user databases, GGUF models, device identifiers, or health content.
- Do not weaken consent, endpoint allowlists, response safety checks,
  transaction ordering, migration support, or release artifact scanning without
  an approved decision and regression coverage.

## 8. Keep The Repository Honest

- Preserve user changes and work safely in a dirty worktree.
- Never claim a test, build, deployment, device check, or submission succeeded
  without evidence from that exact artifact or revision.
- Update `docs/PROJECT_STATUS.md` when verified current truth changes.
- Update public README or privacy documentation when external behavior changes.
- Add an ADR only for a durable decision with meaningful alternatives.
- Do not commit caches, generated build products, credentials, local models,
  private device data, or contest media excluded by `.gitignore`.
- Surface newly discovered issues with evidence and severity. Record adjacent
  work as an Issue rather than silently expanding the active Pull Request.

## 9. Definition Of Done

Local work is complete when its requested outcome, relevant checks, and
required documentation are complete and any limitations are explicit. Local
completion does not claim a Pull Request is ready, merged, or released.
Integration additionally requires the Pull Request evidence, successful current
revision CI, and applicable device/account checks defined in
`docs/DEVELOPMENT_WORKFLOW.md`. A successful build alone is not done.
Applicable competition rules and intellectual-property/dependency-license
obligations are current release gates; commercial-production controls are not
unless the release scope changes.

When communicating with the product owner, explain an unfamiliar abbreviation
the first time it appears and translate engineering trade-offs into plain
product consequences.

## Autonomous Merge Gate

The complete, mandatory gate is defined only in
[`docs/DEVELOPMENT_WORKFLOW.md`](docs/DEVELOPMENT_WORKFLOW.md#autonomous-merge-gate).
Read and satisfy it before marking a Pull Request Ready or merging. It retains
cumulative self-review, Issue-specified fresh-context independent review,
resolution of all Blocker/Required findings, current-revision CI, current-main
integration, and required external evidence. A new tracked-file commit
invalidates prior review, approval, and CI; the workflow defines the stop
conditions and post-merge verification. This reference is not a waiver.

## Build-Cache Safety

Before native validation or cache operations, read the required prevention rules
and the preserved 2026-09-01 incident in
[`docs/TOOLING_AND_PLUGIN_PLAN.md`](docs/TOOLING_AND_PLUGIN_PLAN.md#agentic-coding-build-cache-safety-2026-09-01).
Never put source worktrees under `.codex-build`. Reuse one governed build-output
namespace per workline, retaining the existing `.codex-local` verification
exception. Preserve source, user changes, and required evidence. Cache cleanup
still requires explicit path-scoped owner confirmation; a model upgrade grants
no exception to these rules.
