package com.enve.keep.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.enve.keep.KeepApplication
import com.enve.keep.domain.Deadline
import com.enve.keep.domain.DeadlineStatus
import com.enve.keep.domain.RecordKind
import com.enve.keep.domain.Renewals
import com.enve.keep.domain.deadline
import com.enve.keep.domain.deadlineStatus
import com.enve.keep.domain.leadDays
import com.enve.keep.ui.subscriptions.monthlyTotals
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.time.LocalDate

data class DashboardEntry(val deadline: Deadline, val status: DeadlineStatus)

data class CategorySummary(val count: Int = 0, val next: Deadline? = null)

data class DashboardState(
    val loaded: Boolean = false,
    val isEmpty: Boolean = true,
    val pastDue: List<DashboardEntry> = emptyList(),
    val upcoming: List<DashboardEntry> = emptyList(),
    val warranties: CategorySummary = CategorySummary(),
    val subscriptions: CategorySummary = CategorySummary(),
    val documents: CategorySummary = CategorySummary(),
    val monthlyTotals: Map<String, BigDecimal> = emptyMap(),
    val remindersEnabled: Boolean = false,
    val reminderPromptDismissed: Boolean = true,
)

class DashboardViewModel(private val app: KeepApplication) : ViewModel() {
    private val repository = app.container.repository
    private val settingsRepository = app.container.settingsRepository

    val state: StateFlow<DashboardState> = combine(
        repository.products,
        repository.subscriptions,
        repository.documents,
        settingsRepository.settings,
    ) { products, subscriptions, documents, settings ->
        val today = LocalDate.now()
        val deadlines = products.mapNotNull { it.deadline() } +
            subscriptions.mapNotNull { it.deadline() } +
            documents.mapNotNull { it.deadline() }
        val entries = deadlines
            .map { DashboardEntry(it, deadlineStatus(it.date, today, settings.leadDays(it.kind))) }
            .sortedBy { it.deadline.date }
        val pastDue = entries.filter {
            it.status == DeadlineStatus.PAST &&
                (it.deadline.kind != RecordKind.WARRANTY || it.deadline.daysFrom(today) >= -RECENT_WARRANTY_DAYS)
        }.reversed()
        val upcoming = entries.filter { it.status == DeadlineStatus.TODAY || it.status == DeadlineStatus.SOON }

        fun summary(kind: RecordKind, count: Int) = CategorySummary(
            count = count,
            next = deadlines.filter { it.kind == kind && !it.date.isBefore(today) }.minByOrNull { it.date },
        )

        DashboardState(
            loaded = true,
            isEmpty = products.isEmpty() && subscriptions.isEmpty() && documents.isEmpty(),
            pastDue = pastDue,
            upcoming = upcoming,
            warranties = summary(RecordKind.WARRANTY, products.size),
            subscriptions = summary(RecordKind.SUBSCRIPTION, subscriptions.count { it.isActive }),
            documents = summary(RecordKind.DOCUMENT, documents.size),
            monthlyTotals = monthlyTotals(subscriptions),
            remindersEnabled = settings.remindersEnabled,
            reminderPromptDismissed = settings.reminderPromptDismissed,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DashboardState())

    fun markRenewed(id: Long) {
        viewModelScope.launch { repository.updateSubscription(id) { Renewals.advance(it, LocalDate.now()) } }
    }

    fun dismissReminderPrompt() {
        viewModelScope.launch { settingsRepository.update { it.copy(reminderPromptDismissed = true) } }
    }

    private companion object {
        const val RECENT_WARRANTY_DAYS = 30L
    }
}
