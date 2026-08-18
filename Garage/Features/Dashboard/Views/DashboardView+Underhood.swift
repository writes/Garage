import SwiftUI

/// The Hood — the Underhood arm's Dashboard presentation (arm manifest §2.4), split from
/// DashboardView.swift by the file/type length caps. Everything here derives from the SAME
/// DashboardViewModel outputs the control cards render — facts only, no invented scores.
extension DashboardView {
    @ViewBuilder
    var underhoodLoadedBody: some View {
        // Control's switcher lives inside OdometerHeroCard, which this body replaces — without
        // this line the Hood would be the one tab a multi-vehicle owner cannot switch from
        // (§4 reachability).
        VehicleSwitcher()
            .frame(maxWidth: .infinity, alignment: .leading)
        // Vehicle-sourced, so it is already correct the moment the owner switches cars. The
        // source line is viewModel-derived, so it blanks while a reload is in flight — otherwise
        // car B's odometer would briefly wear car A's entry date.
        OdometerBlockView(
            miles: appState.currentVehicle?.currentOdometer ?? 0,
            recordedText: viewModel.isLoading ? "last entry — · entered by you" : odometerSourceLine
        )
        // Control's hero facts, same information in this arm's voice (§4): warranty and fuel
        // badges exactly as OdometerHeroCard renders them, and the recall badge in control's
        // exact placement (outside the loading gate — same staleness class in both arms).
        HStack {
            if viewModel.hasActiveWarranty {
                BadgeView(title: "Under warranty", color: Theme.Colors.success)
            }
            if let fuelType = appState.currentVehicle?.fuelType {
                BadgeView(title: fuelType.displayName, color: Theme.Colors.accent)
            }
        }
        RecallAlertBadge(openRecallCount: viewModel.openRecalls)
        // Data-free, so it lives OUTSIDE the loading gate: the Trends row is this arm's ONLY
        // route to Stats (control keeps a whole tab), and §4 says the route must exist for
        // zero-history and error states too — exactly when the gate below shows no content.
        if DesignPackStore.shared.pack.structure.showsDashboardTrendsRow {
            DashboardTrendsRow()
        }
        // Everything below derives from the PREVIOUS vehicle's load until reload lands, so it
        // sits behind the same loading gate control keeps its data cards behind — otherwise a
        // vehicle switch renders the old car's service lights and bay tiles under the new name.
        if viewModel.isLoading {
            LoadingOverlay()
        } else if let error = viewModel.error {
            ErrorBanner(error: error, retry: { Task { await reload() } })
        } else if viewModel.hasNoHistory {
            firstEntryState
        } else {
            serviceLightsRow
            // §2.4 restyles the HERO and the maintenance card (the bay tiles). Every sibling
            // Dashboard card still renders — recalls, MPG drop, wear, reminders — because §4
            // makes every shipped feature reachable in BOTH arms.
            HoodAssemblyView(
                vehicleName: appState.currentVehicle?.displayName ?? "Your vehicle",
                tiles: systemsBayTiles
            )
            FuelEconomyNotice(verdict: viewModel.fuelEconomy)
            wearSection
            remindersSection
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                UnderhoodEyebrow(text: "Recent care")
                RecentEntryFeed(entries: viewModel.recentEntries)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var serviceLightsRow: some View {
        let lights = serviceLightLabels
        return Group {
            if !lights.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(Array(lights.enumerated()), id: \.offset) { _, light in
                            ServiceLightPill(label: light.label, severity: light.severity)
                        }
                    }
                }
                .accessibilityIdentifier("hood.serviceLights")
            }
        }
    }

    /// The bay renders EVERY tracked system from the full roster — healthy ones included — never
    /// the attention-needed slice (an all-current car must read as four green tiles, not four
    /// "no record" warnings). Placeholders only when there is genuinely no history to reason from.
    var systemsBayTiles: [SystemsBayTile] {
        let roster = viewModel.maintenanceRoster
        return roster.isEmpty ? SystemsBayDeriver.placeholderTiles() : SystemsBayDeriver.tiles(from: roster)
    }

    /// Dates the LAST ENTRY, and says so — the odometer figure itself can be newer (a vehicle
    /// edit updates it without an entry), so claiming the figure was "recorded" then would label
    /// it with a fact the app does not have.
    var odometerSourceLine: String {
        if let date = viewModel.recentEntries.first?.entryDate {
            return "last entry \(date.shortDisplay) · entered by you"
        }
        return "no entries yet · entered by you"
    }

    var serviceLightLabels: [(label: String, severity: ServiceLightPill.Severity)] {
        viewModel.maintenanceDue.prefix(4).map { due in
            let prefix = due.item.label.uppercased()
            let suffix: String
            let severity: ServiceLightPill.Severity
            switch due.status {
            case .overdue:
                severity = .bad
                // Time-only overdue carries NEGATIVE milesPastDue (miles still remaining) — the
                // mileage figure is only honest when it is the axis that is actually over.
                if let miles = due.milesPastDue, miles > 0 {
                    suffix = "\(miles.formatted()) MI OVER"
                } else {
                    suffix = "OVERDUE"
                }
            case .dueSoon:
                severity = .warn
                suffix = due.milesPastDue.map { abs($0).formatted() + " MI" } ?? "DUE SOON"
            case .neverLogged:
                severity = .warn
                suffix = "NO RECORD"
            case .upToDate:
                severity = .okay
                suffix = "OK"
            }
            return ("\(prefix) · \(suffix)", severity)
        }
    }
}
