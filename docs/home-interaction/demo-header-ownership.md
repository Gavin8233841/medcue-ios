# Issue 163: bounded demo header ownership repair

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

## Follow-up: initial publication regression (Required)

Repair baseline is frozen `implementation-stage-23`,
tree `implementation-stage-23-tree`, on new independent branch
`unpublished-implementation-branch`. The original demo-local-owner-stage and owned-scroll-stage candidates,
retained evidence  and Mac environments remain unchanged. This section supersedes
any implication below that initial publication/restart acceptance is satisfied.

Native owner reported demo-local-owner-stage source, one incremental build PASS, Duo/iOS27.1:

- `testExitIsConfirmedAndReopenRetainsTheOwnedStore`: FAIL at line 146 waiting
  for the unique Settings leaf's enabled=true immediately after first elder
  entry, before skip/no local presentation. Exit's explicit check had not run;
  automatic AX nevertheless showed one Settings and one Exit, both Disabled.
  Pixel frame at 26.895 seconds showed both grey. Skip/cancel/exit/reopen untested.
- `testDemoModeNeedsConfirmationAndPersistsInItsOwnSession`: FAIL at line 182
  opening Settings after restart. Earlier switch cancellation preserved 0,
  confirmed entry succeeded, persisted elder taken control and five-task
  assertions passed. Settings/Exit each one Disabled in AX, grey in frame at
  40.011667 seconds; isHittable passed but does not mean enabled. Returning to
  complete mode was not executed.
- `testEachAllowedElderActionCommitsOnceAndUndoRemainsDisabled`: PASS, 79.185
  seconds; taken/delay/skip each logs=1 and corresponding status=1, undo disabled
  if present, actual Settings open/done after each action, inspection unchanged.

These are coordinator/native technical returns; no raw results opened here.
Busy-state internals were not sampled. A correlated source cause candidate is:
the registrar stores `screenGuard`, then immediately publishes a closure that
re-reads `demoElderScreenGuard` through a captured TodayContentView value.
That State starts with a permanently false guard. If that publication observes
the previous round's State value, Host retains false; initial global predicate
stays true, so its change observer need not republish. Later action busy changes
can republish. This fits the observed difference but is **not proof of SwiftUI
internal timing**, and a static fix does not establish native recovery.

Bounded fix: publish the conjunction directly with this registration's
`screenGuard` argument; store it separately for later global-state republication.
Keep the fail-closed initial State and Host guard, local-owner change/initial
registration, two disabled controls and final commit rechecks. No default-true
change, scheduling delay, retry, dose action to enable navigation or missing-guard
fallback. Production scope is only the registrar's initial publication.

Acceptance extends existing UI methods without new discovery: explicitly check
unique Settings/Exit enabled at complete startup, initial elder entry, persisted
elder restart and exit/reopen **before any dose action**; retain local skip
disable/cancel/no-write and ordinary mode/store assertions. Existing action
journey remains a separate busy-recovery control. Fresh review and exact-source
native runs are pending. If first publication remains disabled, stop at the exact
first failure rather than injecting an action/delay. Photo preview stays a known
fixture gap; help-draft locator repair and startup sentinels are outside this
candidate. Cloud has no Swift/Xcode; no native pass is claimed.

## Problem and exact baseline

Baseline: `implementation-stage-22`, tree
`implementation-stage-22-tree`. Independent local branch
`unpublished-implementation-branch`; repository Gavin8233841/medcue-ios.
No remote operation, Mac change or replacement of retained evidence owned-scroll-stage source v5.

`BundledDemoHost.demoHeader` calls `openSettings(guard: navigationGuard)` and
checks the registered `navigationGuard` for exit request and final confirmation.
`TodayContentView` currently registers only `canLeaveElderToday` on appearance.
That live predicate covers dose confirmation, saves/in-flight work, reminder
sync, undo rollback and **helpConfirmationPhone**. Help is already covered.
`ElderTodayScreen.navigationGuard` additionally covers its private
`taskPendingSkip` and `medicationPhotoPreview`. Ordinary elder toolbar requests
pass this guard through `guardedElderRequest`, which composes both predicates;
the demo header never receives it.

With a pending local skip/photo and otherwise idle Today, the current demo
header guard returns true. This is a confirmed source ownership-contract defect,
not evidence that a native user can tap through a modal or write a wrong dose.
If a header request is delivered, it can open demo settings or accept exit while
that local owner remains unresolved. The repair makes those header controls
unavailable while owned and preserves final action-time guard checks.

## Scope, deliverables and acceptance

Own only TodayView's demo guard composition, ElderTodayScreen's optional demo
guard registration, BundledDemoHost's two header controls, the existing bundled
demo exit regression journey, and this technical record. Reuse the existing
environment callback and live request guard; add no service, dependency or test
fixture. Ordinary application callbacks default to nil and its original
navigation checks/transactions remain intact. No primary store, startup,
preferences, external-action adapter, fixture data, Core, schema, CI/tool or
project-file edits. No third-party code/license change or new medical claim.

Acceptance:

1. Demo receives the conjunction of current global and local elder guards,
   retaining final exit/mode rechecks. An absent registrar remains a no-op.
2. Local owner changes update the demo header's enabled state; initial guard
   registration has no duplicate parent override. Complete mode keeps its
   existing global registration; elder re-entry/reopen registers its new owner.
   Today retains the last registered local guard, initially fail-closed, and
   republishes the conjunction when global busy state changes. This avoids
   relying on another view's State invalidation to refresh a disabled header.
3. Existing synthetic exit UI journey enters elder mode, opens skip confirmation,
   observes the unique header Settings and Exit controls disabled (not merely
   covered/non-hittable), cancels using the existing owned-dialog helper, verifies
   both enabled again, and compares the unchanged owned-store snapshot. Settings
   and confirmed exit/reopen remain usable afterward. No extra test method/count.
4. Native owner reports exact candidate source, actual destination/runtime,
   complete method result or precise first stop. Cloud source checks do not
   establish Swift compilation or native behavior. A modal hiding header AX
   controls is a test-observability precondition failure, not a pass inferred
   from their absence. Photo data is absent from the historical bundled fixture;
   photo ownership requires additional native synthetic evidence, not real data.

Stop before broadening ownership architecture, adding startup fixture hooks,
weakening an assertion, reading a real store, changing normal application paths,
touching Mac/owned-scroll-stage package/evidence, pushing, merging or releasing. Stop and report
if the guard is already composed, file ownership conflicts, or proving native
behavior requires an unavailable owner/control. Keep source-review and native
acceptance pending until exact-candidate evidence exists.

## Read-only startup sentinel investigation

Source locations and what they prove:

- `MedicationAdherenceApp.swift:24–57`: explicit demo init branches before
  primary opening, PDF sweep and delegate install; demo error uses an in-memory
  container and a unique preference domain; AppIntent dependency fails closed.
  Its AppStorage declaration precedes init and is reassigned to demo preferences.
  Source separation is useful but does not establish actual process-startup
  standard-domain equivalence or absence of framework/default-wrapper effects.
- Same file, ordinary init and `PersistencePrimaryStoreOpener`: real default
  primary opening; recovery's `--medcue-recovery-isolated-test-store` points to a
  fixed temporary synthetic store. That recovery hook is not the real default
  primary location and cannot be relabelled as an actual-path isolation sentinel.
- `Models/MedicationAdherenceModelContainer.swift`: defaultStoreURL comes from
  the schema's actual ModelConfiguration; explicit `make(storeURL:)` and current
  schema/migration support reusable synthetic seeding. Do not guess the filename.
- `BundledDemoIsolationTests.primarySentinelAndStandardPreferenceDomainRemainUntouched`:
  real synthetic record + standard-defaults snapshot, but calls only the factory
  and points its sentinel to `primary-sentinel.store` under TestDirectory. It
  does not execute App.init at its actual default path. Hosted app launch may
  already have run ordinary initialization before a test constructs another App;
  a constructor test alone cannot close fresh-process startup isolation.
- `BundledDemoHost.fakeSystemSurfaces`, BundledDemoHelpOpener and
  TodayMedicationDetailDestination are existing fake/read-only seams. Existing
  UI inspection reports owned demo medications/tasks/logs/status totals. Neither
  those totals nor factory tests count actual NotificationService, Live Activity,
  Watch, URL/phone/network/export invocation at process startup.

Reusable plan for a separately authorized native task (not implemented/run):

1. Use a fresh disposable simulator/app container proven to contain only owned
   synthetic records; stop if ownership cannot be proved. Seed the same app's
   **actual default primary path** using the current schema/make(storeURL:) and
   fixed synthetic UUIDs, save and close. Seed standard defaults with completion,
   mode, theme/help and an unrelated synthetic sentinel. Never copy a user's
   container or inspect/rewrite an existing real database.
2. Record stable baseline hashes and sidecar presence for the closed owned store,
   plus its synthetic record projection and the app's persistent preference
   domain. Use a persistent-domain comparison rather than dictionaryRepresentation
   alone, which includes volatile/registration domains. Do not open the primary
   for read/write during the demo run merely to observe it; compare after process
   termination and retain only synthetic/count/hash evidence.
3. Reuse valid-session, invalid/conflicting-argument, reopen and confirmed exit
   journeys. For each fresh process, prove demo-only root/error UI, unchanged
   primary/standard domain, owned demo changes only, and no ordinary recovery.
   Read-only comparisons alone detect mutation, not forbidden primary reads;
   primary-open/delegate/PDF-maintenance attempt counters need a separate,
   explicitly reviewed DEBUG-only startup seam.
4. Reuse existing fake TodaySystemSurfaceAdapter/help seams for action checks,
   but separately instrument invocation counts at actual primary opener and
   production notification/Live Activity/Watch/URL/export/network entry points
   if a no-attempt claim is required. An unchanged notification count alone
   cannot prove zero attempts. Do not replace production adapters or change
   safety policy as part of this header fix.
5. Keep failure/restart paths and ordinary control startup distinct; run no
   external-effect-producing ordinary controls without owned fakes. Release and
   physical-device demo exclusion remain separate compilation/native gates.

## Cloud checks and review boundary

- `git diff --check`: passed; focused production diff contains guard registration,
  composition and two disabled modifiers only. Existing action-time guards and
  ordinary `guardedElderRequest` remain unchanged. No transactions or fixture
  data changed; startup sentinel investigation is documentation only.
- `tools/swift-source-size-check.sh`: passed at limit 1400; TodayScreen.swift is
  exactly 1400 lines. No unrelated refactor to reduce it or override the limit.
- Source discovery: all 20 inventory methods and complete source suite method
  lists remain identical to owned-scroll-stage. Existing exit/reopen method has stronger checks;
  historical passes of that old method do not validate its changed body.
- `tools/verify-native.sh --quick`: stopped with exit 2 at missing `plutil` before
  gates ran. `swift` and `xcodebuild` also absent. No build/native-test pass claim,
  package generation, native run or Mac operation.
- Self-review additionally found that disabled controls must recover when global
  busy state ends; explicit global guard republication addresses that in source.
  Exact-candidate native evidence remains pending. Reuse the existing
  `testEachAllowedElderActionCommitsOnceAndUndoRemainsDisabled` to verify header
  Settings remains usable after each real synthetic mark/delay/skip transaction.
  Selected exit/reopen journey is the primary new regression. Mode persistence
  journey covers complete/elder registration. Photo fixture coverage is absent.

Await fresh-context review before proposing any independent native build.
The frozen owned-scroll-stage validation/visual-review jobs keep their exact source and evidence;
this candidate does not inherit owned-scroll-stage's two UI passes or earlier-integrated-stage's hosted36/demo4.

## Platform sources and evidence limits

Consulted Apple API pages on 2026-10-10:

- [EnvironmentKey](https://developer.apple.com/documentation/swiftui/environmentkey):
  custom environment values have a default and are injected through the view
  hierarchy; the existing optional registrar defaults to nil.
- [State](https://developer.apple.com/documentation/swiftui/state): local view
  state has SwiftUI-managed storage; retained guards must read current state.
- [onChange](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg):
  use the existing two-argument API with initial registration and Boolean owner
  change observation, not body-time side effects.
- [disabled](https://developer.apple.com/documentation/swiftui/view/disabled(_:)):
  disable only the two demo header controls; retain their action-time guards.
- [confirmationDialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)-2tbci):
  regular-size-class popovers support outside dismissal. Reuse the existing
  owner/frame-bounded dismissal helper rather than app-wide gestures.

EnvironmentKey, State, confirmation-dialog, disabled and onChange summaries were
returned by web search. Apple's [older onChange overload](https://developer.apple.com/documentation/swiftui/view/onchange(of:perform:))
specifically points to the zero/two-input replacements. Full API bodies required
JavaScript; Markdown retrieval failed (browser unsupported content type; direct
network proxy 403). These consulted API references do not prove native behavior.
