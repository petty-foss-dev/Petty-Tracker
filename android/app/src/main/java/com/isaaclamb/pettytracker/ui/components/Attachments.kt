package com.isaaclamb.pettytracker.ui.components

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import com.isaaclamb.pettytracker.data.AttachmentLabel
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.automirrored.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.AttachmentStore
import com.isaaclamb.pettytracker.ui.AttachmentFormViewModel
import com.isaaclamb.pettytracker.ui.Formats
import com.isaaclamb.pettytracker.ui.RecordDetailViewModel

@Composable
fun AttachmentThumbnail(attachment: Attachment, store: AttachmentStore, modifier: Modifier = Modifier) {
    val sizePx = with(LocalDensity.current) { 56.dp.roundToPx() }
    val bitmap by produceState<Bitmap?>(null, attachment.fileName) {
        if (attachment.isImage) value = store.thumbnail(attachment.fileName, sizePx)
    }
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        shape = RoundedCornerShape(10.dp),
        modifier = modifier.size(56.dp),
    ) {
        val image = bitmap
        if (image != null) {
            Image(
                image.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.clip(RoundedCornerShape(10.dp)),
            )
        } else {
            val icon = if (attachment.mimeType == "application/pdf") Icons.Outlined.PictureAsPdf else Icons.AutoMirrored.Outlined.InsertDriveFile
            Icon(icon, contentDescription = null, modifier = Modifier.padding(14.dp))
        }
    }
}

@Composable
private fun AttachmentRow(
    attachment: Attachment,
    store: AttachmentStore,
    caption: String? = null,
    onClick: () -> Unit,
    actions: @Composable () -> Unit,
) {
    OutlinedCard(onClick = onClick, colors = elevatedCardColors(), shape = CardShape, modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(8.dp),
        ) {
            AttachmentThumbnail(attachment, store)
            Column(Modifier.weight(1f)) {
                Text(attachment.displayName, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
                Text(
                    listOfNotNull(caption, Formats.fileSize(attachment.sizeBytes)).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            actions()
        }
    }
}

/** The labels a product's files can carry, in the order the product screen groups them. */
val ProductFileLabels = listOf(
    AttachmentLabel.ITEM,
    AttachmentLabel.PART,
    AttachmentLabel.INSTRUCTIONS,
    AttachmentLabel.WARRANTY,
    AttachmentLabel.OTHER,
)

val AttachmentLabel.title: Int
    get() = when (this) {
        AttachmentLabel.ITEM -> R.string.label_item
        AttachmentLabel.PART -> R.string.label_part
        AttachmentLabel.INSTRUCTIONS -> R.string.label_instructions
        AttachmentLabel.PRODUCT_PAGE -> R.string.label_product_page
        AttachmentLabel.WARRANTY -> R.string.label_warranty
        AttachmentLabel.OTHER -> R.string.label_other
    }

private val AttachmentLabel.chip: Int
    get() = when (this) {
        AttachmentLabel.ITEM -> R.string.label_chip_item
        AttachmentLabel.PART -> R.string.label_chip_part
        AttachmentLabel.INSTRUCTIONS -> R.string.label_chip_instructions
        AttachmentLabel.PRODUCT_PAGE -> R.string.label_chip_product_page
        AttachmentLabel.WARRANTY -> R.string.label_chip_warranty
        AttachmentLabel.OTHER -> R.string.label_chip_other
    }

@Composable
fun AttachmentEditor(viewModel: AttachmentFormViewModel<*>, labels: List<AttachmentLabel> = listOf(AttachmentLabel.OTHER)) {
    val context = LocalContext.current
    var label by rememberSaveable { mutableStateOf(labels.first()) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        viewModel.attachments.forEach { attachment ->
            AttachmentRow(
                attachment,
                viewModel.attachmentStore,
                caption = if (labels.size > 1) stringResource(attachment.label.title) else null,
                onClick = { viewAttachment(context, viewModel.attachmentStore, attachment) },
            ) {
                IconButton(onClick = { viewModel.remove(attachment) }) {
                    Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_remove_named, attachment.displayName))
                }
            }
        }
        if (viewModel.importing) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (labels.size > 1) LabelChips(labels, label) { label = it }
        AttachmentButtons(
            viewModel.attachmentStore,
            onFiles = { viewModel.addFiles(it, label) },
            onPhoto = { name, success -> viewModel.onPhotoResult(name, success, label) },
        )
    }
}

/**
 * A detail screen's attachments, added and removed in place rather than through the editor. With more than
 * one label, files are grouped under their labels and new files take the label chosen above the buttons.
 */
@Composable
fun DetailAttachments(
    viewModel: RecordDetailViewModel,
    attachments: List<Attachment>,
    emptyText: String,
    labels: List<AttachmentLabel> = listOf(AttachmentLabel.OTHER),
) {
    val context = LocalContext.current
    var pendingRemoval by remember { mutableStateOf<Attachment?>(null) }
    var relabeling by remember { mutableStateOf<Attachment?>(null) }
    var label by rememberSaveable { mutableStateOf(labels.first()) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (attachments.isEmpty()) {
            Text(emptyText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val groups = if (labels.size > 1) labels.map { it to attachments.filter { a -> a.label == it } } else listOf(labels.first() to attachments)
        groups.filter { it.second.isNotEmpty() }.forEach { (groupLabel, group) ->
            if (labels.size > 1) {
                Text(
                    stringResource(groupLabel.title),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            group.forEach { attachment ->
                AttachmentRow(attachment, viewModel.attachmentStore, onClick = { viewAttachment(context, viewModel.attachmentStore, attachment) }) {
                    if (labels.size > 1) {
                        Box {
                            IconButton(onClick = { relabeling = attachment }) {
                                Icon(Icons.AutoMirrored.Outlined.Label, contentDescription = stringResource(R.string.action_change_label_named, attachment.displayName))
                            }
                            DropdownMenu(expanded = relabeling == attachment, onDismissRequest = { relabeling = null }) {
                                labels.forEach { option ->
                                    DropdownMenuItem(
                                        text = { Text(stringResource(option.title)) },
                                        onClick = {
                                            relabeling = null
                                            viewModel.relabel(attachment, option)
                                        },
                                    )
                                }
                            }
                        }
                    }
                    IconButton(onClick = { shareAttachment(context, viewModel.attachmentStore, attachment) }) {
                        Icon(Icons.Outlined.Share, contentDescription = stringResource(R.string.action_share_named, attachment.displayName))
                    }
                    IconButton(onClick = { pendingRemoval = attachment }) {
                        Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_remove_named, attachment.displayName))
                    }
                }
            }
        }
        if (viewModel.importing) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (labels.size > 1) LabelChips(labels, label) { label = it }
        AttachmentButtons(
            viewModel.attachmentStore,
            onFiles = { viewModel.addFiles(it, label) },
            onPhoto = { name, success -> viewModel.onPhotoResult(name, success, label) },
        )
    }
    val message = viewModel.message
    LaunchedEffect(message) {
        if (message != null) {
            Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
            viewModel.message = null
        }
    }
    pendingRemoval?.let { attachment ->
        ConfirmDialog(
            title = stringResource(R.string.remove_attachment_title, attachment.displayName),
            text = stringResource(R.string.remove_attachment_body),
            confirmLabel = stringResource(R.string.action_remove),
            onConfirm = { viewModel.remove(attachment) },
            onDismiss = { pendingRemoval = null },
        )
    }
}

@Composable
private fun LabelChips(labels: List<AttachmentLabel>, selected: AttachmentLabel, onSelect: (AttachmentLabel) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            stringResource(R.string.label_add_as),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        FilterChips(labels, selected, label = { stringResource(it.chip) }, onSelect = onSelect)
    }
}

@Composable
private fun AttachmentButtons(
    store: AttachmentStore,
    onFiles: (List<Uri>) -> Unit,
    onPhoto: (fileName: String, success: Boolean) -> Unit,
) {
    val context = LocalContext.current
    val hasCamera = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    var pendingPhoto by rememberSaveable { mutableStateOf<String?>(null) }

    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments(), onFiles)
    val takePhoto = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        pendingPhoto?.let { onPhoto(it, success) }
        pendingPhoto = null
    }

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(onClick = { pickFiles.launch(arrayOf("*/*")) }, modifier = Modifier.weight(1f)) {
            Icon(Icons.Outlined.AttachFile, contentDescription = null)
            Text(stringResource(R.string.action_add_file), modifier = Modifier.padding(start = 8.dp))
        }
        if (hasCamera) {
            OutlinedButton(
                onClick = {
                    val file = store.newPhotoFile()
                    pendingPhoto = file.name
                    try {
                        takePhoto.launch(store.uriFor(file.name))
                    } catch (_: ActivityNotFoundException) {
                        file.delete()
                        pendingPhoto = null
                        Toast.makeText(context, R.string.error_no_camera_app, Toast.LENGTH_SHORT).show()
                    }
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Outlined.PhotoCamera, contentDescription = null)
                Text(stringResource(R.string.action_take_photo), modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

fun viewAttachment(context: Context, store: AttachmentStore, attachment: Attachment) {
    val uri = store.uriFor(attachment)
    val intent = Intent(Intent.ACTION_VIEW)
        .setDataAndType(uri, attachment.mimeType)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, R.string.error_no_viewer, Toast.LENGTH_SHORT).show()
    }
}

fun shareAttachment(context: Context, store: AttachmentStore, attachment: Attachment) {
    val uri = store.uriFor(attachment)
    val intent = Intent(Intent.ACTION_SEND)
        .setType(attachment.mimeType)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.clipData = ClipData.newUri(context.contentResolver, attachment.displayName, uri)
    context.startActivity(Intent.createChooser(intent, null))
}

/** Opens a web link in the person's browser; the app itself never goes online. */
fun openLink(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, R.string.error_no_browser, Toast.LENGTH_SHORT).show()
    }
}

fun shareText(context: Context, subject: String, text: String) {
    val intent = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_SUBJECT, subject)
        .putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(intent, null))
}
