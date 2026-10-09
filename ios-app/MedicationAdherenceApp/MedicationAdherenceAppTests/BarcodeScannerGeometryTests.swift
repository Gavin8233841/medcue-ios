import Testing
import SwiftUI
import UIKit
@testable import MedicationAdherenceApp

@Suite(.serialized)
@MainActor
struct BarcodeScannerGeometryTests {
    @Test
    func roomyViewportKeepsOriginalGuideSize() {
        #expect(BarcodeScannerGeometry.frameSize(in: CGSize(width: 600, height: 800)) == CGSize(width: 286, height: 178))
    }

    @Test
    func narrowAndShortViewportsPreserveAspectAndStayInsideAvailableSpace() {
        for available in [CGSize(width: 248, height: 300), CGSize(width: 600, height: 89),
                          CGSize(width: 32, height: 12), CGSize(width: 288, height: 200)] {
            let size = BarcodeScannerGeometry.frameSize(in: available)
            #expect(size.width > 0 && size.height > 0)
            #expect(size.width <= available.width && size.height <= available.height)
            #expect(abs(size.width / size.height - 286.0 / 178.0) < 0.000001)
            #expect(size.width <= 286 && size.height <= 178)
        }
        #expect(BarcodeScannerGeometry.frameSize(in: CGSize(width: 600, height: 89)) == CGSize(width: 143, height: 89))
    }

    @Test
    func unavailableOrInvalidLayoutProducesNoScanArea() {
        for size in [CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: 100, height: 0),
                     CGSize(width: CGFloat.infinity, height: 100), CGSize(width: 100, height: CGFloat.nan)] {
            #expect(BarcodeScannerGeometry.frameSize(in: size) == .zero)
        }
        #expect(BarcodeScannerGeometry.clippedRect(.null, in: CGRect(x: 0, y: 0, width: 320, height: 480)) == .zero)
        #expect(BarcodeScannerGeometry.clippedRect(CGRect(x: 0, y: 0, width: 20, height: 20), in: .zero) == .zero)
    }

    @Test
    func clippingDoesNotInventAreaOutsidePreview() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 480)
        #expect(BarcodeScannerGeometry.clippedRect(CGRect(x: -20, y: 450, width: 100, height: 80), in: bounds)
                == CGRect(x: 0, y: 450, width: 80, height: 30))
        #expect(BarcodeScannerGeometry.clippedRect(CGRect(x: 400, y: 50, width: 100, height: 80), in: bounds) == .zero)
    }

    @Test
    func actualGuideWinsOverAnIndependentlyComputed320PointROI() {
        let fixture = makeFixture()
        fixture.anchor.frame = CGRect(x: 17, y: 150, width: 286, height: 178)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                == CGRect(x: 17, y: 150, width: 286, height: 178))
        // The old UIKit formula returned 272 wide for this 320-point camera.
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera).width != 272)
    }

    @Test
    func overlaySafeAreaOffsetIsConvertedToFullBleedPreviewCoordinates() {
        let fixture = makeFixture()
        fixture.overlay.frame.origin = CGPoint(x: 0, y: 64)
        fixture.anchor.frame = CGRect(x: 17, y: 150, width: 286, height: 178)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                == CGRect(x: 17, y: 214, width: 286, height: 178))
    }

    @Test
    func repeatedResizeAndSafeAreaMovesDoNotUseCachedGeometry() {
        let fixture = makeFixture()
        for offset in [CGFloat(64), 0, 20, 64] {
            fixture.overlay.frame.origin.y = offset
            fixture.anchor.frame = CGRect(x: 24, y: 80, width: 248, height: 154)
            #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                    == CGRect(x: 24, y: 80 + offset, width: 248, height: 154))
        }
        fixture.preview.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        fixture.anchor.frame = CGRect(x: 10, y: 10, width: 180, height: 100)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                == CGRect(x: 10, y: 74, width: 180, height: 46))
    }

    @Test
    func previewLayerOffsetAndBoundsOriginAreRespected() {
        let fixture = makeFixture()
        fixture.preview.frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        fixture.preview.bounds.origin = CGPoint(x: 5, y: 7)
        fixture.anchor.frame = CGRect(x: 30, y: 50, width: 100, height: 80)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                == CGRect(x: 25, y: 37, width: 100, height: 80))
    }

    @Test
    func transformInOverlayHierarchyIsConverted() {
        let fixture = makeFixture()
        fixture.overlay.layer.anchorPoint = .zero
        fixture.overlay.layer.position = CGPoint(x: 20, y: 30)
        fixture.overlay.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        fixture.anchor.frame = CGRect(x: 40, y: 60, width: 200, height: 100)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                == CGRect(x: 40, y: 60, width: 100, height: 50))
    }

    @Test
    func detachedAnchorAndDifferentWindowsDisableArea() {
        let fixture = makeFixture()
        fixture.anchor.removeFromSuperview()
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera) == .zero)
        let otherWindow = UIWindow(frame: fixture.window.bounds)
        otherWindow.addSubview(fixture.anchor)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera) == .zero)
        fixture.region.anchorView = nil
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera) == .zero)
    }

    @Test
    func lateAnchorAttachmentRecoversFromUnreadyLayout() {
        let fixture = makeFixture()
        fixture.anchor.removeFromSuperview()
        fixture.anchor.bounds.size = .zero
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera) == .zero)
        fixture.overlay.addSubview(fixture.anchor)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera) == .zero)
        fixture.anchor.frame = CGRect(x: 17, y: 150, width: 286, height: 178)
        #expect(fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
                == CGRect(x: 17, y: 150, width: 286, height: 178))
        // A real AVCapture input-format notification and aspect-fill conversion
        // still require the native camera integration/device acceptance lane.
    }

    @Test
    func deferredRefreshUsesFinalAncestorLayoutAndCoalescesUpdates() async {
        let fixture = makeFixture()
        var observedRect = CGRect.zero
        var updates = 0
        fixture.region.onChange = {
            updates += 1
            observedRect = fixture.region.rect(in: fixture.preview, previewView: fixture.camera)
        }
        fixture.region.scheduleUpdate()
        fixture.overlay.frame.origin.y = 64
        fixture.region.scheduleUpdate()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(updates == 1)
        #expect(observedRect == CGRect(x: 17, y: 214, width: 286, height: 178))
        fixture.region.onChange = nil
    }

    @Test
    func metadataGateRejectsEmptyAndMovedRegionsButAcceptsCurrentIntersection() {
        let oldObject = CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
        let movedRegion = CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.2)
        #expect(!BarcodeScannerGeometry.accepts(metadataBounds: oldObject, region: .zero))
        #expect(!BarcodeScannerGeometry.accepts(metadataBounds: oldObject, region: movedRegion))
        #expect(BarcodeScannerGeometry.accepts(
            metadataBounds: CGRect(x: 0.7, y: 0.65, width: 0.1, height: 0.1), region: movedRegion
        ))
        #expect(!BarcodeScannerGeometry.accepts(metadataBounds: .null, region: movedRegion))
        let clipped = BarcodeScannerGeometry.normalizedRegion(CGRect(x: -0.1, y: 0.9, width: 0.3, height: 0.3))
        #expect(abs(clipped.width - 0.2) < 0.000001)
        #expect(abs(clipped.height - 0.1) < 0.000001)
        #expect(clipped.minX == 0 && clipped.maxY == 1)
        #expect(BarcodeScannerGeometry.normalizedRegion(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1)) == .zero)
    }

    @Test
    func swiftUIBackgroundAnchorTracksNarrowShortAndSafeAreaLayouts() async throws {
        let region = BarcodeScannerRegion()
        let host = UIHostingController(rootView: BarcodeScannerOverlay(
            scanRegion: region,
            statusMessage: "请把药盒条码放入取景框，识别结果仍需二次确认。",
            scanHint: "对准药盒条码，保持边缘完整"
        ).environment(\.dynamicTypeSize, .large))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        let preview = CALayer()
        host.view.layer.insertSublayer(preview, at: 0)
        var refreshedRect = CGRect.zero
        region.onChange = { refreshedRect = region.rect(in: preview, previewView: host.view) }
        defer { region.onChange = nil }

        let layouts: [(CGSize, DynamicTypeSize)] = [
            (CGSize(width: 320, height: 568), .large),
            (CGSize(width: 280, height: 360), .large),
            (CGSize(width: 600, height: 260), .large),
            (CGSize(width: 280, height: 360), .accessibility5),
            (CGSize(width: 600, height: 260), .accessibility5),
            (CGSize(width: 320, height: 568), .large)
        ]
        for (size, dynamicType) in layouts {
            host.rootView = BarcodeScannerOverlay(
                scanRegion: region,
                statusMessage: "请把药盒条码放入取景框，识别结果仍需二次确认。",
                scanHint: "对准药盒条码，保持边缘完整"
            ).environment(\.dynamicTypeSize, dynamicType)
            window.frame.size = size
            host.view.frame = window.bounds
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 20, left: 8, bottom: 16, right: 8)
            preview.frame = host.view.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            host.view.layoutIfNeeded()
            region.scheduleUpdate()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }

            let anchor = try #require(region.anchorView)
            #expect(anchor.window === window)
            #expect(anchor.bounds.width > 0 && anchor.bounds.height > 0)
            #expect(anchor.bounds.width <= 286 && anchor.bounds.height <= 178)
            let actualFrame = anchor.convert(anchor.bounds, to: host.view)
            let safeBounds = host.view.bounds.inset(by: host.view.safeAreaInsets)
            #expect(safeBounds.contains(actualFrame))
            #expect(refreshedRect == actualFrame)
            #expect(abs(anchor.bounds.width * 178 / 286 - anchor.bounds.height) <= 1)
        }
    }

    private func makeFixture() -> Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let camera = UIView(frame: window.bounds)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(camera)
        window.addSubview(overlay)
        let preview = CALayer()
        preview.frame = camera.bounds
        camera.layer.addSublayer(preview)
        let anchor = UIView(frame: CGRect(x: 17, y: 150, width: 286, height: 178))
        overlay.addSubview(anchor)
        let region = BarcodeScannerRegion()
        region.anchorView = anchor
        return Fixture(window: window, camera: camera, overlay: overlay, preview: preview, anchor: anchor, region: region)
    }

    private struct Fixture {
        let window: UIWindow
        let camera: UIView
        let overlay: UIView
        let preview: CALayer
        let anchor: UIView
        let region: BarcodeScannerRegion
    }
}
