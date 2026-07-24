import Foundation

// MARK: - PDF temp-file persistence, exposure, and cleanup (audit finding: paid PDF export had
// no way to save or share it — ExportView showed a byte-count Text instead of a ShareLink).
// Mirrors the CSV artifact's temp-file + cleanup discipline; split out to stay under the file cap.

extension ExportViewModel {
    /// Writes the freshly-built PDF bytes (already in `exportData`) to a temp file so ExportView
    /// can hand it to a ShareLink, the same way CSV already writes straight to `csvExportURL`.
    func persistPDFArtifact() throws {
        guard let exportData else { return }
        let url = pdfURLFactory()
        try exportData.write(to: url, options: .completeFileProtection)
        Self.livePDFURLs.insert(url)
        pdfExportURL = url
    }

    /// Parallels `authorizedCSVURL(for:)` / `authorizedPDFData(for:)`: only returns the file if
    /// the caller's authorization still matches the session that produced it.
    func authorizedPDFURL(for authorization: PDFExportAuthorization?) -> URL? {
        guard let authorization, pdfAuthorization == authorization else { return nil }
        return pdfExportURL
    }

    func discardPDFExport() {
        guard let pdfExportURL else { return }
        Self.livePDFURLs.remove(pdfExportURL)
        Self.removeExportFile(pdfExportURL)
        self.pdfExportURL = nil
    }

    static func removeAbandonedPDFExports() {
        removeAbandonedExports(prefix: "garage-record-pdf-", extension: "pdf", liveURLs: livePDFURLs)
    }
}
