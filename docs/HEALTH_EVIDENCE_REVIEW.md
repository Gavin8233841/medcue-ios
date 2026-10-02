# Health evidence review — Issue #135 candidate

Issue: https://github.com/Gavin8233841/medcue-ios/issues/135
Base: `4d9c6d50d46a5735dc014da5434e1063d8cf7493`.
This document describes the proposed branch, not an integrated release or device acceptance.

## User journey

Settings → Apple Health → 本机健康回顾 opens a local review. Choose 7, 30 or 56 days,
refresh, inspect sleep, resting heart rate, HRV SDNN and respiratory-rate facts,
and choose a deterministic review question. The settings overview counts new review records
separately from legacy vital signs, so sleep-only authorization is not shown as no health data;
trend/export destinations still count only their supported vital-sign records. No model download, credential or network
request is needed for this page. This does not remove the existing downloaded-model
readiness requirement from the separate assistant chat screen. Existing vital-sign trends and visit-summary links remain.

Permission completion is not proof of individual HealthKit read permission. Empty data
is described as unreadable/unrecorded, not zero or proof of denial. Previously authorized
users can request the newly added types via 管理新增指标读取授权.

Health-summary sharing with the offline assistant is a separate default-off switch.
It does not modify medication consent. The existing assistant still requires its chosen
runtime to be ready; the standalone local review has no such requirement. Only an exact
allowlist of record-review questions can use the deterministic chat shortcut. Arbitrary
symptom, treatment and causal questions continue through the existing medical-AI path.
The data-backed shortcut does not use a language model or claim model interpretation.
Successful deterministic replies include the report timezone and all applicable quality
limitations, including excluded source groups and timezone assumptions.
An exact review question with no current snapshot returns a refresh/permission message and
never falls through to general model generation. Symptom questions retain the existing path.

## Data contract and calculations

- The existing six vital-sign types retain their own legacy trend mapping. Stable HK UUIDs
  now survive mapping. New sleep/RHR/HRV/respiratory types do not enter legacy scores.
- New evidence carries UUID, UTC interval, normalized value/unit, source app/version,
  product type/model grouping, and optional recorded timezone. No device serial number is
  collected. A source group is not a unique physical device identity; two identical devices
  may not be distinguishable.
- One source app/version/model group per metric is selected by covered complete periods,
  then stable source ID tie-break. Samples from other groups are not averaged in. Multiple
  groups and timezone assumptions are visible. This is not Apple Health's source-priority
  algorithm or proof of equivalent data.
- Quantity periods are calendar days. Sleep periods are noon-to-noon in the displayed
  report timezone, including naps. Only complete periods count; in-bed/awake are excluded,
  asleep intervals are unioned, overlapping detailed stages are flagged, and stage percentages
  are not calculated. DST uses elapsed time, not wall-clock subtraction.
- Each complete period is summarized first; the report is the median of observed period
  values. Coverage is unique observed periods / expected complete periods. Missing periods
  never become zero. This is a descriptive record summary, not a diagnostic score, a clinical
  normal-range assessment, causal inference, or treatment advice.
- The report shows actual start/end/timezone. Controlled weekly/monthly questions select
  seven/thirty-day evidence when available, never silently reuse the full 56-day summary.

## Bounded reads, deletion and cancellation

The read window is at most 56 days. Each quantity query requests at most 20,001 objects
and sleep requests at most 8,001. The extra object is an overflow sentinel: if a type exceeds
20,000 quantity / 8,000 sleep records, that entire metric is excluded and a visible budget
warning is shown. A 7-day retry is reachable. There is no silent latest-250 truncation and
no claim that overflow results form a complete summary. This is a bounded fail-closed
snapshot implementation, not persistent pagination or an anchored background collector.

Refresh replaces the in-memory snapshot, so deletion/replacement of source samples is
reflected after a successful refresh. Query failures never reuse old facts. Statistics run
outside the main actor; sleep overlap detection uses a sorted sweep rather than pairwise
comparison. HealthKit queries stop when their awaiting task is cancelled, with a locked
single-completion continuation to handle the callback/cancellation race. Real device
latency, memory, background behavior and cancellation must still be measured.

Per-service epochs reject superseded reads. A shared connection revision also rejects
reads across disconnect/reconnect (the bool-only ABA case). Delayed disconnect notifications
carry their revision and cannot clear a newly authorized snapshot. A shared snapshot
revision invalidates in-flight health answers as soon as a refresh starts. Multiple screens
refreshing at once can supersede an older screen's snapshot; that screen must refresh again.

Stop reading clears this app's in-memory review and closes health-summary permission.
It does not delete Apple Health originals or existing chat messages. System-side read
revocation is not directly observable by an app; no immediate remote erasure promise is made.

## AI and privacy boundary

`healthSummary` is a new independent scope. Medication consent alone cannot attach evidence.
The request carries health consent and snapshot revisions. Before either local or online
assistant responses are persisted, the main-actor command checks the current consent and
revisions and commits without another suspension. Revocation/regrant and snapshot refresh
cannot accept an old response. Existing conversation history is intentionally retained.

Cloud health sharing is not enabled. The cloud factory wraps the existing provider client
with a guard rejecting any request containing a health bundle before transport. No broker
production deployment or provider API call was made. Future rollout needs a separately
reviewed provider health-data role, explicit consent, retention/deletion behavior and
medical-output evaluation; ChatGPT subscriptions are not an API entitlement for this app.
User-entered chat text retains the existing disclosure and sharing semantics; this gate
protects automatically attached HealthKit evidence, not arbitrary text typed by a user.

No persistent HealthKit database, automatic long-term health memory, vector index,
background alerting or cloud-sync feature is implemented. Future memory requires dependency
tracking, user-visible editing/deletion and full derived-data invalidation, not just chat storage.
No SwiftData schema migration is added. New UserDefaults keys store only permission/revision
state; the health content remains in memory.

## Validation evidence and limitations

Cloud Linux, official Swift 6.4 toolchain: the portable core suite passed **176 tests**, including
15 health-evidence tests. Initial new-test macro compilation failed because a mutating method
was called inside `#expect`; the tests were corrected to evaluate the mutation before asserting.
The original failure log was retained outside the repository. Swift source-size and diff-whitespace
checks pass. All app and hosted-test Swift files passed compiler syntax parsing on Linux;
this is **not iOS type checking or an Xcode build**.

The toolchain was downloaded from the official Swift.org Debian 13 link; GPG reported a good
signature with the official Swift 6.x fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`.
It also reported an expired public key warning. This local compiler evidence is supplementary;
the repository's unchanged required macOS/Xcode CI remains authoritative for native checks.

Seventeen hosted integration tests are added, covering default-off scope, cloud guard, connection
ABA, regrant, and actual SwiftData commit rejection after revocation/refresh. They were not run
on Linux. `tools/verify-native.sh --quick` is blocked by missing `xcodebuild`; no gate is weakened.
No device, HealthKit permission dialog, provider, model inference, UI/accessibility screenshot,
watch build, full native gate or exact-head CI success is claimed here.

Independent non-author review is in progress. The reviewer has prior design-review context;
this is not a claim that the repository's fresh-context final-review gate is already satisfied.
Keep the PR Draft and do not merge until required CI, final review and device evidence exist.

## Native and device acceptance checklist

1. Run unchanged full Native Verification for the exact PR revision; run all hosted tests.
2. On a synthetic test iPhone, grant only sleep; deny other types. Verify empty types make no
   permission assumption. Add authorization for RHR from the existing-user management button.
3. Add overlapping sleep/in-bed/stage samples, timezone/DST cases and two source groups;
   compare displayed periods, source group and coverage to independently calculated values.
4. Supply 301 quantity samples and then over-budget samples; the first remains complete and
   the latter shows no partial statistics. Choose a shorter window and retry.
5. Delete/replace samples in Apple Health, refresh, and verify both facts and in-flight health
   responses do not reuse the previous snapshot. Existing completed chat is not automatically deleted.
6. Begin a read in screen A, disconnect in B, reconnect in B, then return to A and refresh.
   Old callbacks and old disconnect notifications must not restore/clear the new result.
7. Begin an assistant response; revoke medication sharing or local health sharing during the
   wait. Verify no assistant message persists; regrant does not resurrect the previous response.
8. Test task cancellation, background/lock/unlock and large readable histories on device.
   Record actual latency/memory and confirm cancellation reaches the OS query.
9. Check review controls and all quality labels at default and accessibility text sizes, VoiceOver,
   dark mode, back-navigation and repeated range changes. Do not infer visual correctness from compilation.
10. With every cloud provider selected, a crafted health request must be rejected before network
    transport, while ordinary authorized medication requests retain existing behavior.

Rollback: revert this feature commit. There is no health database/schema migration; new permission
keys can remain inert, and Apple Health originals are untouched. Do not expand cloud sharing as a
rollback shortcut. Future work and known PR overlaps must be integrated serially.

## Official references

- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis
- https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate
- https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn
- https://developer.apple.com/documentation/healthkit/hkmetadatakeytimezone
- https://developer.apple.com/documentation/healthkit/protecting-user-privacy
