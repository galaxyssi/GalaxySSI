package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthRecordStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun pressure() = HealthDraft(values = mapOf("systolic" to "124", "diastolic" to "82"), measuredAt = 1_790_000_000_000L)
    private fun fixture(test: (String, HealthRecordStore) -> Unit) {
        val name = "health-test-${UUID.randomUUID()}.db"
        try { HealthRecordStore(context, name).use { test(name, it) } }
        finally { context.deleteDatabase(name) }
    }
    @Test fun confirmedMeasurementSurvivesClosingAndReopeningEncryptedDatabase() = fixture { name, store ->
        val record = (store.save(pressure()) as HealthSaveResult.Saved).record
        assertEquals(1L, store.count())
        HealthRecordStore(context, name).use { reopened -> assertEquals(record, reopened.record(record.id)) }
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM observations", null).use {
                assertTrue(it.moveToFirst())
                val envelope = it.getBlob(0)
                assertEquals(1.toByte(), envelope[0])
                assertFalse(String(envelope, Charsets.ISO_8859_1).contains("systolic"))
                assertFalse(String(envelope, Charsets.ISO_8859_1).contains("diastolic"))
            }
            db.rawQuery("SELECT dedupe FROM observations", null).use {
                it.moveToFirst(); assertNotEquals(HealthObservationPolicy.duplicateKey(record), it.getString(0))
            }
        }
    }
    @Test fun duplicateSaveCannotCreateAnotherMeasurement() = fixture { _, store ->
        val first = (store.save(pressure()) as HealthSaveResult.Saved).record
        val duplicate = store.save(pressure().copy(values = mapOf("systolic" to "124.00", "diastolic" to "82.0")))
        assertEquals(HealthSaveResult.Duplicate(first.id), duplicate)
        assertEquals(1L, store.count())
    }
    @Test fun revisionChecksPreventLostUpdatesAndDeletionKeepsAuditHistory() = fixture { _, store ->
        val first = (store.save(pressure()) as HealthSaveResult.Saved).record
        val updated = (store.save(first.editable().copy(note = "verified")) as HealthSaveResult.Saved).record
        assertEquals(HealthSaveResult.Conflict, store.save(first.editable().copy(note = "stale")))
        assertFalse(store.delete(first.id, first.revision))
        assertEquals(2, store.history(first.id).size)
        assertEquals("", store.history(first.id).last().draft.note)
        assertTrue(store.delete(updated.id, updated.revision))
        assertNull(store.record(first.id))
        assertEquals(0L, store.count())
        assertTrue(store.page().records.isEmpty())
        assertEquals(3, store.history(first.id).size)
    }
    @Test fun timeAndIdentityCursorHasNoLossOrDuplicatesOnEqualTimestamps() = fixture { _, store ->
        repeat(125) { index ->
            assertTrue(store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "${index + 1}"),
                measuredAt = pressure().measuredAt)) is HealthSaveResult.Saved)
        }
        var cursor: HealthPageCursor? = null
        val ids = mutableListOf<String>()
        var pages = 0
        do {
            val page = store.page(cursor)
            assertTrue(page.records.size <= HealthRecordStore.PAGE_SIZE)
            ids += page.records.map { it.id }; cursor = page.next; pages++
        } while (cursor != null)
        assertEquals(125, ids.size)
        assertEquals(125, ids.distinct().size)
        assertEquals(5, pages)
        assertTrue(store.page(metric = HealthMetric.GLUCOSE).records.isEmpty())
        assertEquals(7, store.page(limit = 7).records.size)
    }
    @Test fun invalidDataDoesNotCreatePartialRows() = fixture { _, store ->
        assertTrue(runCatching { store.save(pressure().copy(values = mapOf("systolic" to "124"))) }.isFailure)
        assertEquals(0L, store.count())
    }
    @Test fun draftsRemainSeparateFromConfirmedRecordsAndAreRemovedAfterSaving() = fixture { name, store ->
        val draft = pressure()
        store.saveDraft(draft)
        HealthRecordStore(context, name).use { reopened -> assertEquals(draft, reopened.draft(HealthRecordStore.draftKey(draft))) }
        assertEquals(0L, store.count())
        assertTrue(store.save(draft) is HealthSaveResult.Saved)
        assertNull(store.draft(HealthRecordStore.draftKey(draft)))
    }
    @Test fun corruptCiphertextFailsExplicitlyWithoutResettingOrHidingTheDatabase() = fixture { name, store ->
        val record = (store.save(pressure()) as HealthSaveResult.Saved).record
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.update("observations", ContentValues().apply { put("payload", byteArrayOf(1, 2, 3)) }, "id=?", arrayOf(record.id))
        }
        assertTrue(runCatching { store.record(record.id) }.isFailure)
        assertEquals(1L, store.count())
    }
    @Test fun encryptedRowsCannotBeSwappedBetweenRecordIdentities() = fixture { name, store ->
        val a = (store.save(pressure()) as HealthSaveResult.Saved).record
        val b = (store.save(pressure().copy(measuredAt = pressure().measuredAt - 1)) as HealthSaveResult.Saved).record
        context.openOrCreateDatabase(name, 0, null).use { db ->
            val envelope = db.rawQuery("SELECT payload FROM observations WHERE id=?", arrayOf(a.id)).use { it.moveToFirst(); it.getBlob(0) }
            db.update("observations", ContentValues().apply { put("payload", envelope) }, "id=?", arrayOf(b.id))
        }
        assertEquals(a, store.record(a.id))
        assertTrue(runCatching { store.record(b.id) }.isFailure)
    }
    @Test fun changedIndexMetadataIsNotTrustedOverTheAuthenticatedMeasurement() = fixture { name, store ->
        val record = (store.save(pressure()) as HealthSaveResult.Saved).record
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.update("observations", ContentValues().apply { put("metric", HealthMetric.GLUCOSE.name) }, "id=?", arrayOf(record.id))
        }
        assertTrue(runCatching { store.page(metric = HealthMetric.GLUCOSE) }.isFailure)
        assertTrue(runCatching { store.record(record.id) }.isFailure)
    }
}
