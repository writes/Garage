import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentPicker: View {
    @Binding var attachmentPaths: [String]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImportingPDF = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Attachments")
                .font(Theme.Typography.headline)

            HStack {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Add Photo", systemImage: "photo")
                }
                Button {
                    isImportingPDF = true
                } label: {
                    Label("Add PDF", systemImage: "doc")
                }
            }

            if attachmentPaths.isEmpty {
                Text("Receipts, invoices, and related photos show up here after selection.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(attachmentPaths, id: \.self) { attachment in
                    Text(attachment)
                        .font(Theme.Typography.caption)
                }
            }
        }
        .garageCard()
        .onChange(of: selectedPhoto) { _, newValue in
            guard newValue != nil else { return }
            attachmentPaths.append("photo-\(UUID().uuidString).jpg")
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                attachmentPaths.append(url.lastPathComponent)
            }
        }
    }
}
