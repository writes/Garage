package com.writes.garage.ui.navigation

import androidx.compose.foundation.layout.padding
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
import androidx.compose.runtime.getValue
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
import com.writes.garage.feature.garage.GarageScreen
import com.writes.garage.feature.garage.RecallsScreen
import com.writes.garage.feature.garage.VehicleEditScreen
import com.writes.garage.feature.handover.HandoverScreen
import com.writes.garage.feature.log.EntryDetailScreen
import com.writes.garage.feature.log.LogScreen
import com.writes.garage.feature.receipt.ReceiptScreen
import com.writes.garage.feature.settings.PaywallScreen
import com.writes.garage.feature.settings.SettingsScreen
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
                )
            }
            composable(Routes.GARAGE) {
                GarageScreen(
                    onAddVehicle = { navController.navigate(Routes.vehicleEdit()) },
                    onEditVehicle = { navController.navigate(Routes.vehicleEdit(it)) },
                    onRecalls = { navController.navigate(Routes.recalls(it)) },
                    onUpgrade = { navController.navigate(Routes.PAYWALL) },
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
                RecallsScreen(vehicleId = entry.arguments?.getString(Routes.ARG_VEHICLE_ID).orEmpty(), onBack = back)
            }
            composable(Routes.STATS) { StatsScreen() }
            composable(Routes.RECEIPT) { ReceiptScreen(onDone = back) }
            composable(Routes.VOICE) { VoiceScreen(onDone = back, onUpgrade = { navController.navigate(Routes.PAYWALL) }) }
            composable(Routes.HANDOVER) { HandoverScreen(onBack = back) }
            composable(Routes.SETTINGS) { SettingsScreen() }
            composable(Routes.PAYWALL) { PaywallScreen(onBack = back) }
        }
    }
}
