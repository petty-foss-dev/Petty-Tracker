package com.isaaclamb.pettytracker.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.isaaclamb.pettytracker.TrackerApplication
import com.isaaclamb.pettytracker.domain.Deadline
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.Renewals
import com.isaaclamb.pettytracker.domain.deadline
import com.isaaclamb.pettytracker.domain.deadlineStatus
import com.isaaclamb.pettytracker.domain.leadDays
import com.isaaclamb.pettytracker.ui.subscriptions.monthlyTotals
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.time.LocalDate

data class DashboardEntry(val deadline: Deadline, val status: DeadlineStatus)

enum class DashboardBand {
    WEEK, MONTH, LATER;

    companion object {
        fun of(days: Long) = when {
            days <= 7 -> WEEK
            days <= 30 -> MONTH
            else -> LATER
        }
    }
}

data class DashboardState(
    val loaded: Boolean = false,
    val isEmpty: Boolean = true,
    val pastDue: List<DashboardEntry> = emptyList(),
    val upcoming: List<Pair<DashboardBand, List<DashboardEntry>>> = emptyList(),
    val upcomingCount: Int = 0,
    val monthlyTotals: Map<String, BigDecimal> = emptyMap(),
    val remindersEnabled: Boolean = false,
    val reminderPromptDismissed: Boolean = true,
)

class DashboardViewModel(private val app: TrackerApplication) : ViewModel() {
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
        val banded = upcoming.groupBy { DashboardBand.of(it.deadline.daysFrom(today)) }

        DashboardState(
            loaded = true,
            isEmpty = products.isEmpty() && subscriptions.isEmpty() && documents.isEmpty(),
            pastDue = pastDue,
            upcoming = DashboardBand.entries.mapNotNull { band -> banded[band]?.let { band to it } },
            upcomingCount = upcoming.size,
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
