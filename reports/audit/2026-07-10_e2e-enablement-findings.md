# E2E enablement findings (accessibility/testability scout, 2026-07-10)

Sweep of the UI layer for XCUITest readiness (sonnet scout, 61 tool calls). Key findings:

1. **One accessibility identifier app-wide** (`ui-test-ready`, on the UITestHarnessView dead
   end). Two `.accessibilityLabel`s (FloatingAddButton, VehicleSwitcher). ~109 interactive
   controls have neither — E2E would depend on visible-string matching (fragile, not a
   contract).
2. **UI_TEST_MODE renders a bare harness Text and never shows the real app** — the two
   existing "CriticalFlows" UI tests could never have tested a flow. Dead end by construction.
3. **LOCAL_DEMO_MODE (Debug-only) is the viable E2E path**: pre-authenticated
   (`debug-user`), seeded vehicles/entries. BUT: all `save()` paths NO-OP in demo mode —
   create→appears journeys cannot verify persistence; needs a demo-mode in-memory store
   (design → tri-vote TV-A5).
4. **No Pro-entitlement lever**: `PurchaseService.uiTest` never flips `isPro`; ProGate blocks
   journeys J5/J6/J7 in demo. Needs a Debug-only `UI_TEST_PRO` launch flag.
5. **SubscriptionView bypasses injection** (`PurchaseService.shared` direct) → talks to live
   RevenueCat even in demo/test mode. Testability + architecture defect.
6. **Sync badge is non-deterministic in demo** (real `SyncService.shared` wired even in demo).
7. Seed data: warranties/recalls/gallery are hardcoded empty — those screens can only be
   empty-state-tested in demo.
8. Navigation contract for tests: 5-tab TabView (label-matched), single global sheet router
   (one sheet at a time), per-view local sheets in Log/SpareParts/Detailing, NavigationStack
   pushes in Garage/Settings, BottomSheet detents affect off-screen content.

Consequence for the plan: Pass C (E2E enablement) must add — all Debug-scoped/additive —
accessibility identifiers on every journey's controls, a `UI_TEST_PRO` flag, a demo-mode
in-memory persistence overlay (per TV-A5 vote), an injected PurchaseService in
SubscriptionView, and (optionally) a deterministic sync-state override for demo.
