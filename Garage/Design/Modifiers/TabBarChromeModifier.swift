import SwiftUI

extension View {
    /// Applies the active pack's tab-bar chrome (arm manifest §1, "tab-bar styling").
    ///
    /// Every modifier here is applied UNCONDITIONALLY, with a value that means "inherit the
    /// platform default" when the token is nil — control carries nil in every field and renders
    /// the virgin bar. The no-branch shape is load-bearing, not style: a `@ViewBuilder if let`
    /// would wrap the TabView in `_ConditionalContent`, and a live kill switch flipping that
    /// branch (Underhood → control) would give the entire tab subtree a NEW structural identity —
    /// tearing down every `LazyTabContent` latch, navigation stack, and scroll position
    /// mid-session (cross-check finding). Value-parameterized modifiers keep the view's type and
    /// identity byte-stable across packs; only the values move.
    ///
    /// `unselectedTint` is absent on purpose: iOS 17 SwiftUI has no unselected-tab-item colour,
    /// so that one field goes through the UIKit appearance proxy from `DesignPackStore.apply`,
    /// which runs BEFORE the bar exists at bootstrap. Appearance proxies do not restyle a bar
    /// already in a window, so on a LIVE kill the unselected tint alone lags until next launch —
    /// a documented cosmetic residue of the emergency path, accepted over recreating the bar.
    func garageTabBarChrome(_ style: DesignTabBarStyle) -> some View {
        self
            // The style value is only consulted while the background is visible; control keeps
            // `.automatic` visibility, under which the system draws its own default — the same
            // `.bar` material this fallback names.
            .toolbarBackground(
                style.background.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.bar),
                for: .tabBar
            )
            .toolbarBackground(style.background == nil ? .automatic : .visible, for: .tabBar)
            // `tint(nil)` is SwiftUI's documented "use the inherited tint" — identical to the
            // modifier being absent, which is what control shipped with.
            //
            // When the pack DOES style the bar, the tint is the RESOLVED ACCENT, not the raw
            // token: SwiftUI tint propagates into the whole tab subtree, so a raw amber here
            // would override a user's explicitly chosen Pro accent on every system control
            // (cross-check finding). `Theme.Colors.primary` is the composition rule itself —
            // the pack's default accent unless the user explicitly picked one — so children
            // inherit exactly the colour every explicit call site already uses, and the
            // selected tab item follows the same accent the rest of the arm wears.
            .tint(style.selectedTint == nil ? nil : Theme.Colors.primary)
    }
}
