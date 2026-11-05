package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.OperationCanceledException
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.CheckBox
import androidx.core.content.FileProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthRestoreDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val secret = "restore test secret"
    private fun id() = UUID.randomUUID().toString()

    private fun fixture(run: (HealthOverviewDatabases, HealthOverviewDatabases) -> Unit) {
        val source = HealthOverviewDatabases(id())
        val target = HealthOverviewDatabases(id())
        try { run(source, target) } finally {
            HealthBackupRepository(context, source).cleanup(Long.MAX_VALUE)
            File(context.cacheDir, "health-restore-stage-${target.fixture}").deleteRecursively()
            clearHealthOverviewFixture(context, source)
            clearHealthOverviewFixture(context, target)
        }
    }

    private fun draft(n: Int, note: String = "", id: String = "", original: HealthOriginal? = null): HealthDraft {
        val evidence = original?.let { HealthEvidence(it.id, UUID.randomUUID().toString(), "restore-$n", it.sha256, 1, "fixture source", confirmed = true) }
        return HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to "7.5"), "h", 1_700_000_000_000L + n,
            note = note, recordId = id, evidence = evidence)
    }

    private fun save(names: HealthOverviewDatabases, value: HealthDraft) = HealthRecordStore(context, names.records).use {
        (it.save(value) as HealthSaveResult.Saved).record
    }

    private fun original(names: HealthOverviewDatabases, bytes: ByteArray, name: String = "fixture.pdf") =
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use {
            it.importOriginal(id(), bytes.inputStream(), name, "application/pdf", "file")
        }

    private fun restore(names: HealthOverviewDatabases, owner: () -> String = { "Fixture Owner" }) =
        HealthRestoreRepository(context, names, owner)

    private fun packageFile(names: HealthOverviewDatabases, owner: String = "Fixture Owner"): File {
        val repo = HealthBackupRepository(context, names)
        val password = secret.toCharArray()
        return try { repo.file(repo.generate(repo.preview(owner, CancellationSignal()), password, CancellationSignal())) }
        finally { password.fill('\u0000') }
    }

    private fun prepare(repo: HealthRestoreRepository, file: File, passwordText: String = secret,
        signal: CancellationSignal = CancellationSignal()): HealthRestorePlan {
        val password = passwordText.toCharArray()
        return try { repo.prepare(file::inputStream, password, signal) } finally { password.fill('\u0000') }
    }

    private fun count(names: HealthOverviewDatabases): Pair<Long, Long> = HealthRecordStore(context, names.records).use { records ->
        HealthOriginalStore(context, names.originals, names.originalRoot(context), records).use { records.count() to it.originalCount() }
    }

    private fun stageFolder(names: HealthOverviewDatabases, id: String) = File(names.originalRoot(context), "restore/$id")

    @Test fun previewProcessDeathLeavesNoCommittedRestore() = processDeath("preview", false)
    @Test fun processDeathInsideCommitRollsBackRecordsFilesAndReceipt() = processDeath("BEFORE_COMMIT", false)
    @Test fun processDeathAfterCommitKeepsOriginalsAndReceiptWithoutDuplicatingOnRetry() = processDeath("AFTER_COMMIT", true)

    @Test fun bluetoothDeviceGroupsSurviveEncryptedBackupAndKeepIdenticalReadingsSeparate() = fixture { source, target ->
        val time = 1_700_000_000_000L
        val rows = HealthRecordStore(context, source.records).use { store ->
            listOf("device-a", "device-b").map { device ->
                (store.saveBluetooth(healthTrendPressure(device, time), "resting") {} as HealthSaveResult.Saved).record
            }
        }
        val file = packageFile(source)
        val repo = restore(target)
        prepare(repo, file).use { assertEquals(2L, it.commit(CancellationSignal()).counts.added) }
        HealthRecordStore(context, target.records).use { store ->
            val day = java.time.Instant.ofEpochMilli(time).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
            val scope = HealthTrendSpec(HealthMetric.BLOOD_PRESSURE, day, day, java.time.ZoneId.systemDefault(), "mmHg")
            for (row in rows) {
                val selected = scope.copy(source = HealthTrendSource(bluetoothGroup = row.bluetoothGroup))
                assertEquals(listOf(row), store.trendRecords(selected, numericOnly = true).records)
            }
        }
        prepare(repo, file).use { assertEquals(2L, it.counts.duplicates) }
    }

    private fun processDeath(phase: String, committed: Boolean) = fixture { source, target ->
        val bytes = "Encrypted restore process fixture".toByteArray()
        val photo = original(source, bytes)
        val record = save(source, draft(1, original = photo))
        val linkedPhoto = original(source, "Secondary restore fixture".toByteArray())
        addSource(source, record, linkedPhoto, 2)
        val backup = packageFile(source)
        val fixtureFile = File(context.cacheDir, "health-restore-process-${target.fixture}.ghbackup")
        backup.copyTo(fixtureFile)
        try {
            val repo = restore(target)
            val batch = stopRestoreProcess(target, phase) { active ->
                val originals = stageFolder(target, active)
                val stage = File(context.cacheDir, "health-restore-stage-${target.fixture}/$active")
                val marker = File(target.originalRoot(context), "restore-pending/$active")
                assertTrue(originals.listFiles().orEmpty().any { it.length() > 0 })
                assertTrue(stage.isDirectory)
                assertTrue(marker.isFile)
                repo.recoverAbandoned()
                assertTrue("Active cross-process restore must keep its files", originals.isDirectory)
                assertTrue(stage.isDirectory)
                assertTrue(marker.isFile)
            }
            val stage = File(context.cacheDir, "health-restore-stage-${target.fixture}/$batch")
            val marker = File(target.originalRoot(context), "restore-pending/$batch")
            assertTrue("Stopped fixture must leave staging for recovery", stage.isDirectory)
            assertTrue(marker.isFile)
            assertEquals(if (committed) (1L to 2L) else (0L to 0L), count(target))
            assertEquals(if (committed) listOf(batch) else emptyList<String>(), repo.recent().map { it.id })
            repeat(2) { repo.recoverAbandoned() }
            assertFalse(stage.exists())
            assertFalse(marker.exists())
            assertEquals(committed, stageFolder(target, batch).exists())
            if (committed) {
                HealthRecordStore(context, target.records).use { records ->
                    HealthOriginalStore(context, target.originals, target.originalRoot(context), records).use { originals ->
                        val restored = requireNotNull(originals.original(photo.id))
                        assertEquals(photo.sha256, restored.sha256)
                        assertArrayEquals(bytes, originals.input(restored).use { it.readBytes() })
                    }
                    assertEquals(1L, repo.recent().single().counts.sourcesAdded)
                }
            }
            prepare(repo, backup).use { plan ->
                assertEquals(if (committed) 0L else 1L, plan.counts.added)
                assertEquals(if (committed) 1L else 0L, plan.counts.duplicates)
                assertEquals(if (committed) 0L else 1L, plan.commit(CancellationSignal()).counts.sourcesAdded)
            }
            assertEquals(1L to 2L, count(target))
        } finally { fixtureFile.delete() }
    }

    private fun stopRestoreProcess(names: HealthOverviewDatabases, phase: String, preview: (String) -> Unit): String {
        val responses = LinkedBlockingQueue<String>()
        val stopped = CountDownLatch(1)
        val service = AtomicReference<Messenger>()
        val listener = Messenger(Handler(Looper.getMainLooper()) { response ->
            responses.offer(response.data.getString("batch") ?: "ERROR: ${response.data.getString("error")}")
            true
        })
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                val remote = Messenger(binder)
                if (!service.compareAndSet(null, remote)) return
                runCatching { remote.send(Message.obtain(null, 1).apply {
                    replyTo = listener
                    data = Bundle().apply { putString("fixture", names.fixture); putString("phase", phase) }
                }) }.onFailure { responses.offer("ERROR: ${it.javaClass.simpleName}") }
            }
            override fun onServiceDisconnected(name: ComponentName) { stopped.countDown() }
            override fun onBindingDied(name: ComponentName) { stopped.countDown() }
        }
        val intent = Intent().setClassName(context, "com.galaxyssi.chat.HealthRestoreProcessFixture")
        assertTrue(context.bindService(intent, connection, Context.BIND_AUTO_CREATE))
        try {
            val id = responses.poll(40, TimeUnit.SECONDS) ?: error("Restore fixture did not open a preview")
            check(HealthProfilePolicy.uuid(id)) { id }
            preview(id)
            service.get().send(Message.obtain(null, 2))
            assertTrue(responses.peek() ?: "Restore fixture did not stop", stopped.await(45, TimeUnit.SECONDS))
            assertNull(responses.peek())
            return id
        } finally { context.unbindService(connection) }
    }

    private fun addSource(names: HealthOverviewDatabases, target: HealthObservation, original: HealthOriginal, index: Int): HealthEvidence {
        val evidence = HealthEvidence(original.id, id(), "association-$index", original.sha256, 2, "Verified source $index",
            boxes = if (target.source == "ocr") listOf(listOf(50, 100, 200, 300)) else emptyList(),
            confirmed = true, kind = target.source, tableRow = if (target.source == "table") index.toLong() else 0L)
        HealthRecordStore(context, names.records).use { records ->
            records.tableDatabase.beginTransaction()
            try {
                records.insertRestoredSource(HealthRestoreSourceLink(target.id, target.revision, target.draft.metric, evidence))
                records.tableDatabase.setTransactionSuccessful()
            } finally { records.tableDatabase.endTransaction() }
        }
        return evidence
    }

    @Test fun secondarySourcesRoundTripAcrossPagesAndRemappedOriginalsWithoutDuplicatingMeasurements() = fixture { source, target ->
        val primaryBytes = "primary OCR report".toByteArray()
        val primary = original(source, primaryBytes)
        val ocr = save(source, draft(1, original = primary))
        val tableFile = original(source, "primary table".toByteArray())
        val tableDraft = draft(2, original = tableFile)
        val table = save(source, tableDraft.copy(evidence = tableDraft.evidence!!.copy(kind = "table", tableRow = 1)))
        val reports = (1..34).map { index ->
            val bytes = "secondary OCR report $index".toByteArray()
            val file = original(source, bytes)
            Triple(file, addSource(source, ocr, file, index), bytes)
        }
        val secondaryTableBytes = "secondary table".toByteArray()
        val secondaryTable = original(source, secondaryTableBytes)
        val tableEvidence = addSource(source, table, secondaryTable, 2)
        val missing = reports.last().first
        HealthOriginalStore(context, source.originals, source.originalRoot(context)).use { assertTrue(it.removeOriginalBytes(missing)) }

        val remappedPrimary = original(target, primaryBytes)
        val remappedTable = original(target, secondaryTableBytes)
        assertNotEquals(primary.id, remappedPrimary.id)
        assertNotEquals(secondaryTable.id, remappedTable.id)
        val current = save(target, ocr.draft.copy(recordId = ocr.id, evidence = ocr.draft.evidence!!.copy(originalId = remappedPrimary.id)))
        val file = packageFile(source)
        val repo = restore(target)
        prepare(repo, file).use { plan ->
            assertEquals(35L, plan.manifest.secondary)
            assertEquals(1, plan.counts.missing)
            assertEquals(HealthRestoreCounts(1, 1, 0, 35, 2, 0, 1, sourcesAdded = 35), plan.counts)
            assertEquals(1L to 2L, count(target))
            plan.commit(CancellationSignal())
        }
        HealthRecordStore(context, target.records).use { records ->
            assertEquals(2L, records.count())
            assertEquals(current, records.record(ocr.id))
            assertEquals(table, records.record(table.id))
            HealthOriginalStore(context, target.originals, target.originalRoot(context), records).use { originals ->
                reports.forEach { (original, evidence, bytes) ->
                    val saved = requireNotNull(originals.original(original.id))
                    assertEquals(original.sha256, saved.sha256)
                    assertEquals(evidence, records.originalPage(original.id).records.single().draft.evidence)
                    if (original.id == missing.id) assertFalse(originals.present(saved))
                    else assertArrayEquals(bytes, originals.input(saved).use { it.readBytes() })
                }
                assertArrayEquals(secondaryTableBytes, originals.input(remappedTable).use { it.readBytes() })
            }
            assertEquals(tableEvidence.copy(originalId = remappedTable.id), records.originalPage(remappedTable.id).records.single().draft.evidence)
        }
        prepare(repo, file).use { plan ->
            assertEquals(0L, plan.counts.added)
            assertEquals(0L, plan.counts.sourcesAdded)
            assertEquals(35L, plan.counts.sourcesReused)
            assertEquals(0L, plan.counts.sourcesSkipped)
            plan.commit(CancellationSignal())
        }
        assertEquals(2L to 37L, count(target))
    }

    @Test fun associationWriteFailureRollsBackRecordsFilesAndReceipt() = fixture { source, target ->
        val record = save(source, draft(1, original = original(source, "primary".toByteArray())))
        val secondary = original(source, "secondary".toByteArray())
        addSource(source, record, secondary, 1)
        val file = packageFile(source)
        val repo = restore(target)
        prepare(repo, file).use { plan ->
            assertEquals(1L, plan.counts.sourcesAdded)
            HealthRecordStore(context, target.records).use { records ->
                records.tableDatabase.execSQL("CREATE TRIGGER refuse_source BEFORE INSERT ON health_source_links BEGIN SELECT RAISE(ABORT,'test failure'); END")
            }
            assertTrue(runCatching { plan.commit(CancellationSignal()) }.exceptionOrNull() is android.database.sqlite.SQLiteConstraintException)
            assertEquals(0L to 0L, count(target))
            assertTrue(repo.recent().isEmpty())
        }
        HealthRecordStore(context, target.records).use { it.tableDatabase.execSQL("DROP TRIGGER refuse_source") }
        prepare(repo, file).use { assertEquals(1L, it.commit(CancellationSignal()).counts.sourcesAdded) }
    }

    @Test fun conflictingMeasurementDoesNotReceiveAnIncomingAssociation() = fixture { source, target ->
        val record = save(source, draft(1, original = original(source, "primary conflict".toByteArray())))
        val secondary = original(source, "secondary conflict".toByteArray())
        addSource(source, record, secondary, 1)
        val existing = save(target, draft(1, note = "Current profile record", id = record.id))
        val repo = restore(target)
        prepare(repo, packageFile(source)).use {
            assertEquals(1L, it.counts.conflicts)
            assertEquals(1L, it.counts.sourcesSkipped)
            assertEquals(it.counts, it.commit(CancellationSignal()).counts)
        }
        HealthRecordStore(context, target.records).use { records ->
            assertEquals(existing, records.record(record.id))
            assertTrue(records.originalPage(secondary.id).records.isEmpty())
        }
    }

    @Test fun selectedConflictAddsRevisionAndSourcesWithoutChangingUnselectedRecords() = fixture { source, target ->
        val incoming = save(source, draft(1, note = "Backup note", original = original(source, "Backup primary".toByteArray())))
        val backupFile = original(source, "Backup secondary".toByteArray())
        val sourceEvidence = addSource(source, incoming, backupFile, 1)
        val untouchedIncoming = save(source, draft(2, note = "Another backup note"))
        val existing = save(target, draft(1, note = "Local note", id = incoming.id, original = original(target, "Local primary".toByteArray())))
        val untouched = save(target, draft(2, note = "Keep this note", id = untouchedIncoming.id))
        val file = packageFile(source)
        val repo = restore(target)
        prepare(repo, file).use { plan ->
            assertEquals(2L, plan.counts.conflicts)
            assertTrue(plan.conflicts().rows.all { it.replaceable })
            assertEquals(1L, plan.counts.sourcesSkipped)
            HealthRecordStore(context, target.records).use { records ->
                records.tableDatabase.execSQL("CREATE TRIGGER fail_replacement_source BEFORE INSERT ON health_source_links BEGIN SELECT RAISE(ABORT,'test failure'); END")
            }
            assertTrue(runCatching { plan.commit(CancellationSignal(), setOf(incoming.id)) }.exceptionOrNull() is android.database.sqlite.SQLiteConstraintException)
            HealthRecordStore(context, target.records).use { records ->
                assertEquals(existing, records.record(existing.id))
                assertNull(records.revision(existing.id, existing.revision + 1))
                assertTrue(records.originalPage(backupFile.id).records.isEmpty())
                records.tableDatabase.execSQL("DROP TRIGGER fail_replacement_source")
            }
            assertTrue(repo.recent().isEmpty())
            val counts = plan.commit(CancellationSignal(), setOf(incoming.id)).counts
            assertEquals(1L, counts.replaced)
            assertEquals(1L, counts.conflicts)
            assertEquals(1L, counts.sourcesAdded)
            assertEquals(0L, counts.sourcesSkipped)
            assertEquals(counts, repo.recent().single().counts)
        }
        HealthRecordStore(context, target.records).use { records ->
            assertEquals(2L, records.count())
            val current = requireNotNull(records.record(incoming.id))
            assertEquals(incoming.draft, current.draft)
            assertEquals(existing.revision + 1, current.revision)
            assertEquals(existing, records.revision(existing.id, existing.revision))
            assertEquals(untouched, records.record(untouched.id))
            assertEquals(sourceEvidence, records.originalPage(backupFile.id).records.single().draft.evidence)
        }
        prepare(repo, file).use { plan ->
            assertEquals(1L, plan.counts.duplicates)
            assertEquals(1L, plan.counts.sourcesReused)
            assertEquals(0L, plan.commit(CancellationSignal()).counts.replaced)
        }
    }

    @Test fun pendingEditOrDeletedTargetCannotBeReplacedAndNoOtherRecordsAreWritten() = fixture { source, target ->
        val incoming = save(source, draft(1, note = "Backup"))
        val deleted = save(source, draft(2))
        save(source, draft(3))
        val current = save(target, draft(1, note = "Local", id = incoming.id))
        val removed = save(target, draft(2, id = deleted.id))
        HealthRecordStore(context, target.records).use { assertTrue(it.delete(removed.id, removed.revision)) }
        val file = packageFile(source)
        val repo = restore(target)
        prepare(repo, file).use { plan ->
            val conflicts = plan.conflicts().rows.associateBy { it.record.id }
            assertTrue(conflicts.getValue(incoming.id).replaceable)
            assertFalse(conflicts.getValue(deleted.id).replaceable)
            assertTrue(runCatching { plan.commit(CancellationSignal(), setOf(incoming.id, deleted.id)) }.exceptionOrNull() is HealthRestoreChanged)
            val edit = current.editable().copy(note = "Unfinished edit")
            HealthRecordStore(context, target.records).use { it.saveDraft(edit) }
            assertTrue(runCatching { plan.commit(CancellationSignal(), setOf(incoming.id)) }.exceptionOrNull() is HealthRestoreChanged)
            HealthRecordStore(context, target.records).use { records ->
                assertEquals(current, records.record(current.id))
                assertNull(records.revision(current.id, current.revision + 1))
                assertEquals(edit, records.draft(HealthRecordStore.draftKey(edit)))
                assertNull(records.record(deleted.id))
                assertEquals(1L, records.count())
            }
            assertTrue(repo.recent().isEmpty())
        }
    }

    @Test fun restoresLegacyVersionOneBackup() = fixture { source, target ->
        val record = save(source, draft(1))
        val manifest = HealthBackupRepository(context, source).preview("Fixture Owner", CancellationSignal()).manifest
        val buffer = java.io.ByteArrayOutputStream()
        val password = secret.toCharArray()
        try {
            HealthBackupCodec.write(buffer, password, manifest, emptySequence(), { _, _ -> error("Unexpected file") },
                sequenceOf(record), formatVersion = 1)
            restore(target).prepare({ buffer.toByteArray().inputStream() }, password, CancellationSignal()).use {
                assertEquals(0L, it.manifest.secondary)
                assertEquals(1L, it.commit(CancellationSignal()).counts.added)
            }
        } finally { password.fill('\u0000') }
        HealthRecordStore(context, target.records).use { assertEquals(record, it.record(record.id)) }
    }

    @Test fun verifiesThenRestoresPagedRecordsAndOriginalAndRepeatIsIdempotent() = fixture { source, target ->
        val content = ByteArray(310_555) { (it % 241).toByte() }
        val photo = original(source, content)
        val incoming = (1..65).map { save(source, draft(it, original = photo.takeIf { _ -> it == 1 })) }
        val packageFile = packageFile(source)
        val repo = restore(target)
        val committed = prepare(repo, packageFile).use { plan ->
            assertEquals(0L to 0L, count(target))
            assertEquals(HealthRestoreCounts(65, 0, 0, 1, 0, 0, 0), plan.counts)
            assertTrue(stageFolder(target, plan.id).listFiles().orEmpty().none { it.readBytes().contentEquals(content) })
            assertTrue(repo.recent().isEmpty())
            plan.commit(CancellationSignal())
        }
        val reopened = restore(target)
        reopened.recoverAbandoned()
        assertEquals(committed, reopened.recent().single())
        HealthRecordStore(context, target.records).use { records ->
            HealthOriginalStore(context, target.originals, target.originalRoot(context), records).use { originals ->
                val restored = requireNotNull(originals.original(photo.id))
                assertEquals(photo.sha256, restored.sha256)
                assertArrayEquals(content, originals.input(restored).use { it.readBytes() })
                assertEquals(incoming.first(), records.page(originalId = photo.id).records.single())
                assertEquals(incoming.first(), records.revision(incoming.first().id, incoming.first().revision))
                assertEquals(65L, records.count())
            }
        }
        prepare(reopened, packageFile).use { plan ->
            assertEquals(HealthRestoreCounts(0, 65, 0, 0, 1, 0, 0), plan.counts)
            plan.commit(CancellationSignal())
        }
        assertEquals(65L to 1L, count(target))
    }

    @Test fun duplicatesConflictsAndTombstonesAreDistinctAndOnlyNewRowsMerge() = fixture { source, target ->
        val changed = save(source, draft(1, note = "incoming"))
        val tombstone = save(source, draft(2))
        save(source, draft(3))
        val added = save(source, draft(4))
        val kept = save(target, draft(1, note = "keep local", id = changed.id))
        val deleted = save(target, draft(2, id = tombstone.id))
        HealthRecordStore(context, target.records).use { assertTrue(it.delete(deleted.id, deleted.revision)) }
        val duplicate = save(target, draft(3))
        val file = packageFile(source)
        val repo = restore(target)
        prepare(repo, file).use { plan ->
            assertEquals(HealthRestoreCounts(1, 1, 2, 0, 0, 0, 0), plan.counts)
            val conflicts = plan.conflicts()
            assertNull(conflicts.next)
            val index = conflicts.rows.associateBy { it.record.id }
            assertEquals(kept, index.getValue(changed.id).existing)
            assertTrue(index.getValue(tombstone.id).deleted)
            plan.commit(CancellationSignal())
        }
        HealthRecordStore(context, target.records).use { records ->
            assertEquals(kept, records.record(changed.id))
            assertNull(records.record(tombstone.id))
            assertEquals(duplicate, records.record(duplicate.id))
            assertEquals(added, records.record(added.id))
            assertEquals(3L, records.count())
        }
    }

    @Test fun rollbackAtReceiptLeavesNeitherObservationsNorOriginalsNorStagedFiles() = fixture { source, target ->
        val attachment = original(source, byteArrayOf(31, 45, 74))
        save(source, draft(1, original = attachment))
        val repo = restore(target)
        val file = packageFile(source)
        val batch = prepare(repo, file).use { plan ->
            HealthRecordStore(context, target.records).use { store ->
                store.tableDatabase.execSQL("CREATE TRIGGER fail_restore BEFORE INSERT ON health_restore_batches BEGIN SELECT RAISE(ABORT,'injected'); END")
            }
            assertTrue(runCatching { plan.commit(CancellationSignal()) }.isFailure)
            assertEquals(0L to 0L, count(target))
            assertTrue(repo.recent().isEmpty())
            plan.id
        }
        assertFalse(stageFolder(target, batch).exists())
        assertFalse(File(context.cacheDir, "health-restore-stage-${target.fixture}/$batch").exists())
    }

    @Test fun damagedPasswordForeignOwnerAndCancelledVerificationNeverWriteLiveData() = fixture { source, target ->
        save(source, draft(1, original = original(source, ByteArray(200_000) { (it % 23).toByte() })))
        val file = packageFile(source)
        val repo = restore(target)
        assertTrue(runCatching { prepare(repo, file, "wrong restore password") }.exceptionOrNull() is HealthBackupException)
        assertTrue(runCatching { prepare(restore(target) { "Different owner" }, file) }.exceptionOrNull() is HealthRestoreOwnerMismatch)
        assertTrue(runCatching { prepare(repo, file, signal = CancellationSignal().apply { cancel() }) }
            .exceptionOrNull() is OperationCanceledException)
        val damaged = File.createTempFile("damaged-health-restore-", ".ghbackup", context.cacheDir)
        try {
            damaged.writeBytes(file.readBytes().let { it.copyOf(it.size - 1) })
            assertTrue(runCatching { prepare(repo, damaged) }.exceptionOrNull() is HealthBackupException)
        } finally { damaged.delete() }
        assertEquals(0L to 0L, count(target))
        assertTrue(repo.recent().isEmpty())
        assertTrue(File(target.originalRoot(context), "restore").listFiles().orEmpty().isEmpty())
    }

    @Test fun restoresMissingProvenanceAndRepairsOnlyMissingCopiesWithoutChangingTheirIds() = fixture { source, target ->
        val same = byteArrayOf(7, 7, 3, 2)
        val incoming = original(source, same)
        val local = original(target, same, "local-name.pdf")
        val missing = original(source, byteArrayOf(8, 9, 8))
        val linked = save(source, draft(1, original = incoming))
        val missingRow = save(source, draft(2, original = missing))
        HealthOriginalStore(context, target.originals, target.originalRoot(context)).use { assertTrue(it.removeOriginalBytes(local)) }
        HealthOriginalStore(context, source.originals, source.originalRoot(context)).use { assertTrue(it.removeOriginalBytes(missing)) }
        val file = packageFile(source)
        prepare(restore(target), file).use { plan ->
            assertEquals(HealthRestoreCounts(2, 0, 0, 1, 0, 1, 1), plan.counts)
            plan.commit(CancellationSignal())
        }
        HealthRecordStore(context, target.records).use { records ->
            HealthOriginalStore(context, target.originals, target.originalRoot(context), records).use { originals ->
                assertEquals(local.id, records.record(linked.id)?.draft?.evidence?.originalId)
                val repaired = requireNotNull(originals.original(local.id))
                assertEquals(local.name, repaired.name)
                assertArrayEquals(same, originals.input(repaired).use { it.readBytes() })
                assertEquals(missing.id, records.record(missingRow.id)?.draft?.evidence?.originalId)
                assertFalse(originals.present(requireNotNull(originals.original(missing.id))))
            }
        }
    }

    @Test fun changedTargetRejectsOldPreviewAndRestartCleanupRemovesOnlyAbandonedWork() = fixture { source, target ->
        save(source, draft(1))
        val file = packageFile(source)
        val repo = restore(target)
        val abandoned = stageFolder(target, id()).apply { check(mkdirs()) }
        File(abandoned, "fixture.enc").writeBytes(byteArrayOf(77))
        prepare(repo, file).use { plan ->
            repo.recoverAbandoned()
            assertFalse(abandoned.exists())
            assertTrue(stageFolder(target, plan.id).exists())
            save(target, draft(3))
            assertTrue(runCatching { plan.commit(CancellationSignal()) }.exceptionOrNull() is HealthRestoreChanged)
            assertTrue(repo.recent().isEmpty())
        }
        assertEquals(1L to 0L, count(target))
    }

    @Test fun nativeRestoreRequiresConsentAndWritesAnIsolatedReceipt() = fixture { source, target ->
        assumeFalse("Restore UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val record = save(source, draft(1, original = original(source, "UI primary".toByteArray())))
        val secondary = original(source, "UI secondary".toByteArray())
        val evidence = addSource(source, record, secondary, 1)
        val updated = save(source, draft(2, note = "Backup revision"))
        val local = save(target, draft(2, note = "Local revision", id = updated.id))
        val packageFile = packageFile(source)
        val folder = File(context.cacheDir, "health-backups").apply { mkdirs() }
        val picked = File(folder, "restore-ui-${id()}.ghbackup")
        packageFile.copyTo(picked)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", picked)
        val filter = IntentFilter(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addDataType("*/*")
        }
        val monitor = instrumentation.addMonitor(filter, Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(uri)), true)
        try {
            val intent = Intent(context, HealthRestoreActivity::class.java).putExtra("health_restore_test_id", target.fixture)
            ActivityScenario.launch<HealthRestoreActivity>(intent).use { scenario ->
                scenario.onActivity { assertTrue(requireNotNull(find(it.window.decorView, "health-restore-select")).performClick()) }
                val editor = awaitValue { node(instrumentation.uiAutomation.rootInActiveWindow) { it.className == "android.widget.EditText" } }
                assertTrue(editor.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, secret)
                }))
                val ok = context.getString(android.R.string.ok)
                assertTrue(awaitValue { node(instrumentation.uiAutomation.rootInActiveWindow) { it.text?.toString() == ok && it.isClickable } }
                    .performAction(AccessibilityNodeInfo.ACTION_CLICK))
                awaitValue {
                    var ready = false
                    scenario.onActivity { ready = find(it.window.decorView, "health-restore-preview") != null }
                    true.takeIf { ready }
                }
                assertEquals(1L to 0L, count(target))
                scenario.onActivity {
                    val caption = it.getString(R.string.health_restore_secondary_counts, 1, 0, 0)
                    assertNotNull(findText(it.window.decorView, caption))
                    assertTrue(requireNotNull(find(it.window.decorView, "health-restore-review-conflicts")).performClick())
                }
                awaitValue {
                    var ready = false
                    scenario.onActivity { ready = find(it.window.decorView, "health-restore-replace-${updated.id}") != null }
                    true.takeIf { ready }
                }
                scenario.onActivity {
                    val replace = requireNotNull(find(it.window.decorView, "health-restore-replace-${updated.id}")) as CheckBox
                    assertFalse(replace.isChecked)
                    replace.isChecked = true
                    assertTrue(requireNotNull(find(it.window.decorView, "health-restore-back-preview")).performClick())
                }
                HealthRecordStore(context, target.records).use { assertEquals(local, it.record(local.id)) }
                scenario.onActivity {
                    val commit = requireNotNull(find(it.window.decorView, "health-restore-commit"))
                    assertFalse(commit.isEnabled)
                    val consent = requireNotNull(find(it.window.decorView, "health-restore-consent")) as CheckBox
                    assertEquals(it.getString(R.string.health_restore_confirm_replacements, 1), consent.text)
                    consent.isChecked = true
                    assertTrue(commit.isEnabled)
                    assertTrue(commit.performClick())
                }
                awaitValue {
                    var ready = false
                    scenario.onActivity { ready = find(it.window.decorView, "health-restore-receipt") != null }
                    true.takeIf { ready }
                }
                assertEquals(1L, restore(target).recent().single().counts.added)
                assertEquals(1L, restore(target).recent().single().counts.sourcesAdded)
                assertEquals(1L, restore(target).recent().single().counts.replaced)
                HealthRecordStore(context, target.records).use { records ->
                    assertEquals(evidence, records.originalPage(secondary.id).records.single().draft.evidence)
                }
            }
        } finally { instrumentation.removeMonitor(monitor); picked.delete() }
    }

    private fun find(root: View, tag: String): View? = if (root.tag == tag) root else if (root is ViewGroup)
        (0 until root.childCount).firstNotNullOfOrNull { find(root.getChildAt(it), tag) } else null

    private fun findText(root: View, text: String): View? = when {
        root is android.widget.TextView && root.text.toString() == text -> root
        root is ViewGroup -> (0 until root.childCount).firstNotNullOfOrNull { findText(root.getChildAt(it), text) }
        else -> null
    }

    private fun node(root: AccessibilityNodeInfo?, matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (root == null || matches(root)) return root
        return (0 until root.childCount).firstNotNullOfOrNull { node(root.getChild(it), matches) }
    }

    private fun <T : Any> awaitValue(read: () -> T?): T {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do {
            read()?.let { return it }
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        error("Timed out waiting for the native restore screen")
    }
}
