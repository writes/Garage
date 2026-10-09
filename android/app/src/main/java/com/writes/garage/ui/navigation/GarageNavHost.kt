package com.writes.garage.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.writes.garage.feature.shared.LocalAppContainer
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.navArgument
import com.writes.garage.R
import com.writes.garage.feature.dashboard.DashboardScreen
import com.writes.garage.feature.entry.EntryEditScreen
import com.writes.garage.feature.garage.DetailingScreen
import com.writes.garage.feature.garage.GalleryScreen
import com.writes.garage.feature.garage.GarageScreen
import com.writes.garage.feature.garage.PartsScreen
import com.writes.garage.feature.garage.WarrantiesScreen
import com.writes.garage.core.model.GallerySection
import com.writes.garage.feature.garage.GarageSection
import com.writes.garage.feature.garage.RecallsScreen
import com.writes.garage.feature.garage.VehicleEditScreen
import com.writes.garage.feature.handover.HandoverScreen
import com.writes.garage.feature.log.EntryDetailScreen
import com.writes.garage.feature.log.LogScreen
import com.writes.garage.feature.receipt.ReceiptScreen
import com.writes.garage.feature.settings.PaywallScreen
import com.writes.garage.feature.settings.ProfileScreen
import com.writes.garage.feature.settings.RemindersScreen
import com.writes.garage.feature.settings.ThemeScreen
import com.writes.garage.feature.settings.SettingsScreen
import com.writes.garage.feature.shared.ProGate
import com.writes.garage.feature.stats.StatsScreen
import com.writes.garage.feature.voice.VoiceScreen

private data class Tab(val route: String, val labelRes: Int, val icon: ImageVector)

private val tabs = listOf(
    Tab(Routes.DASHBOARD, R.string.tab_dashboard, Icons.Filled.Home),
    Tab(Routes.LOG, R.string.tab_log, Icons.AutoMirrored.Filled.List),
    Tab(Routes.GARAGE, R.string.tab_garage, Icons.Filled.Build),
    Tab(Routes.STATS, R.string.tab_stats, Icons.Filled.DateRange),
    Tab(Routes.SETTINGS, R.string.tab_settings, Icons.Filled.Settings),
)

@Composable
fun GarageNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showBar = tabs.any { it.route == currentRoute }
    val back: () -> Unit = { navController.popBackStack() }
    val upgrade: () -> Unit = { navController.navigate(Routes.PAYWALL) }
    val vehicleArg = listOf(navArgument(Routes.ARG_VEHICLE_ID) { type = NavType.StringType })

    ReviewPromptHost(currentRoute)

    Scaffold(
        modifier = modifier,
        bottomBar = {
            if (showBar) {
                NavigationBar {
                    tabs.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(stringResource(tab.labelRes)) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Routes.DASHBOARD,
            modifier = Modifier.padding(padding).statusBarsPadding(),
        ) {
            composable(Routes.DASHBOARD) {
                DashboardScreen(
                    onAddEntry = { navController.navigate(Routes.entryEdit()) },
                    onScanReceipt = { navController.navigate(Routes.RECEIPT) },
                    onVoice = { navController.navigate(Routes.VOICE) },
                    onHandover = { navController.navigate(Routes.HANDOVER) },
                    onOpenEntry = { v, e -> navController.navigate(Routes.entryDetail(v, e)) },
                    onReminders = { navController.navigate(Routes.REMINDERS) },
                    onRecalls = { navController.navigate(Routes.recalls(it)) },
                    onWarranties = { navController.navigate(Routes.warranties(it)) },
                )
            }
            composable(Routes.LOG) {
                LogScreen(
                    onOpenEntry = { v, e -> navController.navigate(Routes.entryDetail(v, e)) },
                    onAddEntry = { navController.navigate(Routes.entryEdit()) },
                )
            }
            composable(
                Routes.ENTRY_DETAIL,
                arguments = listOf(
                    navArgument(Routes.ARG_VEHICLE_ID) { type = NavType.StringType },
                    navArgument(Routes.ARG_ENTRY_ID) { type = NavType.StringType },
                ),
            ) { entry ->
                val vehicleId = entry.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty()
                val entryId = entry.arguments?.getString(Routes.ARG_ENTRY_ID).orEmpty()
                EntryDetailScreen(
                    vehicleId = vehicleId,
                    entryId = entryId,
                    onEdit = { navController.navigate(Routes.entryEdit(vehicleId, entryId)) },
                    onBack = back,
                )
            }
            composable(
                Routes.ENTRY_EDIT,
                arguments = listOf(
                    navArgument(Routes.ARG_VEHICLE_ID) { type = NavType.StringType; nullable = true; defaultValue = null },
                    navArgument(Routes.ARG_ENTRY_ID) { type = NavType.StringType; nullable = true; defaultValue = null },
                ),
            ) { entry ->
                EntryEditScreen(
                    vehicleId = entry.arguments?.getString(Routes.ARG_VEHICLE_ID),
                    entryId = entry.arguments?.getString(Routes.ARG_ENTRY_ID),
                    onDone = back,
                    onUpgrade = { navController.navigate(Routes.PAYWALL) },
                )
            }
            composable(Routes.GARAGE) {
                GarageScreen(
                    onAddVehicle = { navController.navigate(Routes.vehicleEdit()) },
                    onEditVehicle = { navController.navigate(Routes.vehicleEdit(it)) },
                    onRecalls = { navController.navigate(Routes.recalls(it)) },
                    onUpgrade = { navController.navigate(Routes.PAYWALL) },
                    onOpenSection = { section, vehicleId ->
                        navController.navigate(
                            when (section) {
                                GarageSection.WARRANTIES -> Routes.warranties(vehicleId)
                                GarageSection.GALLERY -> Routes.gallery(vehicleId)
                                GarageSection.WHEELS -> Routes.wheels(vehicleId)
                                GarageSection.PARTS -> Routes.parts(vehicleId)
                                GarageSection.DETAILING -> Routes.detailing(vehicleId)
                            },
                        )
                    },
                )
            }
            composable(
                Routes.VEHICLE_EDIT,
                arguments = listOf(
                    navArgument(Routes.ARG_VEHICLE_ID) { type = NavType.StringType; nullable = true; defaultValue = null },
                ),
            ) { entry ->
                VehicleEditScreen(
                    vehicleId = entry.arguments?.getString(Routes.ARG_VEHICLE_ID),
                    onDone = back,
                    onUpgrade = { navController.navigate(Routes.PAYWALL) },
                )
            }
            composable(
                Routes.RECALLS,
                arguments = listOf(navArgument(Routes.ARG_VEHICLE_ID) { type = NavType.StringType }),
            ) { entry ->
                ProRoute(GARAGE_TOOLS_PRO, upgrade, back) { RecallsScreen(vehicleId = entry.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), onBack = back) }
            }
            composable(Routes.WARRANTIES, arguments = vehicleArg) { e ->
                ProRoute(GARAGE_TOOLS_PRO, upgrade, back) { WarrantiesScreen(vehicleId = e.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), onBack = back) }
            }
            composable(Routes.GALLERY, arguments = vehicleArg) { e ->
                ProRoute(GARAGE_TOOLS_PRO, upgrade, back) { GalleryScreen(e.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), GallerySection.MAIN, back) }
            }
            composable(Routes.WHEELS, arguments = vehicleArg) { e ->
                ProRoute(GARAGE_TOOLS_PRO, upgrade, back) { GalleryScreen(e.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), GallerySection.WHEEL, back) }
            }
            composable(Routes.PARTS, arguments = vehicleArg) { e ->
                ProRoute(GARAGE_TOOLS_PRO, upgrade, back) { PartsScreen(vehicleId = e.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), onBack = back) }
            }
            composable(Routes.DETAILING, arguments = vehicleArg) { e ->
                ProRoute(GARAGE_TOOLS_PRO, upgrade, back) { DetailingScreen(vehicleId = e.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), onBack = back) }
            }
            composable(Routes.STATS) { ProRoute("Stats are a Pro feature. Unlock MPG trends, cost breakdowns, and wear history for every vehicle.", upgrade, back) { StatsScreen() } }
            composable(Routes.RECEIPT) { ReceiptScreen(onDone = back, onUpgrade = { navController.navigate(Routes.PAYWALL) }) }
            composable(Routes.VOICE) { VoiceScreen(onDone = back, onUpgrade = { navController.navigate(Routes.PAYWALL) }) }
            composable(Routes.HANDOVER) { HandoverScreen(onBack = back, onUpgrade = { navController.navigate(Routes.PAYWALL) }) }
            composable(Routes.SETTINGS) {
                SettingsScreen(
                    onReminders = { navController.navigate(Routes.REMINDERS) },
                    onProfile = { navController.navigate(Routes.PROFILE) },
                    onTheme = { navController.navigate(Routes.THEME) },
                    onVehicles = {
                        navController.navigate(Routes.GARAGE) {
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
            composable(Routes.REMINDERS) { RemindersScreen(onBack = back) }
            composable(Routes.PROFILE) { ProfileScreen(onBack = back) }
            composable(Routes.THEME) { ThemeScreen(onBack = back, onUpgrade = { navController.navigate(Routes.PAYWALL) }) }
            composable(Routes.PAYWALL) { PaywallScreen(onBack = back) }
        }
    }
}

private const val GARAGE_TOOLS_PRO = "Garage tools are part of Pro. Spare parts, detailing, warranty, photos, wheels, and recalls unlock with Pro."

/** Pro-only destination: the same entitlement check as the entry points, so a deep link or stale back stack can't bypass it. */
@Composable
private fun ProRoute(message: String, onUpgrade: () -> Unit, onBack: () -> Unit, content: @Composable () -> Unit) {
    val isPro by LocalAppContainer.current.purchases.entitlement.collectAsState()
    ProGate(isPro = isPro.isPro, onUpgrade = onUpgrade, lockedMessage = message, locked = {
        androidx.compose.foundation.layout.Column(
            Modifier.statusBarsPadding().padding(16.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
        ) {
            Text(message)
            androidx.compose.material3.Button(onClick = onUpgrade) { Text("Upgrade to Pro") }
            androidx.compose.material3.TextButton(onClick = onBack) { Text("Back") }
        }
    }, content = content)
}

/** Routes where a rating request is fair: calm browsing screens, never forms, the first-run flow or the paywall. */
private val calmRoutes = setOf(Routes.DASHBOARD, Routes.LOG, Routes.GARAGE, Routes.STATS, Routes.SETTINGS, Routes.ENTRY_DETAIL)

@Composable
private fun ReviewPromptHost(currentRoute: String?) {
    val container = LocalAppContainer.current
    val due by container.reviews.due.collectAsState()
    val context = LocalContext.current
    LaunchedEffect(due, currentRoute) {
        val activity = context as? android.app.Activity ?: return@LaunchedEffect
        if (due && currentRoute in calmRoutes) {
            container.reviewLauncher.launch(activity) { container.reviews.markPrompted() }
        }
    }
}
