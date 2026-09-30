package com.enve.keep.ui

import android.content.res.Resources
import com.enve.keep.R
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs

object Formats {
    private val dateFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

    fun date(date: LocalDate): String = date.format(dateFormatter)

    fun relativeDays(res: Resources, days: Long): String = when {
        days == 0L -> res.getString(R.string.relative_today)
        days == 1L -> res.getString(R.string.relative_tomorrow)
        days == -1L -> res.getString(R.string.relative_yesterday)
        days > 0 -> res.getQuantityString(R.plurals.relative_in_days, days.toInt(), days.toInt())
        else -> res.getQuantityString(R.plurals.relative_days_ago, abs(days).toInt(), abs(days).toInt())
    }

    fun fileSize(bytes: Long): String = when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "%.0f KB".format(bytes / 1024.0)
        else -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
    }

    fun toPickerMillis(date: LocalDate): Long = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

    fun fromPickerMillis(millis: Long): LocalDate =
        java.time.Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
}
