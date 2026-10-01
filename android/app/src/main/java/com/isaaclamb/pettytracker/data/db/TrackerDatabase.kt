package com.isaaclamb.pettytracker.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.SentReminder
import com.isaaclamb.pettytracker.data.Subscription

@Database(
    entities = [Product::class, Subscription::class, Document::class, Attachment::class, SentReminder::class],
    version = 1,
)
@TypeConverters(Converters::class)
abstract class TrackerDatabase : RoomDatabase() {
    abstract fun dao(): TrackerDao

    companion object {
        fun create(context: Context): TrackerDatabase =
            Room.databaseBuilder(context, TrackerDatabase::class.java, "tracker.db").build()
    }
}
