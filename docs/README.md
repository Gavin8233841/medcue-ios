# MedCue Documentation Map

Use this index to avoid treating historical notes as current engineering truth.
When documents disagree, use the authority order below and verify consequential
claims against the exact source revision and tests.

## Authority Order

1. `../CONTEXT.md` for product context, current release scope, intended behavior,
   language, and safety invariants.
2. Source, tests, committed configuration, and exact-revision evidence for what
   the implementation actually does.
3. `PROJECT_STATUS.md` for current verified engineering state and top risks.
4. `ARCHITECTURE.md` and `TEST_STRATEGY.md` for intended engineering boundaries.
5. `DEVELOPMENT_WORKFLOW.md` and `../AGENTS.md` for delivery rules.
6. Accepted ADRs for specific durable decisions; reflect their consequences in
   `ARCHITECTURE.md` or `TEST_STRATEGY.md` when those boundaries change.
7. Operational references and historical evidence listed below.

Generated summaries, knowledge graphs, model evaluations, chats, and handoff
documents are navigation aids. They do not override the sources above.

## Current Documents

| Document | Purpose |
| --- | --- |
| `PROJECT_STATUS.md` | Current verified baseline, blockers, debt, and owner decisions |
| `ARCHITECTURE.md` | Module, state, persistence, platform, and trust boundaries |
| `TEST_STRATEGY.md` | Risk-to-evidence map and verification expectations |
| `DEVELOPMENT_WORKFLOW.md` | Issue, branch, Pull Request, CI, review, and release flow |
| `adr/` | Accepted durable decisions and their consequences |
| `../CONTEXT.md` | Product context, current release scope, actors, terms, invariants, and platform roles |
| `../AGENTS.md` | Short repository-wide rules for engineering agents |

## Operational References

- `13-iphone-signing-and-live-activity-test.md`: legacy physical-device script;
  use its scenarios, but record evidence in the active Pull Request against an
  exact revision.
- `24-privacy-data-flow-audit-20260727.md`: detailed privacy audit evidence;
  `PROJECT_STATUS.md` owns the current conclusion when facts change.
- `25-token-broker-deployment-prerequisites-20260727.md`: Broker deployment and
  account prerequisites; verify live CloudBase state before operating it.
- `openai-image-local-api.md`: local image-generation helper instructions.
- `watchos-support/README.md`: historical Watch implementation and device evidence;
  revalidate its steps against `PROJECT_STATUS.md` and the current project.

## Historical Evidence

The numbered planning, strategy, snapshot, hardening, dependency-map, and
architecture documents that remain tracked from `01-...` through `25-...` are
retained for audit and context. They are not an active backlog and may contain
statements that were current only when written.

`11-development-todo.md` is a frozen historical record. The repository does not
contain `../PROJECT_UPDATE_LOG.md`, the removed Watch handoff/devlog files, or
privacy-removed migration assets and placeholders. These absent materials are
not current evidence and must not be reconstructed from guessed or raw inputs.
New work belongs in GitHub Issues; verification and review evidence belongs in
Pull Requests; durable decisions belong in ADRs.

## Maintenance Rule

Update a current document only when its owned truth changes. Link to existing
evidence instead of copying status across several files. Add a new permanent
document only when it has one clear owner and prevents repeated mistakes.
