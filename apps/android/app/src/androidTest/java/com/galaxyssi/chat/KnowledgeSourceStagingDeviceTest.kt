package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceStagingDeviceTest {
    @Test fun stagingIsEncryptedAndDuplicateHandlingDoesNotChangeBackupValidation() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(0).copy(content = "unique-private-source-body", source = "unique-private-source-url")
        val file = KnowledgeBackupStaging(f.context).use { stage ->
            assertEquals(1L, stage.acceptSource(item.source, sequenceOf(item, item.copy(content = "ignored"))))
            assertEquals(item, stage.incoming().single())
            stage.rememberPrevious(item); stage.finishPrevious()
            assertEquals(item, stage.item(item.id, true)); assertTrue(stage.changes().none())
            assertEquals(1, stage.changes(includeUnchanged = true).count())
            val disk = stage.file.readBytes().toString(Charsets.ISO_8859_1)
            assertFalse(disk.contains(item.source)); assertFalse(disk.contains(item.content)); assertFalse(disk.contains(item.id))
            stage.file
        }
        assertFalse(file.exists())
    }

    @Test fun largeStagedBodyAvoidsCursorWindowLimit() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(0).copy(content = "\u6b63\u6587\ud83d\ude80".repeat(250_000))
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(item.source, sequenceOf(item))
            stage.rememberPrevious(item); stage.finishPrevious()
            assertEquals(item, stage.incoming().single()); assertEquals(item, stage.previous().single())
            assertEquals(item, stage.item(item.id, false))
        }
    }

    @Test fun tamperedIncomingRecordCannotCommitAReplacement() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0))
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource("\u6765\u6e90", sequenceOf(f.item(1)))
            SQLiteDatabase.openOrCreateDatabase(stage.file, null).use { sql ->
                sql.execSQL("UPDATE records SET incoming='invalid'")
            }
            assertThrows(Exception::class.java) { KnowledgeSourceReplacement(f.db, stage, "\u6765\u6e90").commit() }
        }
        assertEquals(listOf(f.item(0)), f.items())
    }

    @Test fun invalidStableIdFailsBeforeCanonicalMutation() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0))
        assertThrows(IllegalArgumentException::class.java) {
            f.store.replaceSource("\u6765\u6e90", sequenceOf(f.item(1), f.item(2).copy(id = " ")))
        }
        assertEquals(listOf(f.item(0)), f.items()); assertEquals(0, f.visits)
    }
}
