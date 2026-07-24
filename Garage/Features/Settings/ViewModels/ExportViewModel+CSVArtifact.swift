import Foundation

// MARK: - CSV temp-file tracking, streaming pagination, and cleanup (split out to stay under the file cap)

extension ExportViewModel {
    func trackCSV(writer: CSVExportService.RawExportWriter, url: URL, operationID: UUID) {
        activeCSVArtifact = .init(operationID: operationID, writer: writer, url: url)
        Self.liveCSVURLs.insert(url)
    }

    func releaseActiveCSV(ifCurrent operationID: UUID) {
        if activeCSVArtifact?.operationID == operationID { activeCSVArtifact = nil }
    }

    func cancelActiveCSV() {
        guard let artifact = activeCSVArtifact else { return }
        cleanupCSV(writer: artifact.writer, url: artifact.url, operationID: artifact.operationID)
    }

    func cleanupCSV(writer: CSVExportService.RawExportWriter, url: URL, operationID: UUID) {
        writer.cancel()
        releaseActiveCSV(ifCurrent: operationID)
        Self.liveCSVURLs.remove(url)
        Self.removeExportFile(url)
    }

    func appendCSVPages(
        vehicleID: String,
        writer: CSVExportService.RawExportWriter,
        operationID: UUID,
        expectedAuthorization: ExportSessionAuthorization,
        authorization: @MainActor () -> ExportSessionAuthorization?
    ) async throws -> Int? {
        var cursor: EntryCursor?
        var entryCount = 0
        repeat {
            guard operationIsCurrent(operationID),
                  authorization() == expectedAuthorization else { return nil }
            let page = try await csvPageFetch(
                EntryQuery(vehicleId: vehicleID), Self.exportPageSize, cursor
            )
            guard operationIsCurrent(operationID),
                  authorization() == expectedAuthorization else { return nil }
            try writer.append(entries: page.entries)
            entryCount += page.entries.count
            cursor = page.nextCursor
        } while cursor != nil
        return entryCount
    }

    func discardCSVExport() {
        csvAuthorization = nil
        guard let csvExportURL else { return }
        Self.liveCSVURLs.remove(csvExportURL)
        Self.removeExportFile(csvExportURL)
        self.csvExportURL = nil
    }

    static func removeAbandonedCSVExports() {
        removeAbandonedExports(prefix: csvFilenamePrefix, extension: "csv", liveURLs: liveCSVURLs)
    }
}
