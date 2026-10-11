# Issue 163 integrated candidate: acceptance and one-build discovery

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

The earlier unpublished integration combined the reviewed demo snapshot
`implementation-stage-14` with the interaction failure-capture
snapshot `implementation-stage-12`. Their common ancestor is
`implementation-stage-09`. The demo changes 15 paths and
the diagnostic changes two different paths. Assembly has no conflicts and keeps
both original histories. No original branch, main, PR 162, Mac checkout, CI,
verification tool, dependency, credential, release or remote has been changed.

Assembly preserves the reviewed production source bytes. Demo implementation
has three logical slices (data, host/guards, app startup), plus its separate
documentation correction; all four implementation slices were preserved in the original development record. That unpublished history is not an ancestor of this public-preparation branch. Diagnostic capture
does not fix a locator. Any authorized locator repair follows in a separate
test-only commit and must receive its own review before native validation.

## File ownership and evidence boundary

The candidate integrator owns only this new candidate, these integration
documents, and any explicitly authorized test-helper repair. Demo data/app/host
bytes belong to the reviewed demo snapshot. Interaction/initialization bytes
belong to their original authors and are preserved. The native owner owns Mac
discovery, builds, devices, artifacts and exact-source reporting. Independent
reviewers own consistency and source review. Changes to medication transactions,
schema, Core, ordinary startup, production Settings/help auto-positioning, CI or
packaging require a new scoped assignment rather than an incidental repair.

Cloud checks establish revision ancestry, exact source composition, test-source
inventory, whitespace, file-size limits and package integrity. They establish no
Swift compilation, executed test, isolation under actual app startup, performance
or accessibility pass. Historical policy 21/21 belongs only to `implementation-stage-09`;
earlier native failure reports and the `implementation-stage-12` diagnostic result remain intact.

## One native build after source freeze

1. Let the current standalone diagnostic run finish. Do not replace its source
   package or switch its checkout. Resolve/review a separately authorized
   Settings locator repair before freezing this integrated candidate.
2. Record the final full commit/tree and package checksum. On Mac enumerate the
   actually compiled tests with the available native tooling. Compare discovery
   against `integrated-test-inventory.json`; source method names are expectations,
   not authoritative compiled Swift Testing identifiers.
3. Use scheme `MedicationAdherenceApp`, Debug and existing build setting
   `MEDCUE_SIMULATOR_UNIT_TEST_BUILD=YES`. Build for testing once for the selected
   compatible simulator runtime/architecture. Retain its matching `.xctestrun`;
   execute selected suites with test-without-building on the ordinary iPhone and
   expanded Duo destinations supported by that build. The native owner resolves
   real destinations, SDK/tool versions and generated paths.
4. Hosted discovery expects five suites / 36 methods. UI discovery expects 20
   unique methods, of which three require a real expanded Today budget of at
   least 668 by 360. The ordinary destination has 17 venue-compatible methods;
   expanded Duo has 20, including forced accessibility compact presentations.
   Retain existing platform/fixture guards. Report actual discoveries, executed
   tests, justified skips and failures; these counts are not forced pass totals.
5. Preserve stdout, exit status and complete test results for each destination,
   raw failure attachments, exact source/build provenance and incomplete runs.
   Do not rebuild an unchanged source repeatedly, alter sources mid-run, add
   retries or broaden selection to conceal a failure. A new source fix requires
   its own review/freeze and a separately agreed validation budget.

The inventory selects first use, confirmed mode transitions, home selection and
pending recovery, bundled demo isolation/interaction, the original demo seeder,
and lightweight schema/persistence/migration regressions. It is a focused
discovery set; it does not replace the repository's full native gate or Release
and physical-device checks needed before a PR can be ready or released.

## Acceptance matrix

| Area | Required observable result | Existing discovery / additional evidence | Current status |
| --- | --- | --- | --- |
| First use and replay | Ask whether to enable elder mode; close/cancel/later/replay never reset completed setup or medication state; restart preserves completion | ExperienceModeUITests, FirstLaunchCompletionUITests | Source present; integrated native run pending |
| Confirmed mode changes | Settings entry and both exit paths confirm; cancel writes nothing; confirmed change commits once and persists; unknown preference safely resolves | ExperienceModeTransitionTests, ExperienceModeUITests, legacy Settings journey | Historical policy pass is earlier SHA only; integrated native run pending |
| Settings scrolling | Verified Settings owner retains its own List; reveal the actual unique Switch without touching background Today; child Switch receives the action | Formal Settings journey and keepAlways AX failure attachments | AX confirms original container hittability rejection; separate scoped test repair implemented, independent review/compile/native gesture result pending |
| Home ordinary / expanded | Expanded layout reorganizes task selection and details; selection writes nothing and retains medication identity; compact/AX mode uses original rows | TodayTaskSelectionTests, TodayTaskWorkspaceUITests on eligible destinations | Source present; integrated native run pending |
| Pending target recovery | Missing/changed/handled/archived/replacement dose never inherits old confirmation or writes another medication | TodayPendingConfirmationRecoveryTests and UI suites | Source present; integrated native run pending |
| Busy and local presentation ownership | Pending dose, in-flight work, help draft and local skip/help/photo presentations prevent header Settings/exit takeover; cancellation keeps original owner and state | Existing mode UI coverage plus explicit demo/header/photo acceptance | Partial source coverage; demo local-presentation/header bypass remains an explicit gap |
| Demo source and startup isolation | Historical five synthetic drug definitions seed only a fresh owned store; actual primary database and standard preferences remain byte/state equivalent; failures never enter primary recovery | BundledDemoIsolationTests and malformed/conflicting request UI test; actual app-level primary/preference sentinels | Factory sentinel test exists; actual app-startup sentinels remain missing |
| Demo commit and side effects | Allowed mark/delay/skip commits exactly once; no notification, Live Activity, Watch, phone/network/export or real health effect; disabled actions stay disabled | BundledDemoUITests; instrument actual external-effect adapters/counters | Source guards reviewed; actual external-effect sentinels remain missing |
| Restart / exit / background | Restart/reopen retains own store, identity, fixed demo clock and own preferences; exit confirms and neither deletes nor resets; background invalidates pending mode confirmation | BundledDemoIsolationTests, BundledDemoUITests and explicit background check | Restart source coverage present; demo background acceptance remains missing |
| Failure and old seeder | Save/publication failure cannot mark ready/retry into user state; original standard demo behavior and migration remain intact | Injected failures and legacy hosted suite; actual fetch/filesystem failures | Injected coverage present; real persistence/publication failure evidence missing |
| White startup bridge removal | White masking animation/wait removed while ordinary database, migration, loading and error recovery remain necessary and intact | Source comparison and ordinary startup/error paths on native | Source composition checked; timing/performance unmeasured |
| Accessibility and competition display | VoiceOver order/labels, largest text, reduced motion, dark mode and Duo open/close preserve identity, ownership and usable controls | AX tests plus native assistive/manual assessment | AX source tests present; manual/device evidence missing |
| Debug and release boundary | Explicit synthetic simulator demo only; Release/device builds cannot expose its factory/host/test flags; ordinary user startup remains unchanged | Debug runs plus separate Release/device compile and source scan | Conditional source guard present; actual Release/device exclusion unverified |

## Stop conditions

Stop before changing production source, weakening a safety assertion, selecting
an ambiguous/background list, touching a real health store, emitting an external
effect, replacing existing evidence, altering CI/tools, pushing or merging a
remote branch, or claiming a pass from missing/incomplete results. Preserve and
report compile failures, owner ambiguity, unsupported destinations, genuine skips,
unsafe fixture ownership and package/manifest mismatch. Missing sentinels, local
presentation ownership, background invalidation and Release/device evidence are
acceptance gaps, not implied passes or permission to silently extend assembly.
