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
                    Formats.fileSize(attachment.sizeBytes),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            actions()
        }
    }
}

@Composable
fun AttachmentEditor(viewModel: AttachmentFormViewModel<*>) {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        viewModel.attachments.forEach { attachment ->
            AttachmentRow(attachment, viewModel.attachmentStore, onClick = { viewAttachment(context, viewModel.attachmentStore, attachment) }) {
                IconButton(onClick = { viewModel.remove(attachment) }) {
                    Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_remove_named, attachment.displayName))
                }
            }
        }
        if (viewModel.importing) LinearProgressIndicator(Modifier.fillMaxWidth())
        AttachmentButtons(viewModel.attachmentStore, onFiles = viewModel::addFiles, onPhoto = viewModel::onPhotoResult)
    }
}

/** A detail screen's attachments, added and removed in place rather than through the editor. */
@Composable
fun DetailAttachments(viewModel: RecordDetailViewModel, attachments: List<Attachment>, emptyText: String) {
    val context = LocalContext.current
    var pendingRemoval by remember { mutableStateOf<Attachment?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (attachments.isEmpty()) {
            Text(emptyText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        attachments.forEach { attachment ->
            AttachmentRow(attachment, viewModel.attachmentStore, onClick = { viewAttachment(context, viewModel.attachmentStore, attachment) }) {
                IconButton(onClick = { shareAttachment(context, viewModel.attachmentStore, attachment) }) {
                    Icon(Icons.Outlined.Share, contentDescription = stringResource(R.string.action_share_named, attachment.displayName))
                }
                IconButton(onClick = { pendingRemoval = attachment }) {
                    Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_remove_named, attachment.displayName))
                }
            }
        }
        if (viewModel.importing) LinearProgressIndicator(Modifier.fillMaxWidth())
        AttachmentButtons(viewModel.attachmentStore, onFiles = viewModel::addFiles, onPhoto = viewModel::onPhotoResult)
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

fun shareText(context: Context, subject: String, text: String) {
    val intent = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_SUBJECT, subject)
        .putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(intent, null))
}
