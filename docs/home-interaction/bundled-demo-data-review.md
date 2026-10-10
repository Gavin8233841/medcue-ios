# Isolated bundled demo: data slice review

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

Historical scope: commits `implementation-stage-10` and `implementation-stage-11`, before UI wiring. The subsequent
coordinator-authorized wiring is reviewed separately in `bundled-demo-wiring-review.md`.

Base `implementation-stage-09`; independent branch
`unpublished-implementation-branch`. **Not an activated demo launch build.**
App startup and all home/UI files remain byte-identical to the fixed Mac snapshot.
The proposed launch flag currently has no startup routing; do not use it as an
isolation guarantee until the protected routing and bounded UI slice are reviewed.

## Implemented

- Simulator `DEBUG || MEDCUE_DEMO` factory, private initializer, own UUID store
  directory, separate preference suite, ready manifest and persisted clock.
  Reject malformed/conflicting requests, unknown/incomplete sessions, incompatible
  manifests and symbolic links; no primary opener, reset, deletion or process exit.
- Fresh seed requires a factory-owned session plus empty checks for all eleven
  schema entities. Existing five-drug definitions, label text and historical
  status rules are reused without changing drug guidance or risk-engine behavior.
  One reference date/calendar drives tasks and D3 cutoff; creation/import/review/
  stock/change metadata use the same instant. New strict reads throw; legacy
  entry conditions and best-effort fetch behavior remain. Legacy source text,
  delete/rebuild/exit functions are unchanged and are not called by this factory.
- Save precedes full first-seed validation and ready publication. Validation
  checks five IDs, five related plans/labels/stocks, exactly 305 associated tasks
  across 61 days, expected dose/status/time/unit, one D3 change and expected risk
  identities. A preparing session is never automatically repaired or reseeded.
- Ready reopen preserves task/stock/preference edits and manifest clock, without
  running the seed. Ownership identity is checked without normalizing records.
  Changed calendar/time zone fails before opening the owned store; tests also
  feed the shared calendar/clock to the actual Today projection to check all five
  current-day tasks. This does not prove later UI clock wiring.
- One new app source, exactly four additive PBX lines/two IDs. No project build
  settings or test registration changes; existing test directory is synchronized.

## Evidence and limits

`git diff --check` passed. Thirty-one static scope assertions passed, including
frozen App, Root, home, container and schema files, exact old source and remove/rebuild
paths, strict read plumbing, debug/simulator gates, precise PBX registration and
unchanged clean Mac candidate. Result is retained outside the repository as the
separate `issue163-bundled-demo-review/static-scope.json` evidence file.

Ten hosted test methods were added for source identity/associations, retained
edits on restart, midnight/DST, factory-level primary/preferences sentinel,
seed/save/publication failure, double seed, unknown directories, symlink redirect
and source-version mismatch. These tests are **not run**: Linux has no Swift or
Xcode. Injected failure is not an actual corrupt-store read or disk-write test.
Ordinary legacy seeder regression tests must also run after this refactoring.
SQLite support-directory handling and Swift 6 compilation require native proof.

The ten tests cannot prove App routing or real-service isolation: App startup
is intentionally unchanged. Existing full tabs, help rebuild, detail/edit,
notification Settings links and archive Live Activity paths must not be exposed
by the later demo host until narrowly gated. No visible marker/exit UI is wired.
No whole-demo acceptance, native build, hosted/UI pass, performance measurement,
primary-startup sentinel pass or Release build is claimed.

## Required next review and integration boundary

Coordinator reviews the exact initialization exception and bounded UI proposal
in `bundled-demo-plan.md` before those protected/frozen files are edited. This
medication-data/PBX slice also needs independent fresh-context review. Keep the
Mac `implementation-stage-09` run fixed; integrate only after it ends. Do not replace its current
retained evidence  or merge/push this branch as part of that run.
