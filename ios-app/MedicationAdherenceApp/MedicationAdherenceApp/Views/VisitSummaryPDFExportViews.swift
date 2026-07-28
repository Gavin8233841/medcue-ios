import Foundation
import QuickLook
import SwiftUI
import UIKit

enum VisitSummaryPDFExporter {
    static func export(payload: VisitSummaryExportPayload, targetURL: URL) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let report = VisitSummaryPDFReport(payload: payload)
            let data = renderer.pdfData { context in
                report.draw(in: context, pageBounds: pageBounds)
            }
            try Task.checkCancellation()
            try data.write(to: targetURL, options: .atomic)
            try Task.checkCancellation()
            return targetURL
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
