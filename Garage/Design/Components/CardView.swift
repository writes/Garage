import SwiftUI

struct CardView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.garageCard()
    }
}
