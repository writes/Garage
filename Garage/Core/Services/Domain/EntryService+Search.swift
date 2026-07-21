import Foundation

extension EntryService {
    /// Filters entries by user-visible content only — notes, entry-type name, shop, and the
    /// humanized detail labels + clean detail values. Never `details.description`, whose raw
    /// dictionary / `CodableValue` representation made queries like "value"/"string" match every
    /// entry (and leaked storage keys).
    nonisolated static func filter(_ entries: [FirestoreEntry], with searchText: String) -> [FirestoreEntry] {
        let lowered = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lowered.isNotEmpty else { return entries }
        return entries.filter { entry in
            entry.notes?.lowercased().contains(lowered) == true
                || entry.entryType.displayName.lowercased().contains(lowered)
                || entry.shopName?.lowercased().contains(lowered) == true
                || entry.details.contains { key, value in
                    key.humanizedFieldLabel.lowercased().contains(lowered)
                        || value.value.displayString.lowercased().contains(lowered)
                }
        }
    }
}
