@file:UseSerializers(LocalDateSerializer::class)

package com.enve.keep.ui.subscriptions

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.toRoute
import com.enve.keep.KeepApplication
import com.enve.keep.data.CycleUnit
import com.enve.keep.data.LocalDateSerializer
import com.enve.keep.data.Subscription
import com.enve.keep.domain.DeadlineStatus
import com.enve.keep.domain.Money
import com.enve.keep.domain.Renewals
import com.enve.keep.domain.deadlineStatus
import com.enve.keep.domain.matches
import com.enve.keep.ui.FormViewModel
import com.enve.keep.ui.SubscriptionDetailRoute
import com.enve.keep.ui.SubscriptionEditRoute
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import java.math.BigDecimal
import java.time.LocalDate

enum class SubscriptionFilter { ACTIVE, CANCELED, ALL }

data class SubscriptionItem(val subscription: Subscription, val status: DeadlineStatus)

data class SubscriptionListState(
    val loaded: Boolean = false,
    val hasAny: Boolean = false,
    val items: List<SubscriptionItem> = emptyList(),
    val monthlyTotals: Map<String, BigDecimal> = emptyMap(),
    val activeCount: Int = 0,
)

fun subscriptionStatus(subscription: Subscription, today: LocalDate, leadDays: Int): DeadlineStatus =
    if (subscription.isActive) deadlineStatus(subscription.nextRenewal, today, leadDays) else DeadlineStatus.NONE

/** Estimated monthly spend of active subscriptions, per currency. */
fun monthlyTotals(subscriptions: List<Subscription>): Map<String, BigDecimal> = subscriptions
    .filter { it.isActive && it.price != null }
    .groupBy { it.currency }
    .mapValues { (_, items) ->
        items.fold(BigDecimal.ZERO) { sum, it -> sum + Renewals.monthlyCost(it.price!!, it.cycleCount, it.cycleUnit) }
    }

class SubscriptionListViewModel(app: KeepApplication) : ViewModel() {
    val query = MutableStateFlow("")
    val filter = MutableStateFlow(SubscriptionFilter.ACTIVE)

    val state: StateFlow<SubscriptionListState> = combine(
        app.container.repository.subscriptions,
        app.container.settingsRepository.settings,
        query,
        filter,
    ) { subscriptions, settings, query, filter ->
        val today = LocalDate.now()
        val items = subscriptions
            .filter { it.matches(query) }
            .filter {
                when (filter) {
                    SubscriptionFilter.ACTIVE -> it.isActive
                    SubscriptionFilter.CANCELED -> !it.isActive
                    SubscriptionFilter.ALL -> true
                }
            }
            .sortedWith(compareBy({ !it.isActive }, { it.nextRenewal }))
            .map { SubscriptionItem(it, subscriptionStatus(it, today, settings.subscriptionLeadDays)) }
        SubscriptionListState(
            loaded = true,
            hasAny = subscriptions.isNotEmpty(),
            items = items,
            monthlyTotals = monthlyTotals(subscriptions),
            activeCount = subscriptions.count { it.isActive },
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SubscriptionListState())
}

data class SubscriptionDetailState(
    val loaded: Boolean = false,
    val subscription: Subscription? = null,
    val leadDays: Int = 0,
)

class SubscriptionDetailViewModel(private val app: KeepApplication, handle: SavedStateHandle) : ViewModel() {
    private val id = handle.toRoute<SubscriptionDetailRoute>().id
    private val repository = app.container.repository

    val state: StateFlow<SubscriptionDetailState> = combine(
        repository.subscription(id),
        app.container.settingsRepository.settings,
    ) { subscription, settings ->
        SubscriptionDetailState(true, subscription, settings.subscriptionLeadDays)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SubscriptionDetailState())

    fun markRenewed() = modify { Renewals.advance(it, LocalDate.now()) }

    fun cancel() = modify { it.copy(canceledOn = LocalDate.now()) }

    fun reactivate() = modify {
        val today = LocalDate.now()
        val next = if (it.nextRenewal.isBefore(today)) {
            Renewals.nextAfter(it.anchorDate, it.cycleCount, it.cycleUnit, today.minusDays(1))
        } else {
            it.nextRenewal
        }
        it.copy(canceledOn = null, nextRenewal = next)
    }

    fun delete() {
        viewModelScope.launch { repository.deleteSubscription(id) }
    }

    private fun modify(transform: (Subscription) -> Subscription) {
        viewModelScope.launch { repository.updateSubscription(id, transform) }
    }
}

@Serializable
data class SubscriptionForm(
    val loaded: Boolean = false,
    val changed: Boolean = false,
    val showErrors: Boolean = false,
    val name: String = "",
    val price: String = "",
    val currency: String = "",
    val cycleCount: String = "1",
    val cycleUnit: CycleUnit = CycleUnit.MONTHS,
    val nextRenewal: LocalDate? = null,
    val notes: String = "",
) {
    val nameError get() = showErrors && name.isBlank()
    val priceError get() = showErrors && price.isNotBlank() && Money.parse(price) == null
    val cycleError get() = showErrors && parsedCycle == null
    val renewalError get() = showErrors && nextRenewal == null
    val parsedCycle: Int? get() = cycleCount.toIntOrNull()?.takeIf { it in 1..999 }
}

class SubscriptionEditViewModel(private val app: KeepApplication, handle: SavedStateHandle) :
    FormViewModel<SubscriptionForm>(handle, SubscriptionForm.serializer(), SubscriptionForm()) {
    val id = handle.toRoute<SubscriptionEditRoute>().id
    private var original: Subscription? = null
    private var saving = false

    init {
        viewModelScope.launch {
            val existing = if (id != 0L) app.container.repository.subscription(id).first() else null
            original = existing
            if (restored) return@launch
            if (existing == null) {
                val currency = app.container.settingsRepository.current().defaultCurrency
                update { it.copy(loaded = true, currency = currency) }
            } else {
                update {
                    SubscriptionForm(
                        loaded = true,
                        name = existing.name,
                        price = existing.price?.let(Money::formatForInput).orEmpty(),
                        currency = existing.currency,
                        cycleCount = existing.cycleCount.toString(),
                        cycleUnit = existing.cycleUnit,
                        nextRenewal = existing.nextRenewal,
                        notes = existing.notes,
                    )
                }
            }
        }
    }

    fun edit(transform: (SubscriptionForm) -> SubscriptionForm) = update { transform(it).copy(changed = true) }

    fun save(onSaved: (id: Long, isNew: Boolean) -> Unit) {
        val form = form
        val price = form.price.takeIf { it.isNotBlank() }?.let(Money::parse)
        val cycle = form.parsedCycle
        val nextRenewal = form.nextRenewal
        if (form.name.isBlank() ||
            (form.price.isNotBlank() && price == null) ||
            Money.currency(form.currency) == null ||
            cycle == null ||
            nextRenewal == null
        ) {
            update { it.copy(showErrors = true) }
            return
        }
        if (saving) return
        saving = true
        viewModelScope.launch {
            val existing = original
            val keptAnchor = existing?.takeIf {
                it.nextRenewal == nextRenewal && it.cycleCount == cycle && it.cycleUnit == form.cycleUnit
            }?.anchorDate
            val subscription = Subscription(
                id = id,
                name = form.name.trim(),
                price = price,
                currency = form.currency,
                cycleCount = cycle,
                cycleUnit = form.cycleUnit,
                nextRenewal = nextRenewal,
                anchorDate = keptAnchor ?: nextRenewal,
                canceledOn = existing?.canceledOn,
                notes = form.notes.trim(),
            )
            val savedId = app.container.repository.saveSubscription(subscription)
            onSaved(savedId, id == 0L)
        }
    }
}
