# Open Source Reference Log

This file records external open-source references considered or used during development, so competition materials can distinguish native implementation from reused work.

## 2026-06-05 v0.8 onboarding and appearance polish

- Scope: first-launch onboarding animation, dark product-demo presentation, Settings appearance preferences.
- External open-source code referenced: none.
- Implementation note: built with native SwiftUI views, animations and AppStorage preferences already available in the iOS app target.

## 2026-06-08 medication trend dashboard and HealthKit ingestion

- Scope: medication trend dashboard, HealthKit sample ingestion, trend chart visualization, adherence metric wording.
- External open-source code referenced: none.
- Official and conceptual references checked:
  - Apple HealthKit queries documentation: `HKSampleQuery` reads matching samples from the HealthKit store through `HKHealthStore.execute(_:)`, with predicates and sort descriptors used for filtering and ordering.
  - Apple Swift Charts documentation and WWDC material: `LineMark`, `AreaMark`, `PointMark`, `RuleMark` and chart selection patterns are suitable for interactive trend inspection.
  - Pharmacy Quality Alliance adherence measures: PQA describes PDC as a medication adherence method based on prescription claims coverage. This project only borrows the “coverage days” concept because the app does not have pharmacy claims, refill or plan enrollment data.
- Implementation note: built with native Swift, HealthKit and Swift Charts. The app reads only user-authorized HealthKit samples and maps them into `HealthSignalSample`; the core trend model uses reminder history, dose changes, medication context and health-signal stability without generating diagnosis, prescription, dose or efficacy recommendations.

## 2026-06-08 medication trend period comparison and confidence

- Scope: trend period comparison, confidence score, data-quality wording and contributor explanations.
- External open-source code referenced: none.
- Official and conceptual references checked:
  - Pharmacy Quality Alliance PDC adherence concept: used only as a conceptual reference for “coverage across days”; the app still does not compute clinical PDC because it lacks pharmacy claims, refill windows and enrollment denominator.
  - AdhereR medication adherence methodology: used as a conceptual reminder that adherence has multiple methods and should expose assumptions and visual evidence; no R code, formulas or package implementation were copied.
  - Apple HealthKit statistics/query documentation: supports thinking of health data as period-based authorized samples; current implementation keeps HealthKit inputs optional and non-diagnostic.
  - Apple Swift Charts documentation: line, area, point and rule marks remain the visualization pattern for period trends and point inspection.
- Implementation note: the core model now adds 近 7 天 vs 前 7 天 comparison, confidence score, evidence summary and contributor summary for each trend topic. Confidence is a transparent heuristic from recent day coverage, previous-period coverage, handled reminder coverage, scheduled-count density and optional HealthKit coverage. It is competition-demo logic for self-management visualization, not a medical device score.

## 2026-06-08 medication trend transparent formula summaries

- Scope: explainable formula summary and model weight display for every medication-trend topic.
- External open-source code referenced: none.
- Official and conceptual references checked:
  - PQA/PDC concept remains only a conceptual reference for coverage across days; no claims, refill windows or clinical denominator are available in this app.
  - AdhereR adherence-method literature reinforces that adherence metrics should expose assumptions and method choice; no package code or formula implementation was copied.
  - Apple Health and Swift Charts patterns remain the UI reference for period comparison, line/area trend display and point inspection.
- Implementation note: each trend topic now outputs a Chinese `formulaSummary` alongside weighted components. The formulas are transparent heuristics over app records, medication context and authorized HealthKit samples; they explicitly avoid diagnosis, prescription, dose adjustment or efficacy claims.

## 2026-06-08 medication trend point decomposition

- Scope: interactive point-level explanation for trend charts.
- External open-source code referenced: none.
- Conceptual reference checked: Apple Health-style trend inspection and Swift Charts point selection patterns remain the interaction model; point details should explain what changed at that date without overstating medical meaning.
- Implementation note: each `MedicationTrendPoint` now carries its own weighted formula components. The app can show the selected date's data counts and component scores directly, while aggregate formula components remain a recent-period summary.

## 2026-06-08 medication trend event markers

- Scope: visible event markers and legends on medication trend charts.
- External open-source code referenced: none.
- Official and conceptual references checked:
  - PQA Proportion of Days Covered concept: still used only as a conceptual reference for day coverage and adherence vocabulary; the app does not have prescription claims or refill windows, so it does not claim to compute clinical PDC.
  - AdhereR adherence-method literature and package documentation: reinforces separating observation windows, event episodes and metric assumptions; no R implementation, package code or formula was copied.
  - Apple Health Trends and Swift Charts interaction patterns: used as UI inspiration for line/area trends, point inspection and contextual annotations.
- Implementation note: the iOS trend chart now overlays event markers for dose changes, lifecycle changes and authorized HealthKit samples. A legend explains marker colors and reiterates that event markers only help explain record changes, not diagnosis, dose advice or efficacy.

## 2026-06-08 medication trend completion audit references

- Scope: final audit of the “用药趋势” mathematical model, source traceability, and runtime evidence.
- External open-source code referenced: none.
- Traceable references:
  - PQA adherence measures: https://www.pqaalliance.org/adherence-measures
    - PQA describes PDC as an adherence method based on prescription-claims coverage. The app does not have claims, refill, days-supply, enrollment or therapeutic-class denominators, so the model deliberately avoids calling its score PDC.
  - AdhereR open-source adherence analysis: https://www.adherer.eu/
    - Used as a conceptual reference for transparent assumptions, multiple adherence-estimation methods and patient-history visualization. No R package code, formulas or implementation details were copied.
  - AdhereR package index and GitHub URL listing: https://rdrr.io/cran/AdhereR/
    - Confirms the package’s focus on adherence estimates, plotting, medication history exploration and parameter settings; used only to shape documentation expectations around transparency.
  - Apple HealthKit queries documentation: https://developer.apple.com/documentation/healthkit/queries
    - Supports the iOS adapter design that reads authorized samples with HealthKit queries, predicates and sorting, then maps them into core `HealthSignalSample` values.
  - Apple Swift Charts documentation: https://developer.apple.com/documentation/charts
    - Supports the native chart choice: `LineMark`, `AreaMark`, `PointMark`, `RuleMark`, axis marks and chart selection for Apple Health-style point inspection.
- Implementation note: the current model remains a native Swift heuristic for self-management visualization. It uses app reminders and user actions as the primary denominator, adds dose changes and medication lifecycle events as explanatory context, and treats HealthKit values as optional authorized signals. It does not diagnose, prescribe, adjust dose, evaluate treatment efficacy or compute a clinical PDC/MPR measure.

## 2026-06-08 integration debug pass references

- Scope: branch-contribution audit, risk page grouping wording, weather reminder fallback wording, notification-reminder logic sanity check, and runtime UI verification.
- External open-source code referenced: none.
- Official and conceptual references checked:
  - FDA drug-interaction patient information: https://www.fda.gov/drugs/resources-drugs/drug-interactions-what-you-should-know
    - Supports keeping the risk page grouped around drug-drug, drug-food/beverage or lifestyle, and drug-condition attention categories.
  - PQA measures resources: https://www.pqa.org/measures/measures-resources/
    - Rechecked for adherence wording, PDC as a claims-based coverage concept, and the common 80% adherence threshold. The app still uses its own reminder-record denominator rather than claiming clinical PDC.
  - Apple UserNotifications documentation: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests%28withidentifiers%3A%29
    - Rechecked the identifier-based pending notification cancellation route used by the reminder rescheduling flow.
  - Apple HealthKit `HKSampleQuery` documentation: https://developer.apple.com/documentation/healthkit/hksamplequery
    - Rechecked that authorized HealthKit samples should be queried and mapped by the iOS adapter before being interpreted by the pure Swift core model.
- Implementation note: this pass only used external sources for product and architecture sanity checks. No external code, formulas, UI components or copyrighted implementation were copied.

## 2026-06-08 trend model app implementation polish

- Scope: making the medication trend model more clearly usable inside the app, especially HealthKit empty states and separating future plans from actual records in the calendar.
- External open-source code referenced: none.
- Product and conceptual references checked:
  - PQA adherence measures: https://www.pqaalliance.org/adherence-measures
    - Reconfirmed that PDC is a claims-based coverage method and 80% is a common adherence threshold; the app only borrows the “coverage days” idea and does not call its reminder-record model clinical PDC.
  - EveryDose App Store listing: https://apps.apple.com/us/app/everydose-medication-reminder/id1188929364
    - Confirms product expectations around marking doses taken/skipped/snoozed, viewing medication history, health metrics charts, Apple Health syncing, refill reminders and reports.
  - EveryDose feature page: https://www.everydose.ai/app/features/
    - Confirms that history should distinguish taken/skipped doses and that weekly summaries are a normal medication-adherence product pattern.
- Implementation note: the iOS app now avoids showing HealthKit “0%” when there are no authorized samples, and the records calendar labels future reminders as planned items instead of incomplete records. No external implementation code was copied.
