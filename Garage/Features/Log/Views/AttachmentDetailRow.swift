import SwiftUI

/// PDFs are tappable: a tap notifies `onTap`, which EntryDetailView (the sheet owner) handles by
/// downloading the bytes, writing them to a session temp file, and presenting the shared preview
/// sheet. Images resolve a downloadURL and show an async thumbnail; failures fall back to a
/// placeholder icon rather than an empty gap — that part is unchanged. Images don't get the
/// QuickLook flow this pass: AsyncImage already renders them inline, and routing an
/// already-visible thumbnail through a second full-screen preview didn't fall out naturally, so
/// it was left alone per the task's "do not force it" guidance.
///
/// Deliberately dumb (review fix — concurrent-tap/late-arrival races): this row used to own its
/// own download Task + `isLoadingPreview`/`previewError` state, so each row downloaded
/// independently and PDFPreviewTempFile.write's shared-temp-dir wipe let a second tap delete the
/// file a live QuickLook sheet was rendering. All of that state now lives in EntryDetailView,
/// which is the only thing that can serialize taps across every row on the screen.
struct AttachmentDetailRow: View {
    let path: String
    let entryAttachmentService: EntryAttachmentService
    let isLoading: Bool
    let previewError: AppError?
    let onTap: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: CGImage?
    @State private var didFailThumbnail = false

    private static let thumbnailSide: CGFloat = 44

    private var isPDF: Bool { path.hasSuffix(".pdf") }
    private var filename: String { (path as NSString).lastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if isPDF {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityIdentifier("entry.detail.attachment.pdf")
            } else {
                rowContent
            }
            if let previewError {
                Text(previewError.errorDescription ?? "Could not open that PDF.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("entry.detail.attachment.error")
            }
        }
        .task {
            guard !isPDF else { return }
            guard let url = try? await entryAttachmentService.downloadURL(for: path) else {
                didFailThumbnail = true
                return
            }
            // Points x scale: the bound is in PIXELS, and 44pt is 132px on a 3x screen.
            let maxPixelSize = Int((Self.thumbnailSide * displayScale).rounded())
            thumbnailImage = await Self.loadThumbnail(from: url, maxPixelSize: maxPixelSize)
            didFailThumbnail = thumbnailImage == nil
        }
    }

    /// Replaces `AsyncImage`, which decodes the FULL stored attachment (2048pt, ~16 MB of bitmap)
    /// for a 44pt row and does it on the main actor. The bytes still come from the same signed
    /// download URL — so the shared URL cache still serves a re-appearing row — but the decode is
    /// bounded to the row's pixel size and runs off the main actor.
    private static func loadThumbnail(from url: URL, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return AttachmentImageProcessor.thumbnail(from: data, maxPixelSize: maxPixelSize)
        }.value
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isPDF {
                Image(systemName: "doc.fill")
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(filename)
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                thumbnail
                Text("Photo")
                    .font(Theme.Typography.caption)
                Spacer()
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailImage {
            // `decorative`: the row is already one combined accessibility element labelled "Photo".
            Image(decorative: thumbnailImage, scale: displayScale)
                .resizable()
                .scaledToFill()
                .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else if didFailThumbnail {
            // Unchanged: a failure shows the placeholder icon rather than an empty gap.
            placeholderIcon
                .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
        } else {
            ProgressView()
                .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "photo")
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}
