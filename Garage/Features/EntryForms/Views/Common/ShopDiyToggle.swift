import SwiftUI

struct ShopDiyToggle: View {
    @Binding var isDiy: Bool
    @Binding var shopName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Picker("Performed by", selection: $isDiy) {
                Text("DIY").tag(true)
                Text("Shop").tag(false)
            }
            .pickerStyle(.segmented)

            if !isDiy {
                TextField("Shop name", text: $shopName)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .garageCard()
    }
}
