import Charts
import Combine
import MedicationAdherenceCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MedicationTrendDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTopic: MedicationTrendTopic = .discipline
    @State private var selectedDate: Date?
    @State private var timeContext = MedicationTrendTimeContext.current()

    var body: some View {
        MedicationTrendQueryView(
            timeContext: timeContext,
            selectedTopic: $selectedTopic,
            selectedDate: $selectedDate
        )
        .id(timeContext.revision)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            refreshTimeContext()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification
            )
        ) { _ in
            refreshTimeContext()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name.NSSystemTimeZoneDidChange
            )
        ) { _ in
            refreshTimeContext()
        }
    }

    private func refreshTimeContext() {
        timeContext = .current()
    }
}

private struct MedicationTrendQueryView: View {
    @Query(sort: \StoredDoseTask.dueAt, order: .reverse) private var tasks: [StoredDoseTask]
    @Query(sort: \StoredMedicationDoseChange.effectiveFrom, order: .reverse) private var doseChanges: [StoredMedicationDoseChange]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    @Query(sort: \StoredMedicationPlan.createdAt) private var plans: [StoredMedicationPlan]
    @Query(sort: \StoredMedicationLifecycleEvent.occurredAt, order: .reverse) private var lifecycleEvents: [StoredMedicationLifecycleEvent]
    @StateObject private var healthKitService = HealthKitService()
    @Binding private var selectedTopic: MedicationTrendTopic
    @Binding private var selectedDate: Date?
    @State private var dashboard: MedicationTrendDashboard
    private let timeContext: MedicationTrendTimeContext

    init(
        timeContext: MedicationTrendTimeContext,
        selectedTopic: Binding<MedicationTrendTopic>,
        selectedDate: Binding<Date?>
    ) {
        self.timeContext = timeContext
        _selectedTopic = selectedTopic
        _selectedDate = selectedDate
        _dashboard = State(
            initialValue: MedicationTrendProjection.emptyDashboard(
                timeContext: timeContext
            )
        )
        let calendar = timeContext.calendar
        let todayStart = calendar.startOfDay(for: timeContext.now)
        let queryStart = calendar.date(byAdding: .day, value: -120, to: todayStart) ?? todayStart.addingTimeInterval(-10_368_000)
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        _tasks = Query(
            filter: #Predicate<StoredDoseTask> { task in
                task.dueAt >= queryStart && task.dueAt < queryEnd
            },
            sort: \StoredDoseTask.dueAt,
            order: .reverse
        )
        _doseChanges = Query(
            filter: #Predicate<StoredMedicationDoseChange> { change in
                change.effectiveFrom >= queryStart
                    && change.effectiveFrom < queryEnd
            },
            sort: \StoredMedicationDoseChange.effectiveFrom,
            order: .reverse
        )
        _lifecycleEvents = Query(
            filter: #Predicate<StoredMedicationLifecycleEvent> { event in
                event.occurredAt >= queryStart && event.occurredAt < queryEnd
            },
            sort: \StoredMedicationLifecycleEvent.occurredAt,
            order: .reverse
        )
    }

    private var dashboardRevision: String {
        MedicationTrendProjection.revision(
            tasks: tasks.adherenceMeasurableTasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: healthKitService.recentTrendSamples,
            timeContext: timeContext
        )
    }

    private var selectedMetric: MedicationTrendMetric {
        dashboard.metrics.first { $0.topic == selectedTopic } ?? dashboard.metrics.first ?? emptyTrendMetric(topic: selectedTopic)
    }

    private var selectedPoint: MedicationTrendPoint? {
        let points = selectedMetric.points
        guard !points.isEmpty else {
            return nil
        }
        guard let selectedDate else {
            return points.last
        }
        return points.min { lhs, rhs in
            abs(trendDate(from: lhs.date).timeIntervalSince(selectedDate)) < abs(trendDate(from: rhs.date).timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        List {
            Section("用药趋势") {
                MedicationTrendDashboardCard(dashboard: dashboard)
            }

            Section("趋势主题") {
                MedicationTrendTopicPicker(selectedTopic: $selectedTopic, metrics: dashboard.metrics)
                    .padding(.vertical, 4)
                MedicationTrendMetricSummary(metric: selectedMetric)
            }

            Section("近期曲线") {
                if selectedMetric.points.isEmpty {
                    Text("还没有可用于趋势计算的服药记录。")
                        .foregroundStyle(.secondary)
                } else {
                    MedicationTrendLineChart(
                        metric: selectedMetric,
                        selectedDate: $selectedDate
                    )
                    .padding(.vertical, 8)

                    MedicationTrendEventLegend(metric: selectedMetric)

                    if let selectedPoint {
                        MedicationTrendPointDetail(point: selectedPoint, topic: selectedMetric.topic)
                    }
                }
            }

            Section("周期对比") {
                TrendPeriodComparisonPanel(metric: selectedMetric)
            }

        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 84)
        }
        .navigationTitle("用药趋势")
        .toolbar(.hidden, for: .tabBar)
        .task {
            await healthKitService.refreshRecentTrendSamples()
        }
        .task(id: dashboardRevision) {
            await refreshDashboard()
        }
    }

    @MainActor
    private func refreshDashboard() async {
        let input = MedicationTrendProjection.input(
            tasks: tasks.adherenceMeasurableTasks,
            doseChanges: doseChanges,
            medications: medications,
            plans: plans,
            lifecycleEvents: lifecycleEvents,
            healthSignals: healthKitService.recentTrendSamples,
            timeContext: timeContext
        )
        let updatedDashboard = await Task.detached(priority: .userInitiated) {
            input.build()
        }.value
        guard !Task.isCancelled else {
            return
        }
        dashboard = updatedDashboard
    }
}
