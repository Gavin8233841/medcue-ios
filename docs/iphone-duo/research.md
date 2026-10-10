# MedCue iPhone Duo: official-source research and validation plan

Research date: **2026-10-09 UTC**. Intended companion to Issue #161. Public technical material only; all proposed fixtures must be synthetic.

## Scope and confidence

This document separates verified Apple guidance from proposed MedCue engineering decisions. It does not claim that MedCue has been built or tested with an iPhone Duo runtime. Work for this task remains cloud-only. No Mac task, device purchase, credential change, distribution, or release is requested by this plan.

Priority: preserve medication workflow correctness, improve visual clarity, and produce an honest, compelling demonstration. A polished responsive preview is useful design evidence, but is not proof of native Duo compatibility.

## 1. Product and toolchain facts

- Apple announced **iPhone Duo on September 9, 2026**. Preorders begin October 16 and first availability is October 23. Its announced shipping system is **iOS 27.1**. [S1]
- Official specifications list a **7.6-inch inner display, 1878 × 2670 pixels**, and a **5.4-inch outer display, 1398 × 2034 pixels**. Open dimensions: 164.6 × 117.8 × 5.2 mm; closed: 84.1 × 117.8 × 11.3 mm; weight: 254 g. These are hardware specifications, not layout constants. Do not infer logical points, scale, safe-area insets, or breakpoint values from them. [S2]
- The developer landing page currently advertises **Xcode 27.1 Release Candidate**. Apple identifies the Duo simulator and Device Hub as the native test route. Verify the exact installed build and runtime before executing or claiming native validation. [S3, S4]
- The SDK linked at build time affects presentation: iOS 26 and earlier use compatibility layout; iOS 27 expands dynamically but still avoids the right-side status region; iOS 27.1 enables full-display layout with adapted bars. Building with a newer SDK does not itself require setting the application's deployment target to that SDK version. [S4]

## 2. Verified design implications

### Resizability and navigation

Use available scene/view geometry and size classes, not device-name checks, screen-size tables, phone-versus-pad assumptions, or physical orientation as the layout model. Remove cached `UIScreen.main` assumptions. A window can resize during an active session. [S4]

Native navigation containers and toolbars are the first option. Safe areas and margins can be asymmetric; split-view placement changes which outer edge contains controls. Foreground controls must remain reachable. Only backgrounds should routinely extend outside safe areas. [S5]

Side-positioned bars share space with navigation, tabs, system status, and activities. Inner-display portrait can use horizontal bars. Plan for overflow and avoid treating a particular corner as a permanently available action location. Custom wide controls need intentional representation rather than forced rotation. [S6]

### Fold regions and state

Reserved-region and arrangement concepts support fold-aware layout. Continuous scrolling lists should not be needlessly displaced into separate regions. Custom visual effects may observe hinge state, but layout should generally use geometry and region APIs. No capability should require a particular pose. [S7, S8]

Navigation state should be independent of whether a screen is displayed as a compact stack or an expanded composition. Preserve the selected record and editing workflow during transitions. [S9]

Do not use `scenePhase` as a fold detector. Apple's DTS describes full-screen transitions that adjust traits and scene size without a scene-state change. With multiple windows, closing the device can background a secondary scene while keeping the recently active scene available. [S10]

### Multiwindow and external-display boundaries

Split View participation is different from offering additional windows of the same app. New same-app windows are dynamically available on the inner display, not the outer display; requests must handle unavailability. A supported camera accessory is not a general permission or API for mirroring arbitrary medical content to the outer display. [S8]

## 3. API verification ledger

The following names appear in Apple material; **they are research leads, not compile-verified declarations**. This document intentionally supplies no inferred function signatures.

| Name or concept | Evidence | Applicability and unresolved checks |
| --- | --- | --- |
| `NavigationStack`, `NavigationSplitView`, `TabView`, toolbar | S5, S6 | Preferred native containers. Verify current project deployment target and navigation ownership before changes. |
| `GeometryReader`, `onGeometryChange`, size-class and display-scale environment values | S4, S5 | Use local geometry; confirm exact availability for every symbol used in the existing deployment range. |
| `ReservedRegion`, geometry reserved-region queries | S5, S7, S11 | Duo guidance references these APIs. Exact SDK declarations, spelling, overloads, platform annotations, and runtime behavior require inspection of the selected SDK. |
| `ArrangementView` and arrangement types | S7 | Optional for an intentional paired-content layout. Do not introduce merely to create two columns. Exact availability and declarations unverified. |
| `onHingeChange`, `UIHingeInteraction` | S8 | Described for live interaction/effects, not the primary layout classifier. SDK declaration and availability unverified. |
| `CameraCaptureAccessory`, scene accessories | S8 | Camera-specific conditions apply. Outside the initial MedCue demonstration scope. SDK annotations and capabilities unverified. |
| `UIWindowSceneActivationAction` | S8 | Apple describes dynamic hiding when new windows are unavailable. Exact integration and availability unverified. |
| `performAccessibilityAudit` | S12 | Useful UI-test audit, not a substitute for assistive-technology testing. Confirm runner/SDK availability. |

Gate all newly adopted APIs using the actual SDK declarations and preserve older-system behavior. Do not assume a symbol exists in the cloud toolchain solely because a current web page names it.

## 4. Proposed MedCue experience

These are product/engineering recommendations, not Apple requirements.

1. **Compact clarity:** retain a calm Today screen with the next medication action, clear time and dose, and an explicit confirmation flow. Long names and larger text must remain readable.
2. **Expanded usefulness:** use extra space for an intentional relationship, such as today's schedule next to selected medication details. Avoid merely stretching cards. Preserve the same content hierarchy and core actions.
3. **Continuity as the demo:** begin editing a synthetic medication in compact layout, expand to the richer presentation, then return without losing input or selection. Record a dose once and show consistent status wherever the app exposes it.
4. **Accessible beauty:** prioritize typography, spacing, restrained color, understandable state labels, and subtle transitions. Never use animation or color as the sole indicator of a medication action.
5. **Honest evidence:** cloud previews and deterministic state tests can establish design and model behavior. Label native system bars, folding behavior, notification presentation, and device performance as unverified until exercised in the actual runtime.

## 5. Cross-surface and data requirements

### Notifications

Keep reminder scheduling independent of view creation and layout changes. Test permission-denied handling, foreground/background delivery, cold-start routing, edited/cancelled schedules, time-zone changes, and repeat action delivery. A second scene must not accidentally schedule another copy of the same reminder. Apple documents system-managed delivery of scheduled local notifications. [S13]

### Widgets and privacy

Inspect supported widget families, Lock Screen, Always On, StandBy, and expanded-device presentation. Consider medication name, dose, and adherence status private. Apple's privacy-sensitive presentation controls and data-protection options are distinct mechanisms; visual redaction is not evidence that protected storage is unreadable. Preserve existing protection and do not weaken it to force a test to pass. [S14]

### Live Activities

Review the changed vertical system presentation on Duo. Do not assume an older horizontal composition remains legible. Apple's general ActivityKit guidance gives bounded activity lifetime; a Live Activity is not a replacement for a durable medication reminder schedule. Exact Duo presentation dimensions and supported variants must be verified with the runtime rather than extrapolated. [S1, S15]

### Watch

This research found no official requirement for a Duo-specific WatchConnectivity protocol. Existing companion behavior still needs duplicate-action handling, disconnected recovery, and appropriate distinction between latest-state snapshots and queued events. Apple requests physical iPhone and Apple Watch for its connectivity sample, so cloud-only tests cannot establish real paired-device delivery. [S16]

### Persistence and concurrency

Preserve the existing authoritative medication/dose model. Where the product already supports multiple scenes, keep navigation scene-local. Select idempotency checks for existing supported action origins, such as notification actions or Watch; do not create new windows or widget actions to satisfy the inventory. Re-layout, reappearance, and scene restoration must not create additional dose records. Use synthetic data for all public fixtures, screenshots, and logs.

## 6. Verification risk inventory

This is a broad research inventory, not a requirement to rebuild all product surfaces. The coordinator’s plan.md selects change-relevant acceptance checks for each slice. Same-app multiwindow checks apply only if the product already supports that behavior; do not add multiwindow architecture to satisfy this inventory.

| Axis | Candidate coverage, selected by change impact |
| --- | --- |
| Geometry | Outer portrait/landscape; inner fully open in both orientations; book/tabletop/tent; left/right Split View; available height reduced by system multitasking |
| Workflows | Today, list/detail, add/edit, confirmation, history, settings, empty/error states |
| Transitions | Mid-edit resize; sheet/alert visible during change; selected detail into split layout; background/foreground; notification deep link; secondary scene becoming inactive |
| Correctness | Draft and selected record retained; no duplicate dose mutation; no duplicate reminders; stale/deleted-record links handled safely |
| Accessibility | Dynamic Type including largest accessibility sizes; VoiceOver focus/order; reduced motion; increased contrast; reduced transparency; sufficient hit regions |
| Localization | Chinese/English, long medication labels, RTL presentation; no assumption that the system bar mirrors with text direction |
| Privacy | Lock Screen/Always On; first unlock after restart; app-switcher snapshot; logs and attachments free of real health information |
| Compatibility | Minimum supported OS; ordinary iPhone; iPad if supported; companion targets if present |

For automated accessibility audits, test individual workflow screens and follow with VoiceOver testing. Passing the audit does not establish complete accessibility. [S12]

### Smallest useful cloud-only milestone

- Inventory project targets, deployment versions, existing tests, and layout/state ownership.
- Scan for hard-coded geometry, cached global screens, orientation branches, single-window assumptions, and view-lifecycle side effects.
- Add deterministic tests for independent navigation state, draft preservation, and duplicate-action handling where existing architecture permits.
- Produce reviewable compact and expanded compositions with synthetic medication fixtures, keeping the same task hierarchy.
- Record the exact evidence obtained and the native-runtime checks still pending.

### Native acceptance milestone, pending an appropriate environment

Build with verified Xcode 27.1 and the corresponding Duo runtime; edit a synthetic medication on the outer display; open and close the simulated device; verify draft/navigation continuity, primary-action reachability, and one committed record; repeat on both sides of Split View. Save screenshots and test output tied to the commit and toolchain.

This milestone does not authorize initiating work on a Mac for the current cloud-only task.

## 7. Known blockers and uncertainty

- **No installed-toolchain evidence in this research.** A web announcement is not proof that the selected execution environment has Xcode 27.1, the runtime, or runnable UI tests.
- **CLI posture control remains unresolved here.** An Apple forum question asks for supported programmatic unfolding and contains no Apple answer on the page inspected. Do not invent `simctl` posture commands or rely on hidden preferences. Official Device Hub controls are documented. [S5, S17]
- **Live-resize UI-test geometry can be unreliable.** An Apple DTS response to stale accessibility frames recommends checking content shapes and filing a reproducible Feedback report if the issue persists; it does not establish a deterministic refresh workaround. Cross-check screenshots and app-reported geometry before attributing such failure to the app. [S18]
- **Physical behavior remains unverified.** Actual visibility, reachability, performance, camera behavior, haptics, and paired-Watch delivery require the relevant hardware.
- **API annotations remain unverified.** Consult installed SDK declarations before writing implementation-specific signatures or asserting deployment availability.
- **Submission is a separate workstream.** Apple's October 5 announcement permits Duo-optimized submissions and states that Duo screenshots will become required in April 2027. Preparing an adaptation plan does not authorize submission or release. [S19]

## Sources and date provenance

All sources below are Apple-owned and were accessed **2026-10-09 UTC**. Where the inspected page did not supply an absolute publication/update date, this is explicitly marked unknown. Relative forum ages are not converted into invented calendar dates.

| ID | Official source | Publication/update date visible in inspected evidence |
| --- | --- | --- |
| S1 | [Apple unveils iPhone Duo](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/) | 2026-09-09 |
| S2 | [iPhone Duo technical specifications](https://www.apple.com/iphone-duo/specs/) | Unknown; live product specifications |
| S3 | [Get ready for iPhone Duo](https://developer.apple.com/iphone-duo/) | Unknown; live developer landing page |
| S4 | [Three steps to make your app shine on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/) | Unknown |
| S5 | [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) | Unknown; Tech Talk page |
| S6 | [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/) | Unknown; Tech Talk page |
| S7 | [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/) | Unknown; Tech Talk page |
| S8 | [Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/) | Unknown; Tech Talk page |
| S9 | [Navigation Across Duo for a Linear Flow](https://developer.apple.com/forums/thread/847818) | Unknown absolute date; Apple DTS answer visible |
| S10 | [ScenePhase call](https://developer.apple.com/forums/thread/847838) | Unknown absolute date; Apple DTS answer visible |
| S11 | [Recommended SwiftUI API for observing fold posture](https://developer.apple.com/forums/thread/847888) | Unknown absolute date; Apple DTS answer visible |
| S12 | [Performing accessibility audits for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app) | Unknown |
| S13 | [Scheduling and Handling Local Notifications](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html) | Unknown absolute update date; archived guide, used only for stable scheduling concepts |
| S14 | [Creating a widget extension](https://developer.apple.com/documentation/WidgetKit/Creating-a-Widget-Extension) | Unknown |
| S15 | [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) | Unknown; general ActivityKit guidance, not Duo-specific measurements |
| S16 | [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity) | Unknown |
| S17 | [Supported way to unfold the Duo simulator programmatically](https://developer.apple.com/forums/thread/847883) | Unknown absolute date; community question and replies, no Apple resolution visible |
| S18 | [XCUITest accessibility snapshot during live scene resize](https://developer.apple.com/forums/thread/847880) | Unknown absolute date; Apple DTS response visible |
| S19 | [Prepare and submit your apps for iPhone Duo](https://developer.apple.com/news/?id=kkphp5qo) | 2026-10-05 |
| S20 | [Designing for iPhone Duo — HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) | 2026-09-09, page change log |
| S21 | [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/) | Unknown; Tech Talk page |

Documentation pages that required JavaScript were corroborated with Apple-hosted rendered search content, available documentation data, or the linked official video transcript. No third-party article or forum participant assertion is treated as an Apple API guarantee. S17 is retained only as evidence of an unresolved automation question.
