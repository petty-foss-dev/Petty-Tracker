package com.isaaclamb.pettytracker.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.RecordLink
import com.isaaclamb.pettytracker.data.SentReminder
import com.isaaclamb.pettytracker.data.Subscription

@Database(
    entities = [Product::class, Subscription::class, Document::class, Attachment::class, SentReminder::class, RecordLink::class],
    version = 2,
)
@TypeConverters(Converters::class)
abstract class TrackerDatabase : RoomDatabase() {
    abstract fun dao(): TrackerDao

    companion object {
        fun create(context: Context): TrackerDatabase =
            Room.databaseBuilder(context, TrackerDatabase::class.java, "tracker.db")
                .addMigrations(MIGRATION_1_2)
                .build()

        /** Product pages, file labels and links between records. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE products ADD COLUMN productUrl TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE attachments ADD COLUMN label TEXT NOT NULL DEFAULT 'OTHER'")
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS record_links (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "fromType TEXT NOT NULL, fromId INTEGER NOT NULL, toType TEXT NOT NULL, toId INTEGER NOT NULL, " +
                        "note TEXT NOT NULL)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_record_links_fromType_fromId ON record_links (fromType, fromId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_record_links_toType_toId ON record_links (toType, toId)")
            }
        }
    }
}
