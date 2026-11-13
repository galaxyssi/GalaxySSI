package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareDocumentDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun source() = HealthCareDocumentRef(id(), "a".repeat(64), 1234, "application/pdf", 2, 3)
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareEncounter) -> Unit) {
        val names = HealthOverviewDatabases(id())
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { store ->
                val visit = store.saveEncounter(issue.id, issue.revision, id(), null, HealthCareEncounterDraft("Synthetic visit"),
                    id(), System.currentTimeMillis()).encounter
                test(names, store, visit)
            }
        } finally { context.deleteDatabase(names.care); clearHealthOverviewFixture(context, names) }
    }
    private fun save(store: HealthCareStore, visit: HealthCareEncounter, source: HealthCareDocumentRef = source(), operation: String = id()) =
        store.linkEncounterDocument(visit.concernId, store.concern(visit.concernId)!!.revision, visit.id, visit.revision,
            source, operation, System.currentTimeMillis())
    @Test fun exactReplayAndDuplicateSourceDoNotDuplicateWritesOrCreatePlans(): Unit = fixture { names, store, visit ->
        val issue = store.concern(visit.concernId)!!
        val saved = save(store, visit)
        val after = store.concern(visit.concernId)!!
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(saved, reopened.linkEncounterDocument(visit.concernId, saved.expectedConcern, visit.id, visit.revision,
                saved.source, saved.id, System.currentTimeMillis()))
            assertEquals(saved, save(reopened, visit, saved.source))
            assertEquals(after, reopened.concern(visit.concernId))
            assertEquals(listOf(saved), reopened.encounterDocuments(visit.concernId, visit.id).items)
            assertEquals(issue.actions, after.actions); assertEquals(issue.target, after.target); assertEquals(issue.stage, after.stage)
            assertTrue(reopened.reminders(visit.concernId).isEmpty()); assertTrue(reopened.researchJobs(visit.concernId).isEmpty())
        }
    }
    @Test fun staleRevisionForeignParentAndChangedReplayAreRejected(): Unit = fixture { _, store, visit ->
        val saved = save(store, visit)
        assertThrows(HealthCareConflict::class.java) { store.linkEncounterDocument(visit.concernId, saved.expectedConcern, visit.id,
            visit.revision, source(), id(), System.currentTimeMillis()) }
        assertThrows(HealthCareConflict::class.java) { store.linkEncounterDocument(visit.concernId, saved.expectedConcern, visit.id,
            visit.revision, saved.source.copy(page = 1), saved.id, System.currentTimeMillis()) }
        assertThrows(HealthCareConflict::class.java) { store.linkEncounterDocument(id(), saved.revision, visit.id,
            visit.revision, saved.source, id(), System.currentTimeMillis()) }
        assertThrows(HealthCareConflict::class.java) { save(store, visit.copy(revision = visit.revision + 1)) }
        assertEquals(1, store.encounterDocuments(visit.concernId, visit.id).items.size)
    }
    @Test fun pagesAreBoundedUniqueAndOrderedByRevision(): Unit = fixture { _, store, visit ->
        val all = (1..65).map { save(store, visit) }
        val first = store.encounterDocuments(visit.concernId, visit.id)
        val second = store.encounterDocuments(visit.concernId, visit.id, first.next!!)
        val third = store.encounterDocuments(visit.concernId, visit.id, second.next!!)
        assertEquals(30, first.items.size); assertEquals(all.reversed(), first.items + second.items + third.items); assertNull(third.next)
        assertTrue(store.encounterDocuments(visit.concernId, id()).items.isEmpty())
        listOf(0, 31, 1000).forEach { count -> assertThrows(IllegalArgumentException::class.java) {
            store.encounterDocuments(visit.concernId, visit.id, limit = count)
        } }
    }
    @Test fun hashAndPageAreEncryptedAndIndexTamperingFailsClosed(): Unit = fixture { names, store, visit ->
        val saved = save(store, visit)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT source_key,payload FROM encounter_documents", null).use { row ->
                assertTrue(row.moveToFirst())
                assertFalse(row.getString(0).contains(saved.source.sha256))
                val raw = row.getBlob(1).toString(Charsets.ISO_8859_1)
                assertFalse(raw.contains(saved.source.originalId)); assertFalse(raw.contains(saved.source.sha256)); assertFalse(raw.contains("application/pdf"))
            }
            db.update("encounter_documents", ContentValues().apply { put("encounter_id", id()) }, "id=?", arrayOf(saved.id))
        }
        assertThrows(IllegalStateException::class.java) { store.encounterDocument(saved.id) }
    }
    @Test fun abortAndIgnoredInsertBothRollBackTheConcernAndHistory(): Unit = fixture { names, store, visit ->
        val issue = store.concern(visit.concernId)!!; val history = store.history(visit.concernId)
        listOf("RAISE(ABORT, 'synthetic failure')", "RAISE(IGNORE)").forEach { failure ->
            context.openOrCreateDatabase(names.care, 0, null).use {
                it.execSQL("CREATE TRIGGER fail_document BEFORE INSERT ON encounter_documents BEGIN SELECT $failure; END")
            }
            try {
                assertTrue(runCatching { save(store, visit) }.isFailure)
                assertEquals(issue, store.concern(visit.concernId)); assertEquals(history, store.history(visit.concernId))
                assertTrue(store.encounterDocuments(visit.concernId, visit.id).items.isEmpty())
            } finally { context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL("DROP TRIGGER fail_document") } }
        }
    }
    @Test fun unlinkCannotBeUndoneByReplayingTheOldConfirmation(): Unit = fixture { _, store, visit ->
        val saved = save(store, visit)
        store.unlinkEncounterDocument(visit.concernId, saved.revision, saved.id, saved.revision, System.currentTimeMillis())
        assertNull(store.encounterDocument(saved.id)); assertNotNull(store.encounter(visit.id))
        assertThrows(HealthCareConflict::class.java) { store.linkEncounterDocument(visit.concernId, saved.expectedConcern, visit.id,
            visit.revision, saved.source, saved.id, System.currentTimeMillis()) }
    }
    @Test fun visitAndConcernDeletionPurgeSourcesAndOldCallbacksCannotRestoreThem(): Unit = fixture { _, store, visit ->
        val saved = save(store, visit)
        store.deleteEncounter(visit.concernId, saved.revision, visit.id, visit.revision, System.currentTimeMillis())
        assertNull(store.encounterDocument(saved.id))
        assertThrows(HealthCareConflict::class.java) { save(store, visit, saved.source, saved.id) }
        val issue = store.concern(visit.concernId)!!
        val other = store.saveEncounter(issue.id, issue.revision, id(), null, HealthCareEncounterDraft("Other synthetic visit"), id(), System.currentTimeMillis()).encounter
        val second = save(store, other)
        store.delete(issue.id, second.revision)
        assertNull(store.encounterDocument(second.id))
    }
    @Test fun schemaTwelveMigrationPreservesVisitsAndStartsWithNoInventedSources(): Unit = fixture { names, store, visit ->
        val issue = store.concern(visit.concernId)!!
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use { removeHealthInstructionTestTables(it); it.execSQL("DROP TABLE encounter_documents"); it.version = 12 }
        HealthCareStore(context, names.care).use {
            assertEquals(visit, it.encounter(visit.id)); assertEquals(issue, it.concern(issue.id))
            assertTrue(it.encounterDocuments(issue.id, visit.id).items.isEmpty()); save(it, visit)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(19, it.version) }
    }
}
