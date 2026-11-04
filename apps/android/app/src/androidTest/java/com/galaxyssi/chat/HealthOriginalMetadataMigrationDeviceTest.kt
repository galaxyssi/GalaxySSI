package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class HealthOriginalMetadataMigrationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()

    private fun fixture(run: (HealthOverviewDatabases, File) -> Unit) {
        val names = HealthOverviewDatabases(id())
        val exports = File(context.cacheDir, "health-shared-export-${names.fixture}")
        try { run(names, exports) } finally {
            clearHealthOverviewFixture(context, names)
            exports.deleteRecursively()
        }
    }

    private fun legacy(names: HealthOverviewDatabases) = HealthOriginalStore(context, names.originals, names.originalRoot(context))
    private fun shared(names: HealthOverviewDatabases, records: HealthRecordStore) =
        HealthOriginalStore(context, names.originals, names.originalRoot(context), records)

    private fun SQLiteDatabase.rows(table: String) = rawQuery("SELECT COUNT(*) FROM $table", null).use {
        check(it.moveToFirst())
        it.getInt(0)
    }

    private fun record(store: HealthRecordStore, original: HealthOriginal? = null): HealthObservation {
        val evidence = original?.let {
            HealthEvidence(it.id, id(), "migration-test", it.sha256, 1, "raw fixture", confirmed = true)
        }
        val result = store.save(HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to "7"), "h",
            System.currentTimeMillis() - 60_000, evidence = evidence))
        return (result as HealthSaveResult.Saved).record
    }

    @Test fun schemaSixUpgradeKeepsLinkedDataAndEncryptedArchiveAndDoesNotRepeat() = fixture { names, exports ->
        val originalBytes = ByteArray(90_000) { (it % 241).toByte() }
        val job = HealthImportJob(id(), "content://fixture/health", 1L)
        val page = HealthOcrPage(1, 200, 200, listOf(HealthOcrLine("fixture text")))
        val (original, export) = legacy(names).use { old ->
            old.createJob(job)
            val value = old.importOriginal(job.id, originalBytes.inputStream(), "source.pdf", "application/pdf", "file")
            old.savePage(job.id, page)
            val library = HealthOriginalLibraryStore(context, old, exports)
            val selection = library.createSelection()
            library.select(selection.id, listOf(value.id), true)
            library.prepare(selection.id)
            library.queue(selection.id)
            assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(old, library, selection.id))
            value to requireNotNull(library.session(selection.id))
        }
        val measurement = HealthRecordStore(context, names.records).use {
            val measurement = record(it, original)
            val db = it.tableDatabase
            db.beginTransaction()
            try {
                listOf("health_restore_batches", "health_original_metadata_migration", "library_export_items", "library_exports", "capture_pages",
                    "capture_batches", "pages", "jobs", "imports", "originals").forEach { table ->
                    db.execSQL("DROP TABLE $table")
                }
                db.version = 6
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
            measurement
        }
        HealthRecordStore(context, names.records).use { records ->
            assertEquals(HealthRecordStore.SCHEMA_VERSION, records.tableDatabase.version)
            assertEquals(measurement, records.record(measurement.id))
            shared(names, records).use { originals ->
                assertSame(records.tableDatabase, originals.libraryDatabase)
                assertEquals(original, originals.originalForJob(job.id))
                assertEquals(page, originals.page(job.id, 1))
                assertEquals(1, originals.job(job.id)?.nextPage)
                assertEquals(listOf(measurement), records.page(originalId = original.id).records)
                assertArrayEquals(originalBytes, originals.input(original).use { it.readBytes() })
                val library = HealthOriginalLibraryStore(context, originals, exports)
                assertEquals(export, library.session(export.id))
                val archive = ByteArrayOutputStream()
                assertEquals(export.archiveBytes, HealthOriginalArchive.save(library, export, archive))
                assertTrue(archive.size() > 0)
                val newId = id()
                assertEquals(original, originals.importOriginal(newId, originalBytes.inputStream(), "duplicate", "image/jpeg", "file"))
                assertEquals(original, originals.originalForJob(newId))
                assertEquals(1, records.tableDatabase.rows("originals"))
                assertEquals(2, records.tableDatabase.rows("imports"))
                legacy(names).use { old ->
                    assertNull(old.originalForJob(newId))
                    assertEquals(original, old.originalForJob(job.id))
                }
            }
        }
        HealthRecordStore(context, names.records).use { records -> shared(names, records).use {
            assertEquals(1L, it.originalCount())
            assertEquals(2, it.libraryDatabase.rows("imports"))
            assertEquals(1, it.libraryDatabase.rows("health_original_metadata_migration"))
        } }
    }

    @Test fun failureAfterCopyingOriginalsDoesNotCommitHalfMigration() = fixture { names, _ ->
        val job = HealthImportJob(id(), "content://fixture/failure", 1L)
        val bytes = byteArrayOf(31, 11, 51)
        val original = legacy(names).use {
            it.createJob(job)
            it.importOriginal(job.id, bytes.inputStream(), "fixture", "image/png", "file")
        }
        HealthRecordStore(context, names.records).use { records ->
            val db = records.tableDatabase
            db.execSQL("CREATE TRIGGER fail_migration BEFORE INSERT ON jobs BEGIN SELECT RAISE(ABORT, 'injected migration failure'); END")
            assertTrue(runCatching { shared(names, records).use { it.originalCount() } }.isFailure)
            assertEquals(0, db.rows("originals"))
            assertEquals(0, db.rows("imports"))
            assertEquals(0, db.rows("health_original_metadata_migration"))
            db.execSQL("DROP TRIGGER fail_migration")
            shared(names, records).use { migrated ->
                assertEquals(original, migrated.originalForJob(job.id))
                assertArrayEquals(bytes, migrated.input(original).use { it.readBytes() })
            }
        }
    }

    @Test fun separateReadersRaceWithoutDuplicateCopyOrLegacyWrites() = fixture { names, _ ->
        legacy(names).use { originals ->
            repeat(34) { originals.importOriginal(id(), byteArrayOf(it.toByte(), 1).inputStream(), "fixture", "image/jpeg", "file") }
        }
        HealthRecordStore(context, names.records).use { assertEquals(0, it.tableDatabase.rows("originals")) }
        val workers = Executors.newFixedThreadPool(2)
        val start = CountDownLatch(1)
        try {
            val reads = List(2) {
                workers.submit(Callable {
                    check(start.await(5, TimeUnit.SECONDS))
                    HealthRecordStore(context, names.records).use { records -> shared(names, records).use { it.originalCount() } }
                })
            }
            start.countDown()
            reads.forEach { assertEquals(34L, it.get(25, TimeUnit.SECONDS)) }
        } finally {
            workers.shutdownNow()
            assertTrue(workers.awaitTermination(20, TimeUnit.SECONDS))
        }
        legacy(names).use { assertEquals(34L, it.originalCount()) }
    }

    @Test fun observationAndOriginalMetadataRollBackInOneTransaction() = fixture { names, _ ->
        val original = legacy(names).use { it.importOriginal(id(), byteArrayOf(9).inputStream(), "fixture", "image/jpeg", "file") }
        HealthRecordStore(context, names.records).use { records -> shared(names, records).use { originals ->
            val database = originals.libraryDatabase
            assertFalse(database.inTransaction())
            database.beginTransactionNonExclusive()
            try {
                val measurement = record(records, original)
                assertNotNull(records.record(measurement.id))
                assertEquals(1, database.delete("imports", "original_id=?", arrayOf(original.id)))
                assertNull(originals.originalForJob(original.id))
            } finally { database.endTransaction(); records.publishCommittedChanges() }
            assertEquals(0L, records.count())
            assertEquals(original, originals.originalForJob(original.id))
        } }
    }

    @Test fun freshSharedStoreDoesNotCreateALegacyDatabase() = fixture { names, _ ->
        HealthRecordStore(context, names.records).use { records -> shared(names, records).use { originals ->
            assertEquals(0L, originals.originalCount())
            assertFalse(context.getDatabasePath(names.originals).exists())
            val row = originals.importOriginal(id(), byteArrayOf(123).inputStream(), "shared-only", "image/jpeg", "camera")
            assertEquals(row, originals.original(row.id))
            assertFalse(context.getDatabasePath(names.originals).exists())
        } }
    }

    @Test fun largeLegacyEncryptedPageSurvivesCursorWindowLimits() = fixture { names, _ ->
        val job = HealthImportJob(id(), "content://fixture/large-metadata", 1)
        val bytes = ByteArray(3 * 1024 * 1024 + 19) { (it % 251).toByte() }
        legacy(names).use { old ->
            old.createJob(job)
            old.libraryDatabase.execSQL("INSERT INTO pages(job_id,page_number,payload) VALUES(?,?,?)", arrayOf(job.id, 1, bytes))
        }
        HealthRecordStore(context, names.records).use { records -> shared(names, records).use { originals ->
            val database = originals.libraryDatabase
            val output = ByteArrayOutputStream()
            for (offset in bytes.indices step 256 * 1024) {
                database.rawQuery("SELECT substr(payload,?,?) FROM pages WHERE job_id=?", arrayOf(
                    (offset + 1).toString(), (256 * 1024).toString(), job.id
                )).use { rows -> assertTrue(rows.moveToFirst()); output.write(rows.getBlob(0)) }
            }
            assertArrayEquals(bytes, output.toByteArray())
        } }
    }
}
