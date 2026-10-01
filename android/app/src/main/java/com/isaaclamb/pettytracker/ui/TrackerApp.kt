package com.isaaclamb.pettytracker.ui

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.compose.runtime.getValue
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.ui.dashboard.DashboardScreen
import com.isaaclamb.pettytracker.ui.documents.DocumentDetailScreen
import com.isaaclamb.pettytracker.ui.documents.DocumentEditScreen
import com.isaaclamb.pettytracker.ui.documents.DocumentListScreen
import com.isaaclamb.pettytracker.ui.products.ProductDetailScreen
import com.isaaclamb.pettytracker.ui.products.ProductEditScreen
import com.isaaclamb.pettytracker.ui.products.ProductListScreen
import com.isaaclamb.pettytracker.ui.search.SearchScreen
import com.isaaclamb.pettytracker.ui.settings.SettingsScreen
import com.isaaclamb.pettytracker.ui.subscriptions.SubscriptionDetailScreen
import com.isaaclamb.pettytracker.ui.subscriptions.SubscriptionEditScreen
import com.isaaclamb.pettytracker.ui.subscriptions.SubscriptionListScreen
import kotlinx.serialization.Serializable

data class OpenRecord(val kind: RecordKind, val id: Long)

@Serializable object HomeRoute
@Serializable object ProductsRoute
@Serializable object SubscriptionsRoute
@Serializable object DocumentsRoute
@Serializable object SearchRoute
@Serializable object SettingsRoute
@Serializable data class ProductDetailRoute(val id: Long)
@Serializable data class ProductEditRoute(val id: Long = 0)
@Serializable data class SubscriptionDetailRoute(val id: Long)
@Serializable data class SubscriptionEditRoute(val id: Long = 0)
@Serializable data class DocumentDetailRoute(val id: Long)
@Serializable data class DocumentEditRoute(val id: Long = 0)

enum class Tab(val route: Any, val label: Int, val icon: ImageVector) {
    HOME(HomeRoute, R.string.tab_home, Icons.Outlined.Home),
    WARRANTIES(ProductsRoute, R.string.tab_warranties, Icons.Outlined.VerifiedUser),
    SUBSCRIPTIONS(SubscriptionsRoute, R.string.tab_subscriptions, Icons.Outlined.Autorenew),
    DOCUMENTS(DocumentsRoute, R.string.tab_documents, Icons.Outlined.Description),
}

fun NavController.openRecord(kind: RecordKind, id: Long) = navigate(
    when (kind) {
        RecordKind.WARRANTY -> ProductDetailRoute(id)
        RecordKind.SUBSCRIPTION -> SubscriptionDetailRoute(id)
        RecordKind.DOCUMENT -> DocumentDetailRoute(id)
    }
)

fun NavController.createRecord(kind: RecordKind) = navigate(
    when (kind) {
        RecordKind.WARRANTY -> ProductEditRoute()
        RecordKind.SUBSCRIPTION -> SubscriptionEditRoute()
        RecordKind.DOCUMENT -> DocumentEditRoute()
    }
)

fun NavController.selectTab(tab: Tab) = navigate(tab.route) {
    popUpTo(graph.findStartDestination().id) { saveState = true }
    launchSingleTop = true
    restoreState = true
}

@Composable
fun TrackerApp(openRequest: OpenRecord?, onOpenHandled: () -> Unit) {
    val navController = rememberNavController()

    LaunchedEffect(openRequest) {
        openRequest ?: return@LaunchedEffect
        navController.openRecord(openRequest.kind, openRequest.id)
        onOpenHandled()
    }

    NavHost(
        navController = navController,
        startDestination = HomeRoute,
        enterTransition = { fadeIn() },
        exitTransition = { fadeOut() },
    ) {
        composable<HomeRoute> { DashboardScreen(navController) }
        composable<ProductsRoute> { ProductListScreen(navController) }
        composable<SubscriptionsRoute> { SubscriptionListScreen(navController) }
        composable<DocumentsRoute> { DocumentListScreen(navController) }
        composable<SearchRoute> { SearchScreen(navController) }
        composable<SettingsRoute> { SettingsScreen(navController) }
        composable<ProductDetailRoute> { ProductDetailScreen(navController) }
        composable<ProductEditRoute> { ProductEditScreen(navController) }
        composable<SubscriptionDetailRoute> { SubscriptionDetailScreen(navController) }
        composable<SubscriptionEditRoute> { SubscriptionEditScreen(navController) }
        composable<DocumentDetailRoute> { DocumentDetailScreen(navController) }
        composable<DocumentEditRoute> { DocumentEditScreen(navController) }
    }
}

@Composable
fun TrackerNavigationBar(navController: NavController) {
    val entry by navController.currentBackStackEntryAsState()
    NavigationBar {
        Tab.entries.forEach { tab ->
            val selected = entry?.destination?.hasRoute(tab.route::class) == true
            NavigationBarItem(
                selected = selected,
                onClick = { if (!selected) navController.selectTab(tab) },
                icon = { Icon(tab.icon, contentDescription = null) },
                label = { Text(stringResource(tab.label)) },
            )
        }
    }
}
