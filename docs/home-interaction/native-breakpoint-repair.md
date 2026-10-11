# Issue 163: minimal repairs from classified native breakpoints

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

## Work item and ownership

Base is frozen integrated snapshot `implementation-stage-16`,
tree `implementation-stage-16-tree`. The coordinator reports one
successful build, hosted 36/36, Duo UI four passes/five failures, ordinary iPhone
demo four passes, and eleven other ordinary UI methods not run. These results
belong only to that snapshot. Raw native evidence has not been transferred here;
this work uses the coordinator's non-sensitive independent local classification.
This report includes no raw native evidence.

Users need separately identifiable home actions and reliable first-use/mode
test evidence. The candidate author owns this independent repair snapshot; the
coordinator retains the base source/evidence, independent reviewers own review,
and the Mac owner owns any later authorized native validation. No automatic
push, Mac operation or rerun. Each repair category is a separate commit.

| Category | Exact observed breakpoint | Scoped implementation | Acceptance |
| --- | --- | --- | --- |
| Settings lifecycle | After presenting the exact mode alert, helper reads an old masked Switch handle | Validate value before tap; validate exact alert and available Settings host during presentation; wait for alert dismissal before fresh owner/leaf lookup | Cancel retains value and store; confirmation changes page/mode; restart persistence and all existing cancellation assertions retained |
| Workspace AX | Parent expanded ID reaches two scroll views and three action buttons; taken ID disappears before mutation | Explicit contain accessibility boundaries for workspace and its panes; preserve individual action IDs/labels/traits; scoped uniqueness assertions in expanded and compact journeys | Exactly one expanded workspace and one list/detail pane; distinct taken/delay/skip and confirm/cancel controls remain accessible; no selection writes |
| Background precondition | Home immediately followed by activate; Later only checked for existence | Wait for actual background/suspended state with official app state API; wait for foreground, exact alert absence and hittable Later; capture state/time/AX before failure | First-use confirmation is invalidated after real background; Later completes, restart and store assertions remain |
| AX5 cancel visibility | Valid pixels show confirmation card cut off at screen bottom; app-wide scrolling ineffective | Read-only source investigation, retain usability risk | Native visible geometry and correct scroll ownership needed before choosing any product or gesture repair |

Out of scope: dose/medical policies, transactions, model schema, primary/demo
stores, initialization/migration, production mode lifecycle/bindings, production
Settings help auto-positioning, AX5 layout/gesture changes, CI/tools, dependencies,
credentials, costs, main/PR162 or release. The production change is accessibility
container ownership only. It must preserve independently actionable children,
VoiceOver labels/traits/order and existing layout; it must not combine/ignore
children, add proxy controls or loosen counts to hide identifier propagation.

Risks: new container boundaries need actual SwiftUI/VoiceOver verification; state
waits must observe real background and not synthesize a lifecycle; native AX
snapshots may be unavailable behind system UI. No device/performance/competition
claim follows from source review. Synthetic-fixture failure attachments stay
local to a later authorized native run, with no real health database or standard
preferences involved. No dependency or license change.

Validation here: exact diff/scope and preserved source checks, original test
methods and cancellation/store assertions, whitespace/line limits, source ZIP
scan and checksum. No Swift/Xcode is available. Independent source review comes
before any new native build; prior pass counts cannot be reused for this HEAD.
Stop on ambiguous ownership, business-state changes, broadened retry/timeouts,
unsafe fixture data, missing native evidence or packaging failure.

## Settings lifecycle slice

The invalid post-tap old-handle value assertion is removed because the exact
alert masks that element. Pre-tap value validation and Settings host existence
remain. Both cancel and confirm helpers wait for their exact original alert to
disappear; existing callers then requery current owner/leaf or assert the resulting
page, and retain restart/store checks. This does not claim the underlying mode
can be read through an accessibility modal or suppress a missing/wrong alert.

Compilation, native alert dismissal timing and the resulting mode value/page
remain unverified for this repair.

## Workspace accessibility ownership slice

The workspace and both panes now have explicit `accessibilityElement(children:
.contain)` boundaries before their own identifiers. There are no label/trait,
layout, selection, dose-state or action closure changes. The three action buttons
retain their existing IDs and the identity's combined spoken description remains
unchanged. The contain semantics preserve accessible children rather than
combining or ignoring their separate actions; see Apple's
[contain documentation](https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/contain)
and [accessibilityElement(children:)](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)).
Runtime container/child IDs and VoiceOver ordering still need native proof.

Expanded UI tests keep the exact workspace count assertion and additionally
require one global and one workspace-owned list/detail pane and one distinct
taken/delay/skip button within the detail pane. The independent detail-scroll
journey resolves the unique actual ScrollView within that pane, accounting for
the boundary itself being a ScrollView or an Other; no arbitrary match is used.
The existing single-task AX compact journey checks absence of all expanded pane
IDs, unique independent action IDs and both confirmation IDs without changing
its gestures, cancel/store assertions or the unresolved AX5 behavior. The wide
pending-recovery journey applies the same ownership checks before mutation.

No native test has run on this change. The original AX5 scrolling failure is
still an acceptance risk, not repaired by adding an identifier boundary.

## Actual-background test precondition slice

The first-use journey records wall-clock time, process uptime and app state at
Home, after the background wait, after foreground wait, after alert-dismissal wait
and after Later-readiness wait. It calls official `app.wait(for:timeout:)` for
runningBackground with five seconds; if the app is already suspended, a zero-time
runningBackgroundSuspended state check accepts that observed alternative. It
also verifies the sampled state is one of those background states before
activating. This is not a second Home gesture, retry or fake lifecycle event.
It then waits for runningForeground, the exact original alert's nonexistence,
and an existing/enabled/hittable Later button, each bounded by the existing
five-second UI wait budget. Store/restart/cancel assertions remain.

Before each new failing assertion, a keepAlways text attachment records state
and times and foreground AX. Capture requires this test's exact fixture arguments
and valid unique session UUID. If the app is not foreground, the attachment marks
AX unavailable instead of activating it to obtain evidence; before/after capture
states remain explicit. This failure evidence is generated only in a later
authorized native execution, not uploaded by the candidate author.

Apple documents [wait(for:timeout:)](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/wait(for:timeout:))
and the [application states](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/state-swift.enum).
These APIs establish what the test observes, not a native pass. Production Root
still cancels requests on non-active scene phase, rejects stale UUID callbacks
and requires active state before committing; its source is unchanged. If the
new properly backgrounded journey leaves confirmation visible, preserve the
exact result as a product lifecycle finding rather than loosening this test.

## AX5 read-only investigation and minimum next evidence

No compact scrolling, confirmation card or gesture source is changed here.
`TodayScreen.timeline` mounts a non-lazy vertical VStack inside one ScrollView
and ScrollViewReader, with bottom padding of 180. Its task scrolls the selected
row to the top when selection event or confirmation key changes.
`TimelineDoseTaskRow` uses an accessibility-size vertical header layout and a
time rail with minimum height 172 during confirmation; this is a minimum, not
evidence of a maximum-height clip. `TodayDoseActionsView` stacks its three action
buttons vertically at accessibility sizes. `InlineDoseConfirmationCard` also
stacks cancel/confirm vertically, uses growing fixed-size text and minimum button
height 60, and focuses the confirmation title on appearance. The compact test's
reveal helper swipes the application, not a verified timeline scroll host.

| Hypothesis (not a finding) | Smallest distinguishing native evidence |
| --- | --- |
| App-wide swipe lands on chrome/another surface instead of the timeline | Identify the unique foreground timeline ScrollView and its card descendants; compare actual scroll/card/button frames before and after one owned-host gesture |
| Growing row/card exceeds the visible budget after the top-anchor reveal or AX focus | Record usable viewport, row/card/cancel/confirm frames and the automatic reveal/focus timing; check whether subsequent owned-host scrolling reaches both controls |
| Scroll content bounds/insets fail to include the full grown confirmation | At the real scroll limit compare content range and cancel/confirm bounds with viewport/bottom obstruction; distinguish unchanged offset from a reachable button still clipped |

Valid captured pixels and the corresponding hierarchy/gesture chronology must
agree before assigning the failure to a product layout or test gesture. No
hard-coded pixel target, global helper relaxation, automatic scroll redesign or
inferred AX5 pass. Raw native frames were unavailable in this source review;
shipping this synthetic source package does not transmit those frames or logs.

For independent review, the three repair slices should be assessed cumulatively
against frozen `implementation-stage-16`; the source-derived test inventory still expects hosted
36 and UI 20 methods because no test method was added/removed. Current native
coverage for this repair branch is zero. AX5 and all eleven unrun ordinary UI
methods remain pending; the original demo acceptance gaps are unchanged.

## Follow-up: observed implementation-stage-19 workspace ID contract

The coordinator reports one successful incremental native build and four methods
run once on `implementation-stage-19`. The complete Settings
journey passed cancellation, both exits, confirmation, restart and store comparison.
Before the background case's activate call, state remained foreground (4) before
Home, after waiting and before/after AX capture. The required actual-background
precondition did not occur; this does not show a Root invalidation failure. Neither
path is changed or rerun by this follow-up. AX5 still awaits authorized visible
evidence; its card and gestures remain unchanged.

Both home failures showed one viewport, one list and one detail, but no expanded
root AX element. The three buttons inherited `today.workspace.actions`; taken
had count zero and recovery had not performed its first mutation. Inspection of
all Swift sources found five expanded references in the two home UI test files,
one expanded production modifier and one actions production modifier; no test
looked up actions. `CompactDoseActionButton` already assigns each native Button
its taken/delay/skip identifier and spoken label. Inline confirmation assigns
its cancel/confirm identifiers on the native Buttons, with an unnamed contain
group. Compact row actions have no workspace-actions ancestor.

This single follow-up removes only the expanded/actions ancestor identifiers
from production source. Existing contain semantics for viewport, workspace,
panes and confirmation are preserved; no additional contain, hidden marker,
proxy control, label, layout, state, selection or transaction change. The earlier
expectation of a distinct expanded root AX node is superseded by the measured
native structure, not by a relaxed count or arbitrary match.

| Required contract | Exact UI assertion |
| --- | --- |
| Two-column presentation | One global viewport, one global list/detail each, and exactly one of each pane within that viewport; existing actual width/height budget guard retained |
| Compact presentation | One viewport; list and detail counts are exactly zero globally and inside the viewport |
| Action ownership | Taken/delay/skip each has exactly one Button globally and inside the current viewport in expanded and original single-task compact fixtures; each has zero Button descendants and retains a spoken label |
| Confirmation ownership | Confirm/cancel each remains unique with zero Button descendants; expanded checks both are in its current viewport |
| No medication change from browsing/cancellation | Original selected identity, dosage/time, selection lock, baseline store and save/log/schedule assertions remain unchanged |

The expanded action footer is mounted with safeAreaInset. Its controls are
checked within the current real viewport rather than requiring them to be
descendants of the detail ScrollView's scroll contents. Detail gestures remain
scoped to the pane's unique actual ScrollView; footer ownership does not broaden
the gesture target. The compact single-task action contract uses the same viewport.

All five expanded test references are replaced by this real host contract. No
Swift code references expanded/actions after this patch. No new firstMatch,
count >= 1 workaround, gesture retry, source marker, build setting or dependency.
The source inventory still has 36 hosted and 20 UI methods; this follow-up has
zero executed native tests and needs independent source review before any newly
authorized native run. Original 712 and earlier-integrated-stage snapshots and their failures remain.

## Bounded workspace identifier audit after implementation-stage-20 native run

The coordinator reports a successful build on `implementation-stage-20`, one complete expanded
selection method pass, and recovery failure in its first missing scenario before
cancel was tapped. Its visible cancel button inherited the unavailable ancestor
ID. The following four recovery scenarios were not run. This is exact older-source
evidence, not a pass for this follow-up. All raw native evidence remains local
to Mac; this branch neither obtains nor uploads it.

The audit is bounded to the Issue's workspace presentation file, its viewport
mounting in TodayScreen, and the shared action/confirmation presentation and
actual Button identifier placement in TodayDoseTimelineViews. Existing Settings,
other app screens, database/startup, transaction and medical policy are outside
scope. A status identifier must describe its own visible non-action state; it
cannot identify an ancestor of separately actionable children.

| Identifier / semantic owner | Audit result and action |
| --- | --- |
| load error/loading on outer status VStack | Noninteractive today, but unnecessarily tags the whole state group; move to visible error Label and loading ProgressView respectively, keeping text/layout unchanged |
| unavailable on missing-selection outer VStack | Confirmed propagation to Cancel; move to the existing visible explanation Text and leave its ancestor unnamed |
| cancel unavailable / return to list | Cancel keeps its explicit native Button ID; give Return its own explicit native Button ID, preserving labels, disabled guards and callbacks |
| viewport, list, detail | Real unique structural hosts observed by native; keep existing contain boundaries and IDs, with no additional container ID or grouping change |
| selected identity combined text | Noninteractive identity/dose/time/status element; retain its ID, header trait and combined spoken description |
| selector and handled-section button | IDs belong to their single existing actions, not ancestors of additional actions; keep selection/value/hint semantics |
| shared dose actions and inline confirmation | Their action ancestors are unnamed; native Button IDs already own taken/delay/skip/confirm/cancel; keep these IDs and grouping unchanged |
| removed expanded/actions ancestors | Remain absent; no fallback marker or test dependency introduced |

Recovery now checks one explanation StaticText globally and in the current
viewport, its exact existing message, one Cancel Button globally/in that viewport,
the real leaf and its spoken label. Missing/replacement Return uses its own ID
with the same owner/leaf/label checks. Original mutation, pending isolation,
no-new-confirmation, task/log/save/schedule, cancellation and selection assertions
remain. No count weakening, firstMatch fallback, business command, layout or
wording changes. Review and exact-source native recovery verification remain
required; the audit is source evidence, not proof of all runtime AX behavior.

Stop on newly ambiguous ownership or any request to change data policies,
production layout or evidence upload boundaries. Source ZIP checks and a
two-commit review precede a later authorized incremental run of only recovery
and AX5; already passed Settings, ordinary background and expanded selection
journeys are not scheduled again here.

## AX5 compact Today scroll scope: separate test-only slice

The coordinator's local visual classification places Cancel below the current
viewport without a demonstrated fixed obstruction. Prior application-wide swipes
do not establish that the actual Today ScrollView cannot reach it. This slice
changes only the AX5 test's first-action and cancel reveal helper; no production
scroll behavior, font, confirmation card, height, focus or animation changes.
No raw frame is obtained or uploaded by this source-review stage.

For this exact owned future/complete fixture, every iteration rebuilds the unique
viewport, verifies compact pane absence, then resolves exactly one actual native
ScrollView within that owner. It requires an existing/enabled host, finite positive
frame and no nested ScrollView. Container hittability is recorded independently,
not treated as proof that a visible descendant is inaccessible. The specific
Button must be unique globally, in the viewport and within that scroll host,
have no Button descendants and be existing/enabled/hittable with frame intersection
before returning it to the caller. Absence may be revealed by scrolling; ambiguity,
misownership and invalid geometry fail before another gesture.

The original bound is retained: at most six upward and six downward swipes, now
on the owned ScrollView, followed by the existing five-second existence wait and
a fresh final owner/leaf lookup. No application-wide fallback, guessed point,
timeout increase or retry loop. Each gesture activity retains a pre-gesture text
trace, so an event-synthesis abort still leaves prior host/leaf values. Helper
failures attach full app/viewport/target/scroll hierarchies, independently read
exists/enabled/hittable/frame/nesting fields, trace and an explicitly unvalidated
screenshot with keepAlways before assertion. Capture/scrolling require this test's
exact generated arguments, known scenario/mode and valid unique session UUID;
no ordinary user session is eligible. These are future native-local attachments,
not newly uploaded evidence or a runtime pass.

Original confirm/cancel leaf-count and baseline medication-store assertions
remain. Already-passed expanded-selection/Settings and other test bodies are
unchanged by this slice. The later native owner should review/build the frozen
source once and select only:

- `MedicationAdherenceAppUITests/TodayPendingConfirmationRecoveryUITests/testWideRecoveryForMissingChangedHandledArchivedAndReplacement`
- `MedicationAdherenceAppUITests/TodayTaskWorkspaceUITests/testMaximumAccessibilitySizeUsesOriginalRowsAndConfirmationWithoutWrites`

Recovery must report all five mutation scenarios or the precise first stop; AX5
must demonstrate actual owned-host reachability and unchanged data. No automatic
run is requested by this source-review stage. Long-list behavior, contrast, assistive
technology assessment, unrun ordinary UI and original demo isolation acceptance
remain separate outstanding work.
