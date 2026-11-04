package com.galaxyssi.chat

import androidx.core.content.FileProvider
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthTablePipelineDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(extension: String, text: String, test: (String, HealthOriginalStore, String, File) -> Unit) {
        fixture(extension, text.toByteArray(Charsets.UTF_8), test)
    }
    private fun fixture(extension: String, payload: ByteArray, test: (String, HealthOriginalStore, String, File) -> Unit) {
        val token = UUID.randomUUID().toString()
        val name = "health-table-pipeline-$token.db"; val records = "health-table-records-$token.db"
        val root = File(context.cacheDir, "health-table-archive-$token")
        val file = File(context.cacheDir, "health-capture/table-test-$token.$extension")
        try {
            file.parentFile!!.mkdirs(); file.writeBytes(payload)
            HealthOriginalStore(context, name, root).use { store ->
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                store.createJob(HealthImportJob(token, uri.toString(), System.currentTimeMillis()))
                test(records, store, token, file)
            }
        } finally { context.deleteDatabase(name); context.deleteDatabase(records); file.delete(); root.deleteRecursively() }
    }
    @Test fun csvRunsThroughTheActualFileQueueAndDoesNotWriteMeasurementsBeforeReview() = fixture("csv",
        "time,systolic,diastolic,unit\n2026-09-01T08:00:00Z,124,82,mmHg") { name, store, id, _ ->
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertEquals(HealthImportState.TABLE_REVIEW, store.job(id)?.state)
        HealthTableStore(context, name).use { tables ->
            assertEquals(1L, tables.batch(id)?.rows); assertEquals(HealthTableState.MAPPING, tables.batch(id)?.state)
        }
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertEquals(1, store.originals().size)
    }
    @Test fun jsonUsesLocalStructuredMappingRatherThanOcrOrAnyProvider() = fixture("json",
        """[{"time":"2026-09-01T08:00:00Z","glucose":5.4,"unit":"mmol/L"}]""") { name, store, id, _ ->
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertEquals(HealthImportState.TABLE_REVIEW, store.job(id)?.state)
        assertNull(store.page(id, 1))
        HealthTableStore(context, name).use { tables ->
            assertEquals("json", tables.batch(id)?.format); assertEquals("5.4", tables.page(id).single().row.cells["glucose"])
        }
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun cancelledQueuedImportsDoNotParseOrSaveAnything() = fixture("csv", "time,value\nnow,4") { name, store, id, _ ->
        store.updateJob(id) { it.copy(state = HealthImportState.CANCELLED) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertTrue(store.originals().isEmpty())
        HealthTableStore(context, name).use { assertNull(it.batch(id)) }
    }
    @Test fun sourceCanDisappearAfterTheEncryptedCopyAndMappingStillRemainsAvailable() = fixture("csv",
        "time,systolic,diastolic,unit\n2026-09-01T08:00:00Z,124,82,mmHg") { name, store, id, file ->
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertTrue(file.delete())
        store.updateJob(id) { it.copy(state = HealthImportState.QUEUED) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertEquals(HealthImportState.TABLE_REVIEW, store.job(id)?.state)
        HealthTableStore(context, name).use { assertEquals(1, it.page(id).size) }
    }
    @Test fun badCsvDoesNotBecomeAReviewablePartialImport() = fixture("csv", "time,time\nnow,other") { name, store, id, _ ->
        assertEquals(HealthImportOutcome.FAILED, HealthImportPipeline(context, name).run(store, id))
        assertEquals(HealthImportState.FAILED, store.job(id)?.state)
        assertEquals("table_headers", store.job(id)?.error)
        assertTrue(store.present(store.originalForJob(id)!!))
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun xlsxActualFileQueueStopsAtWorksheetSelectionWithoutSavingAnyMeasurements() = fixture("xlsx", HealthXlsxFixtures.workbook()) { name, store, id, _ ->
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertEquals(HealthImportState.TABLE_REVIEW, store.job(id)?.state)
        HealthTableStore(context, name).use { tables ->
            assertEquals(HealthTableState.SHEET_SELECTION, tables.batch(id)?.state)
            assertEquals("Home", tables.batch(id)?.sheets?.single()?.name)
            assertTrue(tables.page(id).isEmpty())
        }
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, name).run(store, id))
        assertEquals(1, store.originals().size)
    }
}
