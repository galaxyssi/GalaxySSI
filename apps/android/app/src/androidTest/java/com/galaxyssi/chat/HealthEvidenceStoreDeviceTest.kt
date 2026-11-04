package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthEvidenceStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (String, HealthRecordStore) -> Unit) {
        val name = "health-evidence-test-${id()}.db"
        try { HealthRecordStore(context, name).use { test(name, it) } }
        finally { context.deleteDatabase(name) }
    }
    private fun draft(original: String = id(), candidate: String = "glucose-0") = HealthDraft(HealthMetric.GLUCOSE,
        mapOf("glucose" to "5.6"), "mmol/L", 1_790_000_000_000L,
        evidence = HealthEvidence(original, id(), candidate, "a".repeat(64), 1, "Glucose 5.6 mmol/L", confirmed = true))

    @Test fun repeatedSourceCandidateDoesNotDuplicateWhenFileIsRecognizedAgain() = fixture { _, store ->
        val draft = draft(); val saved = (store.save(draft) as HealthSaveResult.Saved).record
        val repeated = draft.copy(measuredAt = draft.measuredAt - 1000, evidence = draft.evidence!!.copy(jobId = id()))
        assertEquals(HealthSaveResult.Duplicate(saved.id), store.save(repeated))
        assertEquals(saved, store.recordForEvidence(repeated)); assertEquals(1L, store.count())
        assertEquals(saved, store.page(originalId = draft.evidence.originalId).records.single())
    }
    @Test fun sourceDraftsStaySeparateFromManualDraftsAndFromEachOther() = fixture { _, store ->
        val first = draft().copy(evidence = draft().evidence!!.copy(confirmed = false))
        val second = first.copy(evidence = first.evidence!!.copy(candidateId = "glucose-1"))
        val manual = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6"))
        listOf(first, second, manual).forEach(store::saveDraft)
        listOf(first, second, manual).forEach { assertEquals(it, store.draft(HealthRecordStore.draftKey(it))) }
        assertTrue(runCatching { store.save(first) }.isFailure); assertEquals(0L, store.count())
    }
    @Test fun sourceIndexMetadataCannotRedirectAnAuthenticatedMeasurement() = fixture { name, store ->
        val a = draft(); val saved = (store.save(a) as HealthSaveResult.Saved).record
        val other = id()
        context.openOrCreateDatabase(name, 0, null).use { db ->
            db.update("observations", ContentValues().apply { put("original_id", other) }, "id=?", arrayOf(saved.id))
        }
        assertTrue(runCatching { store.page(originalId = other) }.isFailure)
        assertEquals(a.evidence!!.originalId, store.record(saved.id)!!.draft.evidence!!.originalId)
    }
    @Test fun associatedMeasurementsPageByTimeAndIdentityRatherThanLoadingWholeSource() = fixture { _, store ->
        val source = id()
        repeat(65) { index ->
            val entry = draft(source, "glucose-$index").copy(measuredAt = 1_790_000_000_000L - index)
            assertTrue(store.save(entry) is HealthSaveResult.Saved)
        }
        var cursor: HealthPageCursor? = null; val records = mutableListOf<HealthObservation>()
        do { val page = store.page(after = cursor, originalId = source); assertTrue(page.records.size <= 30)
            records += page.records; cursor = page.next
        } while (cursor != null)
        assertEquals(65, records.size); assertEquals(65, records.map { it.id }.distinct().size)
        assertTrue(store.page(originalId = id()).records.isEmpty())
    }
    @Test fun versionOneUpgradePreservesEncryptedRecordsDraftsAndRevisions() {
        val name = "health-migration-test-${id()}.db"
        val manual = HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "60"), "kg", 1_790_000_000_000L)
        val record = HealthObservationPolicy.observation(manual)
        val encoded = AgentStorageCipher.encryptBinary(record.json().toString().toByteArray(), "$name|health|${record.id}|1".toByteArray())
        val key = HealthRecordStore.draftKey(manual)
        val draftBytes = AgentStorageCipher.encryptBinary(manual.json().toString().toByteArray(), "$name|health|$key|1".toByteArray())
        try {
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.execSQL("CREATE TABLE observations(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,metric TEXT NOT NULL,measured_at INTEGER NOT NULL,payload BLOB NOT NULL,dedupe TEXT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0)")
                db.execSQL("CREATE UNIQUE INDEX observation_dedupe ON observations(dedupe) WHERE deleted=0")
                db.execSQL("CREATE INDEX observation_page ON observations(deleted,measured_at DESC,id DESC)")
                db.execSQL("CREATE INDEX observation_metric_page ON observations(metric,deleted,measured_at DESC,id DESC)")
                db.execSQL("CREATE TABLE revisions(id TEXT NOT NULL REFERENCES observations(id),revision INTEGER NOT NULL,payload BLOB NOT NULL,changed_at INTEGER NOT NULL,deleted INTEGER NOT NULL,PRIMARY KEY(id,revision))")
                db.execSQL("CREATE TABLE drafts(draft_key TEXT PRIMARY KEY,payload BLOB NOT NULL)")
                db.insertOrThrow("observations", null, ContentValues().apply {
                    put("id", record.id); put("revision", 1); put("metric", manual.metric.name); put("measured_at", manual.measuredAt)
                    put("payload", encoded); put("dedupe", AgentMemoryIndexKey.token("$name|health-duplicate-v1|${HealthObservationPolicy.duplicateKey(record)}")); put("deleted", 0)
                })
                db.insertOrThrow("revisions", null, ContentValues().apply { put("id", record.id); put("revision", 1); put("payload", encoded); put("changed_at", record.receivedAt); put("deleted", 0) })
                db.insertOrThrow("drafts", null, ContentValues().apply { put("draft_key", key); put("payload", draftBytes) })
                db.version = 1
            }
            HealthRecordStore(context, name).use { store ->
                assertEquals(record, store.record(record.id)); assertEquals(manual, store.draft(key))
                assertEquals(listOf(record), store.history(record.id)); assertEquals(1L, store.count())
                assertTrue(store.save(draft()) is HealthSaveResult.Saved); assertEquals(2L, store.count())
            }
            context.openOrCreateDatabase(name, 0, null).use { assertEquals(HealthRecordStore.SCHEMA_VERSION, it.version) }
        } finally { encoded.fill(0); draftBytes.fill(0); context.deleteDatabase(name) }
    }
}
