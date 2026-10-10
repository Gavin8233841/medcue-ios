# Bundled demo: narrow startup and Today wiring

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

Data base: `implementation-stage-11`; independent branch
`unpublished-implementation-branch`. The data slice received independent source
review. The coordinator explicitly approved startup routing and the bounded
Today UI, then required disabling all undo/reopen/banner rollback because their
failure reporter writes standard preferences outside the injected save path.
This is a separate wiring commit; native acceptance remains pending.

## Implemented boundary

Simulator `DEBUG || MEDCUE_DEMO` only: an explicit `--bundled-demo-session UUID`
branches at the very beginning of App init, before the original PDF sweep and
primary opener. Valid requests use the owned data factory. Invalid/conflicting
arguments or opening/seed errors use an in-memory error container and dedicated
demo landing, without primary recovery/export actions. Neither path installs
the real notification delegate; the registered intent executor returns save
failure. No ordinary Root or smoke task is rendered. Both paths bind the app's
color preference to an owned suite, including a separate error domain.

The original non-demo init block is byte-identical. The original Group containing
Root, recovery and all smoke calls is copied verbatim into the ordinary content
property. Ordinary migration, store opening, primary retry and init are retained;
the early demo branch returns before them. No white startup animation is restored.

`BundledDemoHost` supplies the existing Today with the owned context/preferences,
persisted clock, ordinary dose transaction using an owned-context save closure,
fake reminder/Live Activity adapter and suite-backed help contact/fake phone opener.
It has one bounded NavigationStack, no ordinary tabs/AI/health/account/export,
and no Root maintenance, Watch synchronization or old seed/rebuild entry.

The visible synthetic marker includes the demo date and explains the supported
actions and disabled features. “演示设置” changes only the session's mode preference,
with confirmation for entering and exiting elder display. A registered live
Today guard is checked at request and confirmation for mode/exit. Both existing
elder settings callbacks target the bounded settings UI. The disabled undo window
does not block demo navigation forever under the intentionally fixed demo clock;
the ordinary capability true keeps its original undo-window guard.

Confirmed exit removes Today only when its live guard allows leaving; it resets
the stored guard and shows a safe demo landing. It does not delete, reseed,
call process exit, write normal first-launch keys or open the primary container.
“重新打开此演示” reuses the same session without reseeding and waits for a fresh
Today guard. Landing explains ordinary relaunch returns the original records.

## One capability and Required undo closure

The capability defaults true for ordinary pages; only the debug host sets false.
Three detail NavigationLinks share a read-only demo destination, with synthetic
identity, strength/form/box/notes and no editor, photos, label import or services.
HelpCenter's old rebuild entry and weather/system settings paths are unavailable.
Archive/restore/reopen UI controls are disabled; complete undo banner is hidden,
elder undo feedback is disabled, and the workspace handled-action group is disabled.
Today owner has early guards for archive/unarchive, elder undo, shared undo/reopen,
banner rollback and system Settings. Defense-in-depth callbacks return before
constructing the real commands or invoking direct Live Activity end.

Allowed mark/delay/skip and confirmations retain their existing transaction code.
Their real notifications/Live Activities are replaced through the existing Today
adapter. No changes to DoseReopenCommand, AppPersistenceCommitter, schemas,
medical rules, migrations, action ordering or real consent. No service platform,
new dependency, installation or paid feature.

## Scope, checks and acceptance gaps

New `Views/BundledDemoHost.swift` has exactly four additive PBX registration lines
and two new IDs. Startup plus five Today view files have the authorized narrow
gates; Root/Settings/HelpCenter/services and the data slice remain unchanged.
TodayScreen and TodayView remain below 1400 lines. The pre-existing UI tests and
Mac mutating-macro fix are preserved; the main-interaction diagnostic commit is
on its separate branch and is not folded into this demo snapshot.

Four new simulator debug UI test methods define malformed/conflicting-request
failure, mode cancel/confirm/restart, each allowed elder action with a single log
and disabled undo, and confirmed exit/reopen. A read-only inspection marker is
enabled only by `--bundled-demo-inspect-store`, observes synthetic task/log counts,
and performs no save. Test definitions are not passes. These journeys do not
measure whole-system notification/call/network effects; source audit and actual
native external-effect/sentinel evidence are both required.

Cloud checks: diff formatting and 45 static scope assertions covering byte
preservation, project registration and callback guards. Source packaging is
validated separately. No Swift/Xcode here; this
commit has no compilation, hosted-test, UI, real-notification, VoiceOver, device
or performance pass. Do not borrow the successful implementation-stage-09 native build/policy
results. Exact new source needs fresh-context startup/PBX/isolation review, then
native debug build plus ten data tests, legacy seeder tests, four demo UI methods
on ordinary iPhone and Duo, failure/sentinel and Release/device exclusion checks.

Preserve original implementation-stage-09 native failures. Main branch's List evidence capture
uses a different validation source package; do not switch that Mac one-case diagnostic
run to this demo tree. No push, merge, release or main/PR162 change is part of this slice.
