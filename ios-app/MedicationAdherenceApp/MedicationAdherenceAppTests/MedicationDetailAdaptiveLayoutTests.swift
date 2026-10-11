import Foundation
import MedicationAdherenceCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MedicationAdherenceApp

/// Hosted integration coverage of the REAL detail view, on the ordinary iPhone CI destination.
/// Source baseline: 4d9c6d50d46a5735dc014da5434e1063d8cf7493.
/// Initial candidate MedicationDetailView.swift SHA-256:
/// 8265cff9295f182de1a49f2bb80d8c7de11b69fb19d50cd89e6469bb366c9ae2.
///
/// Exercises the REAL detail view's mounted List, trait transitions, rendered images,
/// and read-only store invariants. No screen-size/device skips, fake detail UI,
/// production visibility changes, persistent store, or action activation.
/// The 1024pt host is an offscreen-capable container, not a physical iPhone screen assertion.
/// Public in-process SwiftUI accessibility traversal is not a semantic oracle here.
/// Column positions, mirrored content, text presence/truncation and enabled controls
/// require separate app-process UI testing and screenshot review. Three images per
/// state sample top/middle/bottom; they do not cover every pixel of the scrolled content.
/// The file-private Layout types cannot be directly fed nil/zero/infinite proposals here.
final class MedicationDetailAdaptiveLayoutTests: XCTestCase {
    @MainActor
    func testRealDetailRendersAndPreservesStoreAcrossNarrowWideNarrow() throws {
        let harness = try DetailLayoutHarness()
        defer { harness.close() }
        for (step, width) in [CGFloat(320), 1024, 320].enumerated() {
            harness.resize(width: width, category: .large)
            try inspect(harness, name: "resize-\(step)-\(Int(width))")
        }
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    func testRealDetailRendersAndPreservesStoreAcrossAX5AndRestoredTraits() throws {
        let harness = try DetailLayoutHarness()
        defer { harness.close() }
        for width in [CGFloat(320), 1024] {
            harness.resize(width: width, category: .accessibilityExtraExtraExtraLarge)
            try inspect(harness, name: "AX5-\(Int(width))")
        }
        // Same hosting controller and model, restoring the real UIKit trait override.
        harness.resize(width: 1024, category: .large)
        try inspect(harness, name: "AX5-restored")
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    func testRealDetailRendersAndPreservesStoreWithRTLTraitsAcrossResize() throws {
        let harness = try DetailLayoutHarness(rightToLeft: true)
        defer { harness.close() }
        for width in [CGFloat(320), 1024] {
            harness.resize(width: width, category: .large)
            try inspect(harness, name: "RTL-\(Int(width))")
        }
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    private func inspect(_ harness: DetailLayoutHarness, name: String) throws {
        harness.geometryDiagnosticPhase = name
        let scroll = try harness.waitForMountedList()
        _ = try harness.waitForStableGeometry(in: scroll)
        let initial = try harness.waitForStableGeometry(in: scroll, seeking: .top)
        XCTAssertEqual(initial.offset.y, initial.top, accuracy: 1, "\(name): must start at List top")
        XCTAssertGreaterThan(initial.bottom - initial.top, 1,
                             "\(name): fixture must exercise vertical scrolling")
        attach(harness, name: name + "-top")

        var geometry = initial
        var reachedEnd = false
        var capturedMiddle = false
        // Walk overlapping visible content viewports, including materialized lazy rows.
        // This proves scroll geometry/traversal, not text or control accessibility.
        // A finite limit fails rather than silently accepting incomplete traversal.
        for _ in 0..<100 {
            XCTAssertLessThanOrEqual(geometry.size.width + geometry.insets.left + geometry.insets.right,
                                     geometry.bounds.width + 2,
                                     "\(name): List must not require horizontal scrolling")
            XCTAssertEqual(geometry.offset.x, -geometry.insets.left, accuracy: 1,
                           "\(name): horizontal offset must stay at its leading boundary")
            // UIScrollView quantizes offsets to device pixels. Use the same 1pt
            // position tolerance as top/bottom/seek, while requiring an interior sample.
            if !capturedMiddle && geometry.offset.y >= geometry.midpoint - 1 {
                guard geometry.offset.y > geometry.top && geometry.offset.y < geometry.bottom else {
                    throw harness.traversalFailure("\(name): middle sample must be strictly interior", scroll: scroll)
                }
                attach(harness, name: name + "-middle")
                capturedMiddle = true
            }
            if abs(geometry.offset.y - geometry.bottom) <= 1 {
                reachedEnd = true
                break
            }
            let previous = geometry
            var target = min(previous.bottom, previous.offset.y + previous.viewport.height * 0.55)
            // Stop exactly at the current range midpoint before crossing it, even when
            // the entire range is shorter than one step. Middle must not mean bottom.
            let midpoint = previous.midpoint
            if !capturedMiddle && previous.offset.y < midpoint {
                target = min(target, midpoint)
            }
            // Freeze this bounded step's coordinate. Lazy measurement can increase
            // the content extent while seeking; chasing its new bottom/midpoint here
            // could jump past an unvisited viewport. Recompute extents next iteration.
            geometry = try harness.waitForStableGeometry(in: scroll, seeking: .offset(target))
            guard geometry.offset.y > previous.offset.y else {
                throw harness.traversalFailure("\(name): no forward progress from \(previous.offset.y)", scroll: scroll)
            }
            guard geometry.offset.y - previous.offset.y <= previous.viewport.height + 1 else {
                throw harness.traversalFailure("\(name): viewport gap after \(previous.offset.y), previous height=\(previous.viewport.height)", scroll: scroll)
            }
        }
        guard reachedEnd && capturedMiddle else {
            throw harness.traversalFailure("\(name): incomplete traversal; reachedEnd=\(reachedEnd), capturedMiddle=\(capturedMiddle)", scroll: scroll)
        }
        XCTAssertEqual(geometry.offset.y, geometry.bottom, accuracy: 1,
                       "\(name): final viewport must reach List bottom")
        attach(harness, name: name + "-bottom")
        // Explicit return to top also checks that the same mounted List remains scrollable.
        let restored = try harness.waitForStableGeometry(in: scroll, seeking: .top)
        XCTAssertEqual(restored.offset.y, restored.top, accuracy: 1,
                       "\(name): List must return to its top boundary")
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    private func attach(_ harness: DetailLayoutHarness, name: String) {
        let image = UIGraphicsImageRenderer(bounds: harness.host.view.bounds).image { _ in
            XCTAssertTrue(harness.host.view.drawHierarchy(in: harness.host.view.bounds, afterScreenUpdates: true),
                          "Snapshot rendering must succeed")
        }
        XCTAssertEqual(CGFloat(image.cgImage?.width ?? 0), harness.host.view.bounds.width * image.scale, accuracy: 1)
        XCTAssertEqual(CGFloat(image.cgImage?.height ?? 0), harness.host.view.bounds.height * image.scale, accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "MedicationDetail-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class DetailLayoutHarness {
    static let medicationName = "合成布局测试药品"
    static let genericName = "合成通用名：用于验证长内容换行，不代表真实药品或用药建议"
    static let planNote = "合成疗程说明：这是一段用于窄宽度和最大字体排版的固定长文本。"
    let container: ModelContainer
    let medication: StoredMedication
    let window: UIWindow
    let parent: UIViewController
    let host: UIHostingController<AnyView>
    let rightToLeft: Bool
    private weak var previousKeyWindow: UIWindow?
    private let initialSnapshot: [String: [AnyHashable]]
    var geometryDiagnosticPhase = "unassigned"
    private var didReportGeometryFailure = false

    init(rightToLeft: Bool = false) throws {
        self.rightToLeft = rightToLeft
        container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        container.mainContext.autosaveEnabled = false
        medication = StoredMedication(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000161")!,
            displayName: Self.medicationName,
            genericName: Self.genericName,
            kind: .overTheCounter,
            form: "合成片剂",
            strength: "10 mg（仅合成测试）",
            inputSource: .manual,
            boxNumber: "SYNTHETIC-161",
            notes: "固定合成布局夹具，不含真实健康信息。",
            isDemoContent: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        container.mainContext.insert(medication)
        let plan = StoredMedicationPlan(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000162")!,
            medicationID: medication.id,
            doseValue: 1,
            doseUnit: "片",
            timingSummary: "固定合成提醒时间",
            timeZonePolicy: .localClock,
            sourceNote: Self.planNote,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        container.mainContext.insert(plan)
        container.mainContext.insert(StoredDoseTask(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000163")!,
            medicationID: medication.id,
            planID: plan.id,
            dueAt: Date(timeIntervalSince1970: 1_700_003_600),
            doseValue: 1,
            doseUnit: "片",
            status: .taken,
            recordedAt: Date(timeIntervalSince1970: 1_700_003_600)
        ))
        try container.mainContext.save()
        initialSnapshot = try Self.snapshot(container.mainContext)
        let medicationForView = medication
        // All queries use the production schema and this same saved in-memory model.
        host = UIHostingController(rootView: AnyView(
            NavigationStack {
                MedicationDetailView(medication: medicationForView)
            }
            .modelContainer(container)
            .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        ))
        parent = UIViewController()
        // A scene-based app must attach the synthetic window to an existing foreground scene.
        // Read only scene/window metadata here, never the existing windows' view/AX contents.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive && $0.keyWindow != nil }
            ?? scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
        guard let scene else {
            throw HarnessFailure.noForegroundWindowScene(
                "connectedWindowScenes=\(scenes.count), activationStates=\(scenes.map { $0.activationState.rawValue })"
            )
        }
        previousKeyWindow = scene.keyWindow
        // The existing scene owns this window. Explicit bounds still exercise a 1024pt
        // container on iPhone CI; this is not a physical-screen visibility assertion.
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 900)
        window.rootViewController = parent
        parent.loadViewIfNeeded()
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        window.makeKeyAndVisible()
        resize(width: 320, category: .large)
    }

    func resize(width: CGFloat, category: UIContentSizeCategory) {
        let sizeClass: UIUserInterfaceSizeClass = width >= 600 ? .regular : .compact
        parent.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: sizeClass),
            UITraitCollection(preferredContentSizeCategory: category),
            UITraitCollection(layoutDirection: rightToLeft ? .rightToLeft : .leftToRight)
        ]), forChild: host)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        parent.view.frame = window.bounds
        host.view.frame = parent.view.bounds
        settle()
        XCTAssertNotNil(window.windowScene)
        XCTAssertTrue(host.view.window === window)
        XCTAssertFalse(window.isHidden || host.view.isHidden)
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 0.5)
        XCTAssertEqual(host.traitCollection.horizontalSizeClass, sizeClass)
        XCTAssertEqual(host.traitCollection.preferredContentSizeCategory, category)
        XCTAssertEqual(host.traitCollection.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    }

    func settle() {
        parent.view.setNeedsLayout()
        parent.view.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        host.view.layoutIfNeeded()
    }

    var descendantViews: [UIView] {
        func collect(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(collect) }
        return collect(host.view)
    }

    struct ListGeometry {
        let bounds: CGRect
        let size: CGSize
        let offset: CGPoint
        let insets: UIEdgeInsets
        let viewport: CGRect

        var top: CGFloat { -insets.top }
        var bottom: CGFloat { max(top, size.height - bounds.height + insets.bottom) }
        var midpoint: CGFloat { top + (bottom - top) / 2 }
        var scalars: [CGFloat] {
            [bounds.minX, bounds.minY, bounds.width, bounds.height, size.width, size.height,
             offset.x, offset.y, insets.top, insets.left, insets.bottom, insets.right,
             viewport.minX, viewport.minY, viewport.width, viewport.height]
        }
        var isValid: Bool {
            scalars.allSatisfy { $0.isFinite }
                && bounds.width > 0 && bounds.height > 0 && size.width > 0 && size.height > 0
                && viewport.width > 0 && viewport.height > 0
                && offset.y >= top - 1 && offset.y <= bottom + 1
        }
        func isClose(to other: ListGeometry) -> Bool {
            zip(scalars, other.scalars).allSatisfy { abs($0.0 - $0.1) <= 0.5 }
        }
    }

    func waitForMountedList() throws -> UIScrollView {
        let deadline = Date(timeIntervalSinceNow: 3)
        repeat {
            settle()
            if let list = descendantViews.compactMap({ $0 as? UIScrollView })
                .filter({ $0.bounds.width > 100 && $0.bounds.height > 100 && $0.contentSize.height > 0 })
                .max(by: { $0.bounds.height < $1.bounds.height }) { return list }
        } while Date() < deadline
        throw HarnessFailure.listDidNotMount(diagnostics(scroll: nil))
    }

    func contentViewport(of scroll: UIScrollView) -> CGRect {
        scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            .intersection(host.view.convert(host.view.bounds, to: window))
            .intersection(window.bounds)
    }

    enum ScrollPosition {
        case top
        case offset(CGFloat)

        func target(in geometry: ListGeometry) -> CGFloat {
            switch self {
            case .top: geometry.top
            case .offset(let value): value
            }
        }
    }

    func waitForStableGeometry(in scroll: UIScrollView, seeking position: ScrollPosition? = nil) throws -> ListGeometry {
        // One deadline covers layout and target reacquisition together. Lazy row
        // measurement may rebase an initially requested offset; never accept a stable
        // but wrong position or broaden tolerance to hide that correction.
        let deadline = Date(timeIntervalSinceNow: 3)
        var previous: ListGeometry?
        var stableSamples = 0
        var corrections: [String] = []
        let diagnosticStarted = ProcessInfo.processInfo.systemUptime
        var diagnosticSamples: [GeometryDiagnosticSample] = []
        var diagnosticIterations = 0
        repeat {
            let settleStarted = ProcessInfo.processInfo.systemUptime
            settle()
            let settleElapsed = ProcessInfo.processInfo.systemUptime - settleStarted
            let current = ListGeometry(bounds: scroll.bounds, size: scroll.contentSize,
                                       offset: scroll.contentOffset, insets: scroll.adjustedContentInset,
                                       viewport: contentViewport(of: scroll))
            diagnosticIterations += 1
            if diagnosticSamples.count == 8 { diagnosticSamples.removeFirst() }
            diagnosticSamples.append(GeometryDiagnosticSample(
                iteration: diagnosticIterations,
                elapsed: ProcessInfo.processInfo.systemUptime - diagnosticStarted,
                settleElapsed: settleElapsed, geometry: current, stableBefore: stableSamples
            ))
            if current.isValid && scroll.window === window && !scroll.isHidden && scroll.alpha > 0 {
                if let position {
                    // Returning to top tracks its current inset. Traversal steps keep
                    // their bounded coordinate and fail if it becomes unreachable.
                    let target = position.target(in: current)
                    guard target.isFinite && target >= current.top - 1 && target <= current.bottom + 1 else {
                        throw traversalFailure("Invalid seek target=\(target), top=\(current.top), bottom=\(current.bottom)", scroll: scroll)
                    }
                    if abs(current.offset.y - target) > 1 || abs(current.offset.x + current.insets.left) > 1 {
                        if corrections.count < 8 {
                            corrections.append("target=\(target), actual=\(current.offset), size=\(current.size), insets=\(current.insets)")
                        }
                        scroll.setContentOffset(CGPoint(x: -current.insets.left, y: target), animated: false)
                        stableSamples = 0
                        previous = nil
                        continue
                    }
                }
                stableSamples = previous.map { current.isClose(to: $0) } == true ? stableSamples + 1 : 1
                if stableSamples >= 3 { return current }
                previous = current
            } else {
                stableSamples = 0
                previous = nil
            }
        } while Date() < deadline
        let seekDetails = "seek=\(String(describing: position)), stableSamples=\(stableSamples), corrections=\(corrections)"
        reportGeometryFailure(samples: diagnosticSamples, iterations: diagnosticIterations,
                              elapsed: ProcessInfo.processInfo.systemUptime - diagnosticStarted,
                              stableSamples: stableSamples, seeking: position)
        throw HarnessFailure.listGeometryDidNotStabilize(seekDetails + "\n" + diagnostics(scroll: scroll))
    }

    private struct GeometryDiagnosticSample {
        let iteration: Int
        let elapsed: TimeInterval
        let settleElapsed: TimeInterval
        let geometry: ListGeometry
        let stableBefore: Int
    }

    /// Numeric metadata from this private, saved in-memory synthetic host only.
    /// One failure event per harness; last 8 samples, at most 12 lines / 5KB.
    private func reportGeometryFailure(
        samples: [GeometryDiagnosticSample], iterations: Int, elapsed: TimeInterval,
        stableSamples: Int, seeking position: ScrollPosition?
    ) {
        guard !didReportGeometryFailure else { return }
        didReportGeometryFailure = true
        let allowedPhases = ["resize-0-320", "resize-1-1024", "resize-2-320",
                             "AX5-320", "AX5-1024", "AX5-restored", "RTL-320", "RTL-1024"]
        let phase = allowedPhases.contains(geometryDiagnosticPhase) ? geometryDiagnosticPhase : "<redacted>"
        let seek: String = switch position {
        case .none: "none"
        case .some(.top): "top"
        case .some(.offset(let target)): "offset(\(target))"
        }
        let prefix = "[MedCueSyntheticLayoutDiagnostic] "
        var lines = 0
        var bytes = 0
        var truncated = false
        func emit(_ fields: String) {
            let output = prefix + fields
            let size = output.utf8.count + 1
            guard lines < 11, bytes + size <= 4_800 else { truncated = true; return }
            print(output)
            lines += 1
            bytes += size
        }
        emit("phase=\(phase) seek=\(seek) elapsed=\(String(format: "%.3f", elapsed))"
             + " iterations=\(iterations) finalStableSamples=\(stableSamples) requiredSamples=3"
             + " deadlineSeconds=3 targetTolerance=1 geometryTolerance=0.5"
             + " sampleLimit=8 retainedSamples=\(samples.count) samplesOmitted=\(iterations - samples.count)")
        var previous: ListGeometry?
        for sample in samples {
            let geometry = sample.geometry
            let delta = previous.map { before in
                zip(geometry.scalars, before.scalars).map { abs($0.0 - $0.1) }.max() ?? 0
            }.map { String(format: "%.3f", Double($0)) } ?? "none"
            emit("iteration=\(sample.iteration) elapsed=\(String(format: "%.3f", sample.elapsed))"
                 + " settleSeconds=\(String(format: "%.3f", sample.settleElapsed)) stableBefore=\(sample.stableBefore)"
                 + " bounds=\(geometry.bounds) size=\(geometry.size) offset=\(geometry.offset)"
                 + " insets=\(geometry.insets) viewport=\(geometry.viewport) maxScalarDelta=\(delta)")
            previous = geometry
        }
        if truncated {
            // 200 bytes and one line were reserved for this explicit marker.
            print(prefix + "outputTruncated=true lineLimit=12 byteLimit=5000")
        }
    }

    func traversalFailure(_ message: String, scroll: UIScrollView) -> Error {
        HarnessFailure.listTraversalFailed(message + "\n" + diagnostics(scroll: scroll))
    }

    private func diagnostics(scroll: UIScrollView?) -> String {
        // Only the synthetic hosting subtree is sampled; never inspect another app window.
        let sceneState = window.windowScene.map { String($0.activationState.rawValue) } ?? "none"
        let geometry = [
            "sceneAttached=\(window.windowScene != nil), sceneActivationState=\(sceneState)",
            "window.frame=\(window.frame), window.bounds=\(window.bounds), hidden=\(window.isHidden), alpha=\(window.alpha), key=\(window.isKeyWindow)",
            "host.frame=\(host.view.frame), host.bounds=\(host.view.bounds), attachedToTestWindow=\(host.view.window === window)",
            "parent.frame=\(parent.view.frame), parent.bounds=\(parent.view.bounds), descendantViews=\(descendantViews.count)"
        ].joined(separator: "\n")
        let scrollGeometry: String
        if let scroll {
            scrollGeometry = "viewport=\(contentViewport(of: scroll)), scroll.frame=\(scroll.frame), scroll.bounds=\(scroll.bounds), "
                + "contentSize=\(scroll.contentSize), contentOffset=\(scroll.contentOffset), adjustedInsets=\(scroll.adjustedContentInset)"
        } else {
            scrollGeometry = "viewport=unavailable; no mounted nonzero List"
        }
        return geometry + "\n" + scrollGeometry
    }

    private enum HarnessFailure: LocalizedError, CustomStringConvertible {
        case noForegroundWindowScene(String)
        case listDidNotMount(String)
        case listGeometryDidNotStabilize(String)
        case listTraversalFailed(String)

        var description: String {
            switch self {
            case .noForegroundWindowScene(let details): "noForegroundWindowScene: " + details
            case .listDidNotMount(let details): "listDidNotMount: " + details
            case .listGeometryDidNotStabilize(let details): "listGeometryDidNotStabilize: " + details
            case .listTraversalFailed(let details): "listTraversalFailed: " + details
            }
        }

        var errorDescription: String? { description }
    }

    func assertFixtureUnchanged() throws {
        XCTAssertEqual(try Self.snapshot(container.mainContext), initialSnapshot,
                       "Viewing/resizing must preserve every fixture field and model count")
        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertEqual(try Self.snapshot(ModelContext(container)), initialSnapshot,
                       "A saved mutation must not escape detection by clearing hasChanges")
    }

    private static func snapshot(_ context: ModelContext) throws -> [String: [AnyHashable]] {
        let medication = try XCTUnwrap(context.fetch(FetchDescriptor<StoredMedication>()).first)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<StoredMedicationPlan>()).first)
        let task = try XCTUnwrap(context.fetch(FetchDescriptor<StoredDoseTask>()).first)
        // All stored fields of the three populated types; the other schema types must stay empty.
        return [
            "medication": [
                AnyHashable(medication.id), AnyHashable(medication.displayName), AnyHashable(medication.genericName),
                AnyHashable(medication.kindRaw), AnyHashable(medication.form), AnyHashable(medication.strength),
                AnyHashable(medication.inputSourceRaw), AnyHashable(medication.photoSymbolName), AnyHashable(medication.photoData),
                AnyHashable(medication.colorTagRaw), AnyHashable(medication.boxNumber), AnyHashable(medication.notes),
                AnyHashable(medication.lifecycleStatusRaw), AnyHashable(medication.isDemoContent), AnyHashable(medication.createdAt)
            ],
            "plan": [
                AnyHashable(plan.id), AnyHashable(plan.medicationID), AnyHashable(plan.doseValue), AnyHashable(plan.doseUnit),
                AnyHashable(plan.timingSummary), AnyHashable(plan.timeZonePolicyRaw), AnyHashable(plan.sourceNote),
                AnyHashable(plan.requiresUserConfirmation), AnyHashable(plan.courseStartAt), AnyHashable(plan.courseEndAt),
                AnyHashable(plan.reminderTimesRaw), AnyHashable(plan.reminderDeliveryRaw),
                AnyHashable(plan.escalatesToAlarmWhenUnhandledRaw), AnyHashable(plan.createdAt)
            ],
            "task": [
                AnyHashable(task.id), AnyHashable(task.medicationID), AnyHashable(task.planID), AnyHashable(task.dueAt),
                AnyHashable(task.doseValue), AnyHashable(task.doseUnit), AnyHashable(task.statusRaw),
                AnyHashable(task.recordedAt), AnyHashable(task.reason)
            ],
            "counts": try [
                AnyHashable(context.fetchCount(FetchDescriptor<StoredMedication>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredMedicationPlan>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredDoseTask>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredMedicationLifecycleEvent>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredMedicationDoseChange>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredRiskCard>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredMedicationLabel>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredMedicationStock>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredDoseActionLog>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredAIConsent>())),
                AnyHashable(context.fetchCount(FetchDescriptor<StoredAIChatMessage>()))
            ]
        ]
    }

    func close() {
        window.isHidden = true
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}
