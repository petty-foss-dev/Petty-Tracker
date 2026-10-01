package com.isaaclamb.pettytracker.reminders

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.isaaclamb.pettytracker.MainActivity
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.domain.Deadline
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.ui.Formats

object ReminderNotifications {
    private const val CHANNEL_ID = "deadlines"

    fun createChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = context.getString(R.string.notification_channel_description) }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun canPost(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (android.os.Build.VERSION.SDK_INT < 33 ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED)

    fun post(context: Context, deadline: Deadline, days: Long) {
        if (!canPost(context)) return
        val res = context.resources
        val upcoming = days > 0
        val title = res.getString(
            when (deadline.kind) {
                RecordKind.WARRANTY -> when {
                    upcoming -> R.string.notification_warranty_soon
                    days == 0L -> R.string.notification_warranty_today
                    else -> R.string.notification_warranty_due
                }
                RecordKind.SUBSCRIPTION ->
                    if (upcoming) R.string.notification_subscription_soon else R.string.notification_subscription_due
                RecordKind.DOCUMENT -> when {
                    upcoming -> R.string.notification_document_soon
                    days == 0L -> R.string.notification_document_today
                    else -> R.string.notification_document_due
                }
            },
            deadline.title,
        )
        val notificationId = "${deadline.kind}:${deadline.id}".hashCode()
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(MainActivity.EXTRA_KIND, deadline.kind.name)
            .putExtra(MainActivity.EXTRA_ID, deadline.id)
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText("${Formats.relativeDays(res, days)} · ${Formats.date(deadline.date)}")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
        @Suppress("MissingPermission")
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }
}
