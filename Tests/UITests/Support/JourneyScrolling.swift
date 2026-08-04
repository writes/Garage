import XCTest

/// Scrolling a control into reach before tapping it.
///
/// Split from `JourneyTestCase` to stay under the 250-line file cap; it is one cohesive concern:
/// everything here exists because the journeys must pass on the SMALLEST canvas the app ever
/// renders at — 375x667, which is what an iPhone-only app (TARGETED_DEVICE_FAMILY = 1) gets in
/// iPad compatibility mode, where App Review reviewed it.
@MainActor
extension JourneyTestCase {
    func revealAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        require(element)
        // Ten passes: a long sheet form (Export) has to expand from its .medium detent AND then
        // travel ~2 screenfuls. Each pass is a no-op once the element is revealed.
        //
        // The anchors VARY because a drag is silently swallowed by whatever sits under its start
        // point — a button row consumes it as a press, a text field as cursor placement — and a
        // fixed anchor that lands on one of those simply repeats the same no-op ten times. Cycling
        // the start point down and up the container retries a blocked pass somewhere else.
        for anchor in [0.75, 0.55, 0.4, 0.85, 0.65, 0.45, 0.7, 0.5, 0.35, 0.8]
        where !isRevealed(element, in: app) {
            scrollStep(toward: element, in: app, anchor: anchor)
        }
        tapWhenHittable(element)
    }

    /// Hittable is NOT sufficient on the smallest canvas. XCUITest calls an element hittable as
    /// soon as its CENTRE is clear, so it green-lights a control whose lower half is behind the
    /// bottom chrome, and a tap landing within a few points of that chrome's top edge is swallowed
    /// by it instead of reaching the control. Measured in iPad compatibility mode:
    /// "vehicle.form.save" spanning y 736.8-829.7 under a keyboard starting at 794.3 reported
    /// hittable, was tapped, and nothing happened; one scroll later the identical tap saved. So an
    /// element reaching under the chrome counts as unrevealed and gets scrolled clear first —
    /// which is exactly what a real user does.
    private func isRevealed(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.isHittable else { return false }
        return element.frame.maxY <= usableBottom(of: scrollContainer(in: app).frame, in: app)
    }

    /// Where the content area effectively ends: the container's own bottom, or the top of whatever
    /// chrome is docked over it. The TAB BAR matters as much as the keyboard — "settings.signout"
    /// is the second-to-last row of the Settings list and on a 375x667 canvas it renders under the
    /// tab bar, tappable only after the list is scrolled up. A tab bar behind a presented sheet is
    /// NOT an obstruction, which is what its buttons' hittability distinguishes.
    private func usableBottom(of frame: CGRect, in app: XCUIApplication) -> CGFloat {
        var bottom = frame.maxY
        var chrome = [app.keyboards.firstMatch]
        if app.tabBars.buttons.firstMatch.isHittable {
            chrome.append(app.tabBars.firstMatch)
        }
        for element in chrome where element.exists {
            let elementFrame = element.frame
            guard elementFrame.height > 0, elementFrame.minY > frame.minY else { continue }
            bottom = min(bottom, elementFrame.minY)
        }
        return bottom
    }

    /// One scroll of the frontmost container toward `element`.
    ///
    /// Deliberately NOT `app.swipeUp()`. This app is iPhone-only (TARGETED_DEVICE_FAMILY = 1), so
    /// on an iPad it runs in compatibility mode, where `XCUIApplication.frame` is reported in the
    /// app's own 375x667 point space while gestures are synthesized in SCREEN space (measured on
    /// iPad Air 11-inch: app.frame = {{0,0},{375,667}}, window = {{79,0},{663,1180}}). An
    /// app-anchored swipe therefore aims ~1.77x short of its target and lands on the backdrop
    /// BEHIND a presented sheet, scrolling nothing — while the identical call is correct on iPhone,
    /// where the two spaces coincide. ELEMENT frames are in screen space, so anchoring the drag on
    /// the scroll container aims true on both device families, and NORMALIZED offsets are the only
    /// safe unit: `XCUICoordinate.withOffset` takes points, which compatibility mode interprets in
    /// the app's space while `frame` is reported in the screen's.
    ///
    /// Two gestures, because one cannot do both jobs. A long haul (the Export sheet: expand from
    /// its .medium detent, then ~2 screenfuls of form) only completes in a bounded number of passes
    /// with a FLICK's momentum. That same momentum overshoots a short keyboard correction and parks
    /// the field under the navigation bar, where it taps but never takes focus — so a control that
    /// only just hangs into the keyboard gets a slow, exactly-measured nudge instead.
    private func scrollStep(toward element: XCUIElement, in app: XCUIApplication, anchor: CGFloat) {
        let container = scrollContainer(in: app)
        let frame = container.frame
        guard frame.height > 0 else { return }
        let keyboardIsUp = app.keyboards.firstMatch.exists
        let contentBottom = usableBottom(of: frame, in: app)
        let usableHeight = contentBottom - frame.minY
        guard usableHeight > 80 else { return }
        // The anchor is a fraction of the part the keyboard is NOT covering, and is capped while a
        // keyboard is up so a drag never begins on the keyboard itself or on the focused field
        // docked just above it — both consume the gesture before the scroll view sees it.
        let overlap = element.frame.maxY - contentBottom
        let startY = frame.minY + usableHeight * (keyboardIsUp ? min(anchor, 0.6) : anchor)
        if overlap > 0, overlap + 24 <= usableHeight * 0.4 {
            drag(container, frame: frame, from: startY, to: startY - (overlap + 24), settling: true)
        } else {
            drag(container, frame: frame, from: startY, to: frame.minY + frame.height * 0.08, settling: false)
        }
    }

    /// `settling` ends the drag with a stationary hold, which zeroes the release velocity so the
    /// scroll view stops exactly where the finger did. The initial press stays SHORT either way: a
    /// long stationary press lands on a text field as a cursor/loupe gesture and the scroll view
    /// never sees the pan at all.
    private func drag(
        _ container: XCUIElement, frame: CGRect, from startY: CGFloat, to endY: CGFloat, settling: Bool
    ) {
        let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fraction(of: startY, in: frame)))
        let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fraction(of: endY, in: frame)))
        if settling {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        } else {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func fraction(of yCoordinate: CGFloat, in frame: CGRect) -> CGFloat {
        guard frame.height > 0 else { return 0.5 }
        return min(max((yCoordinate - frame.minY) / frame.height, 0), 1)
    }

    /// The frontmost scrollable container. Sheets in this app are always a `BottomSheet` (a
    /// ScrollView) presented OVER list/form screens (collection views), so a ScrollView wins when
    /// both are on screen; within one query the LAST match wins, because later siblings are the
    /// ones drawn on top.
    ///
    /// The height floor is load-bearing: a raised keyboard publishes its own ScrollView — the
    /// QuickType candidate bar, ~7% of the window tall and docked directly above the keys — which
    /// would otherwise win as the last ScrollView and swallow every flick into a strip that
    /// scrolls nothing. Page content is always a substantial slice of the window.
    private func scrollContainer(in app: XCUIApplication) -> XCUIElement {
        let window = app.windows.firstMatch
        let minimumHeight = window.frame.height * 0.25
        for query in [app.scrollViews, app.collectionViews, app.tables] {
            let candidates = query.allElementsBoundByIndex.filter { $0.frame.height >= minimumHeight }
            if let last = candidates.last { return last }
        }
        return window
    }
}
