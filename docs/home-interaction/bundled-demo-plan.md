# Isolated historical five-drug demo slice

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

Base: `implementation-stage-09`, branch
`unpublished-implementation-branch`. The Mac validation source snapshot stays on its fixed
snapshot; this branch is not integrated, pushed or released during that run.

Current status: the data slice received independent source review; the
coordinator authorized narrow startup/Today wiring and required disabling all
undo/reopen/banner rollback because failures bypass the injected save path.
Wiring, marker and confirmed safe exit are implemented but **unvalidated**. The
flag is not a verified isolation guarantee until exact-source native build/tests
and independent wiring review finish. See `bundled-demo-wiring-review.md`.

## Problem and outcome

The expanded home needs realistic debugging data without reading, replacing or
writing an existing user's medication records. The source is the repository's
`DemoDataSeeder.swift`: five stable medication IDs, five daily plans, stocks,
saved educational label samples, risk cards, 60 days of synthetic task history
and the Vitamin D3 dose change. This is historical demo **source**, not an
imported historical user database. The two-medication UI fixture is different;
there are no historical package photos to recover. No downloaded assets,
dependencies, accounts or services are required; existing repository code and
educational samples remain first-party repository source under the boundaries
recorded in `docs/THIRD_PARTY_NOTICES.md`. No repository LICENSE file was found;
this slice does not infer new redistribution rights or add third-party material.

## Planned explicit session and data contract

- Simulator-only `DEBUG || MEDCUE_DEMO`, explicit `--bundled-demo-session UUID`.
  Missing flag means ordinary startup; invalid/duplicate/conflicting arguments
  mean isolated failure, never primary fallback. Device and Release entry absent.
- New `BundledDemoStores/<UUID>/demo.store`, CloudKit disabled through the existing
  container factory; separate `medcue.bundled-demo.<UUID>` preference domain.
  Reject symlink/unknown/partial directories before opening any store.
- Record preparing/ready source version, session UUID, reference instant and
  time zone in an owned manifest. Create only an empty, newly owned container;
  fetch errors and save errors propagate. Write ready only after successful save
  and full initial-data validation. A failed session remains failed: no deletion,
  no rebuild, no automatic retry of a partial seed.
- Same-session ready reopen only loads. It does not reseed, normalize or reset
  user actions/preferences. One persisted reference date/calendar seeds all
  historical/today data and supplies the demo clock. First session defaults to
  the current instant; deterministic hosted tests supply a fixed instant.
  A changed calendar/time zone refuses this session before opening its store;
  a new explicit session is needed. Existing Today uses its device calendar,
  so silently accepting a changed zone would break the demo-day task boundary.
- Visible “合成演示数据” plus reference date; an explicit exit closes only the
  demo UI and explains relaunching without its argument. It does not delete data,
  call `exit`, switch a live ModelContext to primary, or rewrite standard defaults.

## File ownership and sequencing

| File | Owner / scope |
| --- | --- |
| `Models/DemoDataSeeder.swift` | This slice: owned-session fresh seed, shared date parameters and strict reads; preserve old entry conditions and legacy best-effort reads |
| new `Models/BundledDemoSession.swift` | This slice: request parser, owned manifest/container/preferences, empty checks and seed validation |
| new `BundledDemoIsolationTests.swift` | This slice: real temporary SwiftData stores, sentinel, idempotency and failure cases; Mac executes |
| `project.pbxproj` | Four additive lines/two IDs per new app source (session, then host); separately reviewed; no target/settings change |
| `MedicationAdherenceApp.swift` | Coordinator-authorized early demo branch; ordinary init/recovery/smoke content retained |
| new `Views/BundledDemoHost.swift` | Real Today host, own settings, marker/error/exit and fake adapters; Root/old fixtures untouched |
| `TodayView`, `TodayScreen`, workspace and two row files | Authorized single-capability presentation and callback guards; no transaction changes |
| Schema/Core/CI/tools/original evidence/native Mac tree | Untouched |

## Precise protected initialization exception for coordinated review

`MedicationAdherenceApp.swift` currently cleans production PDF files before
fixture selection; a thrown fixture load enters generic recovery, whose retry
opens the primary store. Its intent executor checks only `active == nil`, which
also becomes true after demo failure. The DEBUG root task runs production smoke
runners. A fixture-only addition therefore cannot satisfy isolation.

Proposed minimal change in this file only:

1. Compute whether `--bundled-demo-session` was requested before PDF cleanup and
   before any primary opener; request detection remains true even if invalid.
2. Skip production PDF sweep only for that request. In the existing init `do`,
   route it to the owned session factory; ordinary/old-fixture startup unchanged.
3. Preserve the existing in-memory failure container, but tag a demo failure and
   render a dedicated demo error/exit page instead of `PersistenceRecoveryView`.
   Its UI has no primary retry/export buttons. No database initializer removed.
4. Set intent external-action permission false for any demo request, successful
   or failed; install no notification delegate for the demo. Skip all three
   smoke runners for that request, even when contradictory smoke flags exist.
5. Use the session preference suite and dedicated demo host on success. Keep the
   ordinary `.modelContainer`, primary retry, migration and recovery code intact.

This is a required isolation dependency, not a performance or recovery redesign.
The coordinator independently assessed and authorized precisely this exception.

## External-action boundary still to resolve before UI wiring

Existing Today injection replaces save/reminder/Live Activity/help adapters, but
ordinary tabs, medication detail/edit, HelpCenter's legacy rebuild button,
permission/settings links, AI/health/account/export and generic persistence-error
reporters can still reach real services or standard defaults. Demo must use a
bounded host with those paths unavailable or narrowly gated. Do not call old
`seedIfNeeded`, `rebuildForExplicitDemoMode` or `rebuildAndExit` in the new flow.
Do not claim a full interactive demo from data-layer completion alone.

Coordinator-authorized narrow wiring: a dedicated, session-owned
NavigationStack hosting the existing Today owner, no ordinary tabs/startup
maintenance. Supply owned preferences, fixed clock, save and fake reminder/Live
Activity/help adapters. Gate three existing detail navigation sites
(`TodayDoseRowViews`, `TodayDoseTimelineViews`, `TodayTaskWorkspaceView`) to a
read-only synthetic summary; gate HelpCenter and system Settings links in
`TodayScreen`/`TodayView`; disable archive/restore in this bounded debug surface
because these two Today methods directly call production Live Activity end and
their command's failure reporter writes standard defaults. Dose mark/delay/skip retain existing transactions. Independent review required
disabling every undo/reopen/banner rollback because its failure writes standard
defaults through DoseReopenCommand. The coordinator approved that bounded
limitation; UI explains it and default capability true preserves ordinary undo.

## Acceptance matrix and stop conditions

| Check | Required evidence |
| --- | --- |
| Five IDs/Chinese identities, 5 plans/stocks/labels, 300 historical tasks + 5 today tasks, Vitamin D3 change and dose attribution | Hosted SwiftData tests with fixed date/time zone and key associations |
| Restart after editing/completing one task | Same IDs/status/reason/stock/defaults; manifest unchanged; no duplicate seed |
| Existing primary/other store + standard defaults | Sentinel before/after equal; no primary opener called |
| Invalid/duplicate UUID, old fixture/seed/smoke flags, symlink, unknown/partial directory, source mismatch | Fails closed without opening unknown/primary data or writing ready |
| Read/save/manifest-write failure | Propagated failure, no ready marker, preserved owned failure evidence |
| Midnight/DST/fixed historic clock | Exactly five current demo-day tasks; history before that day; consistent Vitamin D3 cutoff |
| Visible synthetic marker, exit, real Today actions | Native UI on this exact later commit; no standard-default mutations, notifications, network, real dial/export |
| Release/device absence and project registration | Native build + fresh-context PBX/source review |

Stop UI integration if primary fallback or uncontrolled external actions remain,
or if schema/medical transaction/Today owner changes are required. Keep failures
and original evidence. Linux has no Swift/Xcode: static verification is not a
compile, hosted-test or UI pass. Integrate only after Mac finishes its fixed run.

## Data slice evidence and remaining gaps

The ten hosted test methods are definitions, not executed passes. Three injected
factory cases cover before-seed failure, throwing seed save and failure before
ready publication; the last verifies committed owned records are retained.
They do not simulate an actual SwiftData fetch failure or filesystem write
failure. Strict-read propagation is source-checked only. Sentinel tests cover
the factory, not the currently unchanged App startup. Native exact-source build,
legacy seeder tests, SQLite companion-directory behavior, hosted cases,
Release/device exclusion and all UI/external-action checks remain pending.
