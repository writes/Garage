import SwiftUI

struct EntryFilterSheet: View {
    @Binding var selectedTypes: Set<EntryType>

    var body: some View {
        BottomSheet(title: "Filter Entries") {
            ForEach(EntryType.allCases, id: \.self) { type in
                Toggle(type.displayName, isOn: Binding(
                    get: { selectedTypes.contains(type) },
                    set: { isSelected in
                        if isSelected {
                            selectedTypes.insert(type)
                        } else {
                            selectedTypes.remove(type)
                        }
                    }
                ))
                .frame(minHeight: 44)
                .accessibilityIdentifier("log.filter.\(type.rawValue)")
            }
        }
    }
}
