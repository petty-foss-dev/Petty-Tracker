package com.enve.keep

import android.app.Application
import com.enve.keep.reminders.ReminderNotifications
import com.enve.keep.reminders.ReminderScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class KeepApplication : Application() {
    lateinit var container: AppContainer
        private set

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        ReminderNotifications.createChannel(this)
        ReminderScheduler.schedule(this)
        scope.launch {
            container.attachmentStore.deleteOrphans(container.repository.referencedFileNames())
        }
    }
}
