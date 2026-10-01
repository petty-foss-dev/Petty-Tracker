package com.isaaclamb.pettytracker.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.Clear
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.ui.Formats
import com.isaaclamb.pettytracker.ui.theme.LocalStatusColors
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs

val RecordKind.icon: ImageVector
    get() = when (this) {
        RecordKind.WARRANTY -> Icons.Outlined.VerifiedUser
        RecordKind.SUBSCRIPTION -> Icons.Outlined.Autorenew
        RecordKind.DOCUMENT -> Icons.Outlined.Description
    }

val RecordKind.label: Int
    get() = when (this) {
        RecordKind.WARRANTY -> R.string.kind_warranty
        RecordKind.SUBSCRIPTION -> R.string.kind_subscription
        RecordKind.DOCUMENT -> R.string.kind_document
    }

/**
 * "Ends in 12 days", "Expired Mar 1, 2024", etc. Dates far away read better as absolute dates;
 * [withDate] appends the exact date to relative phrasing.
 */
@Composable
fun deadlineText(kind: RecordKind, date: LocalDate, today: LocalDate = LocalDate.now(), withDate: Boolean = false): String {
    val res = LocalResources.current
    val days = ChronoUnit.DAYS.between(today, date)
    val relative = abs(days) <= RELATIVE_WINDOW_DAYS
    val whenText = if (relative) Formats.relativeDays(res, days) else Formats.date(date)
    val future = days >= 0
    val text = stringResource(
        when (kind) {
            RecordKind.WARRANTY -> if (future) R.string.deadline_warranty_future else R.string.deadline_warranty_past
            RecordKind.SUBSCRIPTION -> if (future) R.string.deadline_subscription_future else R.string.deadline_subscription_past
            RecordKind.DOCUMENT -> if (future) R.string.deadline_document_future else R.string.deadline_document_past
        },
        whenText,
    )
    return if (relative && withDate) "$text · ${Formats.date(date)}" else text
}

private const val RELATIVE_WINDOW_DAYS = 60

/** List sections in reading order: what needs action, what's fine, what has no date, what's over. */
enum class StatusSection {
    SOON, OK, UNDATED, PAST;

    fun title(kind: RecordKind): Int = when (this) {
        SOON -> if (kind == RecordKind.DOCUMENT) R.string.filter_expiring else R.string.filter_ending
        OK -> if (kind == RecordKind.DOCUMENT) R.string.filter_valid else R.string.filter_covered
        UNDATED -> if (kind == RecordKind.DOCUMENT) R.string.document_no_expiry else R.string.warranty_no_date
        PAST -> if (kind == RecordKind.DOCUMENT) R.string.filter_expired else R.string.section_ended
    }

    companion object {
        fun of(status: DeadlineStatus) = when (status) {
            DeadlineStatus.TODAY, DeadlineStatus.SOON -> SOON
            DeadlineStatus.OK -> OK
            DeadlineStatus.NONE -> UNDATED
            DeadlineStatus.PAST -> PAST
        }

        /** Splits items into non-empty sections, keeping each section's order. */
        fun <T> group(items: List<T>, status: (T) -> DeadlineStatus): List<Pair<StatusSection, List<T>>> {
            val grouped = items.groupBy { of(status(it)) }
            return entries.mapNotNull { section -> grouped[section]?.let { section to it } }
        }
    }
}

@Composable
fun statusColors(status: DeadlineStatus): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    val statusColors = LocalStatusColors.current
    return when (status) {
        DeadlineStatus.PAST, DeadlineStatus.TODAY -> scheme.errorContainer to scheme.onErrorContainer
        DeadlineStatus.SOON -> statusColors.soonContainer to statusColors.soon
        DeadlineStatus.OK -> statusColors.okContainer to statusColors.ok
        DeadlineStatus.NONE -> scheme.surfaceContainerHighest to scheme.onSurfaceVariant
    }
}

@Composable
fun StatusPill(status: DeadlineStatus, text: String, modifier: Modifier = Modifier) {
    val (container, content) = statusColors(status)
    Surface(color = container, contentColor = content, shape = CircleShape, modifier = modifier) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

@Composable
fun KindBadge(kind: RecordKind, status: DeadlineStatus, modifier: Modifier = Modifier) {
    val (container, content) = statusColors(status)
    Surface(color = container, contentColor = content, shape = RoundedCornerShape(12.dp), modifier = modifier.size(44.dp)) {
        Icon(kind.icon, contentDescription = stringResource(kind.label), modifier = Modifier.padding(10.dp))
    }
}

@Composable
fun RecordCard(
    kind: RecordKind,
    title: String,
    subtitle: String?,
    status: DeadlineStatus,
    statusText: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    OutlinedCard(onClick = onClick, colors = elevatedCardColors(), shape = CardShape, modifier = modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(14.dp),
        ) {
            KindBadge(kind, status)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (statusText != null) StatusPill(status, statusText)
            }
            trailing?.invoke()
        }
    }
}

/** Card shape and elevated surface shared by record, detail and attachment cards. */
val CardShape = RoundedCornerShape(20.dp)

@Composable
fun elevatedCardColors() = CardDefaults.outlinedCardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)

/** A small, tracked, uppercase section label. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth().padding(top = 12.dp, start = 4.dp),
    ) {
        Text(
            text.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.5.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        action?.invoke()
    }
}

@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp),
    ) {
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
            shape = CircleShape,
            modifier = Modifier.size(88.dp),
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.padding(24.dp))
        }
        Spacer(Modifier.height(20.dp))
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(8.dp))
        Text(
            body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(20.dp))
            FilledTonalButton(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
fun NoMatches() {
    EmptyState(
        icon = Icons.Outlined.SearchOff,
        title = stringResource(R.string.no_matches_title),
        body = stringResource(R.string.no_matches_body),
    )
}

@Composable
fun BackButton(onClick: () -> Unit) {
    IconButton(onClick = onClick) {
        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.action_back))
    }
}

@Composable
fun SearchField(query: String, onQueryChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        placeholder = { Text(placeholder) },
        leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(Icons.Outlined.Clear, contentDescription = stringResource(R.string.action_clear_search))
                }
            }
        },
        singleLine = true,
        shape = CircleShape,
        colors = TextFieldDefaults.colors(
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        ),
        modifier = modifier.fillMaxWidth().clip(CircleShape),
    )
}

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = {
            TextButton(onClick = { onDismiss(); onConfirm() }) { Text(confirmLabel) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}

/** Groups a detail screen's label/value rows on one card, with the values selectable. */
@Composable
fun DetailCard(content: @Composable () -> Unit) {
    OutlinedCard(colors = elevatedCardColors(), shape = CardShape, modifier = Modifier.fillMaxWidth()) {
        SelectionContainer {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { content() }
        }
    }
}

@Composable
fun DetailRow(label: String, value: String?, modifier: Modifier = Modifier) {
    if (value.isNullOrBlank()) return
    Column(modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}
