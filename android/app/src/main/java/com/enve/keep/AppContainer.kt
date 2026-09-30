package com.enve.keep

import android.content.Context
import com.enve.keep.data.AttachmentStore
import com.enve.keep.data.KeepRepository
import com.enve.keep.data.SettingsRepository
import com.enve.keep.data.backup.BackupManager
import com.enve.keep.data.db.KeepDatabase

class AppContainer(context: Context) {
    val database = KeepDatabase.create(context)
    val attachmentStore = AttachmentStore(context)
    val repository = KeepRepository(database, attachmentStore)
    val settingsRepository = SettingsRepository(context)
    val backupManager = BackupManager(context, database, attachmentStore, settingsRepository)
}
