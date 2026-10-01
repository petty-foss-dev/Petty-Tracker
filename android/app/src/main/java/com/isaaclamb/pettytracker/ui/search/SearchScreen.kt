package com.isaaclamb.pettytracker.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import com.isaaclamb.pettytracker.TrackerApplication
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.deadlineStatus
import com.isaaclamb.pettytracker.domain.matches
import com.isaaclamb.pettytracker.ui.components.BackButton
import com.isaaclamb.pettytracker.ui.components.EmptyState
import com.isaaclamb.pettytracker.ui.components.NoMatches
import com.isaaclamb.pettytracker.ui.components.RecordCard
import com.isaaclamb.pettytracker.ui.components.SearchField
import com.isaaclamb.pettytracker.ui.components.SectionHeader
import com.isaaclamb.pettytracker.ui.components.deadlineText
import com.isaaclamb.pettytracker.ui.documents.subtitle
import com.isaaclamb.pettytracker.ui.trackerViewModel
import com.isaaclamb.pettytracker.ui.openRecord
import com.isaaclamb.pettytracker.ui.products.subtitle
import com.isaaclamb.pettytracker.ui.subscriptions.priceText
import com.isaaclamb.pettytracker.ui.subscriptions.statusText
import com.isaaclamb.pettytracker.ui.subscriptions.subscriptionStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.Subscription
import java.time.LocalDate

data class SearchResults(
    val products: List<Product> = emptyList(),
    val subscriptions: List<Subscription> = emptyList(),
    val documents: List<Document> = emptyList(),
) {
    val isEmpty get() = products.isEmpty() && subscriptions.isEmpty() && documents.isEmpty()
}

class SearchViewModel(app: TrackerApplication) : ViewModel() {
    val query = MutableStateFlow("")
    val settings = app.container.settingsRepository.settings

    val results = combine(
        app.container.repository.products,
        app.container.repository.subscriptions,
        app.container.repository.documents,
        query,
    ) { products, subscriptions, documents, query ->
        if (query.isBlank()) {
            SearchResults()
        } else {
            SearchResults(
                products.filter { it.matches(query) },
                subscriptions.filter { it.matches(query) },
                documents.filter { it.matches(query) },
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SearchResults())
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, _ -> SearchViewModel(app) }
    val query by viewModel.query.collectAsStateWithLifecycle()
    val results by viewModel.results.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle(null)
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    SearchField(
                        query,
                        { viewModel.query.value = it },
                        stringResource(R.string.search_everything),
                        modifier = Modifier.padding(end = 12.dp).focusRequester(focusRequester),
                    )
                },
                navigationIcon = { BackButton { navController.popBackStack() } },
            )
        },
    ) { padding ->
        val today = LocalDate.now()
        LazyColumn(
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxSize().padding(padding).imePadding(),
        ) {
            val current = settings ?: return@LazyColumn
            when {
                query.isBlank() -> item {
                    EmptyState(
                        icon = Icons.Outlined.Search,
                        title = stringResource(R.string.search_hint_title),
                        body = stringResource(R.string.search_hint_body),
                    )
                }
                results.isEmpty -> item { NoMatches() }
            }
            if (results.products.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.tab_warranties)) }
                items(results.products, key = { "p${it.id}" }) { product ->
                    RecordCard(
                        kind = RecordKind.WARRANTY,
                        title = product.name,
                        subtitle = product.subtitle(),
                        status = deadlineStatus(product.warrantyExpires, today, current.warrantyLeadDays),
                        statusText = product.warrantyExpires?.let { deadlineText(RecordKind.WARRANTY, it) },
                        onClick = { navController.openRecord(RecordKind.WARRANTY, product.id) },
                    )
                }
            }
            if (results.subscriptions.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.tab_subscriptions)) }
                items(results.subscriptions, key = { "s${it.id}" }) { subscription ->
                    RecordCard(
                        kind = RecordKind.SUBSCRIPTION,
                        title = subscription.name,
                        subtitle = subscription.priceText(),
                        status = subscriptionStatus(subscription, today, current.subscriptionLeadDays),
                        statusText = subscription.statusText(),
                        onClick = { navController.openRecord(RecordKind.SUBSCRIPTION, subscription.id) },
                    )
                }
            }
            if (results.documents.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.tab_documents)) }
                items(results.documents, key = { "d${it.id}" }) { document ->
                    RecordCard(
                        kind = RecordKind.DOCUMENT,
                        title = document.title,
                        subtitle = document.subtitle(),
                        status = deadlineStatus(document.expiresOn, today, current.documentLeadDays),
                        statusText = document.expiresOn?.let { deadlineText(RecordKind.DOCUMENT, it) },
                        onClick = { navController.openRecord(RecordKind.DOCUMENT, document.id) },
                    )
                }
            }
        }
    }
}
