package com.isaaclamb.pettytracker.reminders

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.isaaclamb.pettytracker.TrackerApplication
import com.isaaclamb.pettytracker.data.SentReminder
import com.isaaclamb.pettytracker.domain.deadline
import com.isaaclamb.pettytracker.domain.leadDays
import java.time.LocalDate

class ReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val container = (applicationContext as TrackerApplication).container
        val settings = container.settingsRepository.current()
        if (!settings.remindersEnabled || !ReminderNotifications.canPost(applicationContext)) return Result.success()

        val dao = container.database.dao()
        val today = LocalDate.now()
        val deadlines = dao.allProducts().mapNotNull { it.deadline() } +
            dao.allSubscriptions().mapNotNull { it.deadline() } +
            dao.allDocuments().mapNotNull { it.deadline() }

        for (deadline in deadlines) {
            val days = deadline.daysFrom(today)
            val stage = when {
                days in -MISSED_GRACE_DAYS..0 -> "due"
                days in 1L..settings.leadDays(deadline.kind).toLong() -> "soon"
                else -> continue
            }
            val key = "${deadline.kind}:${deadline.id}:${deadline.date}:$stage"
            if (dao.markReminderSent(SentReminder(key)) != -1L) {
                ReminderNotifications.post(applicationContext, deadline, days)
            }
        }
        return Result.success()
    }

    private companion object {
        // Covers days the worker didn't get to run, without alerting about long-past dates.
        const val MISSED_GRACE_DAYS = 7L
    }
}
