package com.enve.keep.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.enve.keep.data.Attachment
import com.enve.keep.data.Document
import com.enve.keep.data.Product
import com.enve.keep.data.SentReminder
import com.enve.keep.data.Subscription

@Database(
    entities = [Product::class, Subscription::class, Document::class, Attachment::class, SentReminder::class],
    version = 1,
)
@TypeConverters(Converters::class)
abstract class KeepDatabase : RoomDatabase() {
    abstract fun dao(): KeepDao

    companion object {
        fun create(context: Context): KeepDatabase =
            Room.databaseBuilder(context, KeepDatabase::class.java, "keep.db").build()
    }
}
