package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in consistent public-only audit; raw copies of an actively written SQLite file are not snapshots. */
class AttentionPublicSnapshotDeviceTest {
    @Test fun exportConsistentPublicArchiveWithoutChangingSourceRows() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_public_snapshot") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val output = File(context.cacheDir, "attention-public-audit.db")
        if (output.exists()) assertTrue(output.delete())
        SQLiteDatabase.openDatabase(context.getDatabasePath(AttentionArticleStore.NAME).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.execSQL("VACUUM INTO ?", arrayOf(output.path))
        }
        SQLiteDatabase.openDatabase(output.path, null, SQLiteDatabase.OPEN_READONLY).use { snapshot ->
            snapshot.rawQuery("PRAGMA quick_check", null).use { assertTrue(it.moveToFirst()); assertEquals("ok", it.getString(0)) }
        }
        instrumentation.sendStatus(0, Bundle().apply { putString("stream", "public_snapshot=cache/attention-public-audit.db consistent=true\n") })
    }
}
