import QuickLook
import SwiftUI

/// Thin QLPreviewController wrapper for previewing a single local file URL (introduced for
/// EntryDetailView's PDF attachment rows — see AttachmentDetailRow.swift). The URL must already
/// point at bytes on disk; QuickLook cannot stream a remote URL the way AsyncImage does. Callers
/// own the temp file's lifecycle — write it before presenting this view, delete it once the
/// presenting sheet is dismissed.
struct QuickLookPreview: UIViewControllerRepresentable {
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

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
