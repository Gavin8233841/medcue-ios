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
/// No screen-size/device skips, fake detail UI, production visibility changes, permissions,
/// persistent store, or action activation. Reachability here means a visible, enabled
/// accessibility button with an in-bounds frame; action effects belong to command/UI tests.
/// AX labels/frames do not prove visually untruncated text. Review the saved screenshots.
/// The 1024pt host is an offscreen-capable container, not a physical iPhone screen assertion.
/// The file-private Layout types cannot be directly fed nil/zero/infinite proposals here.
/// Public accessibility traversal must succeed: missing observations FAIL, never skip/pass.
final class MedicationDetailAdaptiveLayoutTests: XCTestCase {
    @MainActor
    func testRealDetailReflowsNarrowWideNarrowWithoutLosingContent() throws {
        let harness = try DetailLayoutHarness()
        defer { harness.close() }
        for (step, width) in [CGFloat(320), 1024, 320].enumerated() {
            harness.resize(width: width, category: .large)
            try inspect(harness, name: "resize-\(step)-\(Int(width))", expectsColumns: width > 600)
        }
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    func testAX5UsesOneColumnEvenInRegularWideContainer() throws {
        let harness = try DetailLayoutHarness()
        defer { harness.close() }
        for width in [CGFloat(320), 1024] {
            harness.resize(width: width, category: .accessibilityExtraExtraExtraLarge)
            try inspect(harness, name: "AX5-\(Int(width))", expectsColumns: false)
        }
        // Same hosting controller and model, restoring the real UIKit trait override.
        harness.resize(width: 1024, category: .large)
        try inspect(harness, name: "AX5-restored", expectsColumns: true)
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    func testRTLDetailRemainsReachableAcrossResize() throws {
        let harness = try DetailLayoutHarness(rightToLeft: true)
        defer { harness.close() }
        for width in [CGFloat(320), 1024] {
            harness.resize(width: width, category: .large)
            try inspect(harness, name: "RTL-\(Int(width))", expectsColumns: width > 600)
        }
        try harness.assertFixtureUnchanged()
    }

    @MainActor
    private func inspect(_ harness: DetailLayoutHarness, name: String, expectsColumns: Bool) throws {
        let scroll = try harness.waitForMountedList()
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        _ = try harness.waitForStableAccessibility(in: scroll)
        attach(harness, name: name + "-top")

        let requiredText = [
            DetailLayoutHarness.medicationName, "药品信息", "疗程与提醒",
            DetailLayoutHarness.genericName, "SYNTHETIC-161", "暂无剂量变化记录。",
            DetailLayoutHarness.planNote, "已服用"
        ]
        let requiredButtons = ["选择照片", "修改疗程与提醒", "填写药盒", "修改药品信息"]
        var seenText = Set<String>()
        var seenButtons = Set<String>()
        var headings: [String: CGRect] = [:]
        var reachedEnd = false
        var capturedInformation = false

        // Walk overlapping viewports rather than asking only for currently materialized rows.
        // A finite limit is a failure diagnostic, not a coverage exemption.
        for _ in 0..<100 {
            let items = try harness.waitForStableAccessibility(in: scroll)
            XCTAssertTrue(scroll.contentSize.width.isFinite && scroll.contentSize.height.isFinite)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 2,
                                     "\(name): List must not require horizontal scrolling")
            let viewport = harness.contentViewport(of: scroll)
            for item in items {
                let frame = harness.window.convert(item.frame, from: nil)
                guard frame.intersects(viewport), frame.height > 0, frame.width > 0 else { continue }
                let matchingText = requiredText.filter { item.label.contains($0) }
                let matchingButtons = requiredButtons.filter { item.label == $0 && item.isButton }
                guard !matchingText.isEmpty || !matchingButtons.isEmpty else { continue }
                XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite
                              && frame.width.isFinite && frame.height.isFinite,
                              "\(name): non-finite accessibility geometry for \(item.label)")
                XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 2,
                                            "\(name): leading overflow for \(item.label)")
                XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 2,
                                         "\(name): trailing overflow for \(item.label)")
                seenText.formUnion(matchingText)
                // The button's center must enter the viewport; partial offscreen rows do not count.
                if viewport.contains(CGPoint(x: frame.midX, y: frame.midY)), !item.isDisabled {
                    seenButtons.formUnion(matchingButtons)
                }
                for title in ["药品信息", "疗程与提醒"] where item.label == title {
                    var contentFrame = frame
                    contentFrame.origin.y += scroll.contentOffset.y
                    headings[title] = contentFrame
                }
            }
            if headings["药品信息"] != nil && !capturedInformation {
                attach(harness, name: name + "-information")
                capturedInformation = true
            }
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y >= bottom - 1 {
                reachedEnd = true
                break
            }
            scroll.setContentOffset(CGPoint(x: 0, y: min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.55)),
                                    animated: false)
        }
        attach(harness, name: name + "-bottom")
        XCTAssertTrue(reachedEnd, "\(name): failed to reach the bottom of the real List")
        XCTAssertEqual(seenText, Set(requiredText), "\(name): missing rendered/visible content")
        XCTAssertEqual(seenButtons, Set(requiredButtons), "\(name): missing reachable enabled controls")
        let information = try XCTUnwrap(headings["药品信息"], "\(name): missing measured information heading")
        let plans = try XCTUnwrap(headings["疗程与提醒"], "\(name): missing measured plans heading")
        if expectsColumns {
            XCTAssertEqual(information.minY, plans.minY, accuracy: 4,
                           "\(name): regular-width information/plans should share a row")
            if harness.rightToLeft {
                XCTAssertLessThan(plans.midX, information.midX - 100,
                                  "RTL column order must mirror the real detail content")
            } else {
                XCTAssertGreaterThan(plans.midX, information.midX + 100)
            }
        } else {
            XCTAssertGreaterThan(plans.minY, information.maxY,
                                 "\(name): narrow/AX content should preserve vertical reading order")
        }
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

    struct AccessibilityItem: Equatable {
        let label: String
        let frame: CGRect
        let isButton: Bool
        let isDisabled: Bool
    }

    func accessibilityItems() -> [AccessibilityItem] {
        var result: [AccessibilityItem] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if object.accessibilityElementsHidden { return }
            if let view = object as? UIView, view.isHidden || view.alpha == 0 { return }
            if object.isAccessibilityElement, let label = object.accessibilityLabel, !label.isEmpty {
                result.append(AccessibilityItem(label: label, frame: object.accessibilityFrame,
                                                isButton: object.accessibilityTraits.contains(.button),
                                                isDisabled: object.accessibilityTraits.contains(.notEnabled)))
            }
            // SwiftUI exposes virtual elements as well as actual UIKit subviews.
            if let elements = object.accessibilityElements {
                for element in elements { if let child = element as? NSObject { visit(child) } }
            } else {
                let count = object.accessibilityElementCount()
                if count > 0 && count != NSNotFound && count < 2_000 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) }
                    }
                }
            }
            if let view = object as? UIView { view.subviews.forEach(visit) }
        }
        visit(host.view)
        return result
    }

    func waitForMountedList() throws -> UIScrollView {
        let deadline = Date(timeIntervalSinceNow: 3)
        repeat {
            settle()
            if let list = descendantViews.compactMap({ $0 as? UIScrollView })
                .filter({ $0.bounds.width > 100 && $0.bounds.height > 100 && $0.contentSize.height > 0 })
                .max(by: { $0.bounds.height < $1.bounds.height }) { return list }
        } while Date() < deadline
        throw HarnessFailure.listDidNotMount(diagnostics(scroll: nil, raw: accessibilityItems(), visible: []))
    }

    func contentViewport(of scroll: UIScrollView) -> CGRect {
        scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            .intersection(host.view.convert(host.view.bounds, to: window))
            .intersection(window.bounds)
    }

    func waitForStableAccessibility(in scroll: UIScrollView) throws -> [AccessibilityItem] {
        let deadline = Date(timeIntervalSinceNow: 3)
        var previous: [AccessibilityItem] = []
        var raw: [AccessibilityItem] = []
        var current: [AccessibilityItem] = []
        var polls = 0
        var maxRawCount = 0
        var maxVisibleCount = 0
        var lastPrevious: [AccessibilityItem] = []
        repeat {
            settle()
            let viewport = contentViewport(of: scroll)
            raw = accessibilityItems()
            current = raw.filter { window.convert($0.frame, from: nil).intersects(viewport) }
            polls += 1
            maxRawCount = max(maxRawCount, raw.count)
            maxVisibleCount = max(maxVisibleCount, current.count)
            if !current.isEmpty && current == previous { return current }
            lastPrevious = previous
            previous = current
        } while Date() < deadline
        // Keep the original exact comparison until native evidence identifies order/jitter
        // as the cause. Neither an empty tree nor a timeout is accepted as layout coverage.
        let stability = "polls=\(polls), maxRaw=\(maxRawCount), maxVisible=\(maxVisibleCount), "
            + "previousVisible=\(lastPrevious.count), "
            + "sameOrderedLabels=\(lastPrevious.map(\.label) == current.map(\.label)), "
            + "sameLabelMultiset=\(lastPrevious.map(\.label).sorted() == current.map(\.label).sorted())"
        throw HarnessFailure.visibleAccessibilityDidNotStabilize(
            stability + "\n" + diagnostics(scroll: scroll, raw: raw, visible: current)
        )
    }

    private func diagnostics(scroll: UIScrollView?, raw: [AccessibilityItem], visible: [AccessibilityItem]) -> String {
        // Only the synthetic hosting subtree is sampled; never inspect another app window.
        let samples = raw.prefix(8).map { item in
            let label = String(item.label.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            return "label=\(label.debugDescription), screenFrame=\(item.frame), "
                + "windowFrame=\(window.convert(item.frame, from: nil)), button=\(item.isButton), disabled=\(item.isDisabled)"
        }.joined(separator: "\n")
        let sceneState = window.windowScene.map { String($0.activationState.rawValue) } ?? "none"
        let geometry = [
            "rawAX=\(raw.count), visibleAX=\(visible.count)",
            "sceneAttached=\(window.windowScene != nil), sceneActivationState=\(sceneState)",
            "window.frame=\(window.frame), window.bounds=\(window.bounds), hidden=\(window.isHidden), alpha=\(window.alpha), key=\(window.isKeyWindow)",
            "host.frame=\(host.view.frame), host.bounds=\(host.view.bounds), attachedToTestWindow=\(host.view.window === window)",
            "host.hidden=\(host.view.isHidden), host.alpha=\(host.view.alpha), host.AXHidden=\(host.view.accessibilityElementsHidden)",
            "parent.frame=\(parent.view.frame), parent.bounds=\(parent.view.bounds), descendantViews=\(descendantViews.count)"
        ].joined(separator: "\n")
        let scrollGeometry: String
        if let scroll {
            scrollGeometry = "viewport=\(contentViewport(of: scroll)), scroll.frame=\(scroll.frame), scroll.bounds=\(scroll.bounds), "
                + "contentSize=\(scroll.contentSize), contentOffset=\(scroll.contentOffset), adjustedInsets=\(scroll.adjustedContentInset)"
        } else {
            scrollGeometry = "viewport=unavailable; no mounted nonzero List"
        }
        return geometry + "\n" + scrollGeometry + "\nsyntheticHostSamples(up to 8):\n" + samples
    }

    private enum HarnessFailure: LocalizedError, CustomStringConvertible {
        case noForegroundWindowScene(String)
        case listDidNotMount(String)
        case visibleAccessibilityDidNotStabilize(String)

        var description: String {
            switch self {
            case .noForegroundWindowScene(let details): "noForegroundWindowScene: " + details
            case .listDidNotMount(let details): "listDidNotMount: " + details
            case .visibleAccessibilityDidNotStabilize(let details): "visibleAccessibilityDidNotStabilize: " + details
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
