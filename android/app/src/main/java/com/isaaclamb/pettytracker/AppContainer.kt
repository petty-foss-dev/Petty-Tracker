package com.isaaclamb.pettytracker

import android.content.Context
import com.isaaclamb.pettytracker.data.AttachmentStore
import com.isaaclamb.pettytracker.data.TrackerRepository
import com.isaaclamb.pettytracker.data.SettingsRepository
import com.isaaclamb.pettytracker.data.backup.BackupManager
import com.isaaclamb.pettytracker.data.db.TrackerDatabase

class AppContainer(context: Context) {
    val database = TrackerDatabase.create(context)
    val attachmentStore = AttachmentStore(context)
    val repository = TrackerRepository(database, attachmentStore)
    val settingsRepository = SettingsRepository(context)
    val backupManager = BackupManager(context, database, attachmentStore, settingsRepository)
}
