import Foundation
import QuickLook
import SwiftUI
import UIKit

enum VisitSummaryPDFExporter {
    /// Export a visit-summary PDF with lifecycle-managed file protection and cleanup.
    ///
    /// - Parameters:
    ///   - payload: The visit summary data to render.
    ///   - lifecycle: The lifecycle manager responsible for file creation, protection, and cleanup.
    /// - Returns: The URL of the successfully protected PDF.
    /// - Throws: If PDF generation, protection verification, or lifecycle management fails.
    static func export(
        payload: VisitSummaryExportPayload,
        lifecycle: VisitSummaryPDFLifecycle
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()

            // Ensure the export root directory exists
            try lifecycle.ensureRootDirectory()

            // Generate PDF data
            let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let report = VisitSummaryPDFReport(payload: payload)
            let data = renderer.pdfData { context in
                report.draw(in: context, pageBounds: pageBounds)
            }

            try Task.checkCancellation()

            // Create target URL with unique opaque filename
            let filename = lifecycle.makeUniqueFilename()
            let targetURL = lifecycle.rootDirectory.appendingPathComponent(filename)

            // Publish with file protection and verification
            let publishedURL = try lifecycle.publish(data: data, to: targetURL)

            try Task.checkCancellation()

            return publishedURL
        }.value
    }
}

struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PDFPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
