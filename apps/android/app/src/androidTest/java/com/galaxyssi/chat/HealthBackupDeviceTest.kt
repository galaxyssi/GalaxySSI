package com.galaxyssi.chat

import android.app.KeyguardManager
import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.IntentFilter
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlin.random.Random
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthBackupDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val password get() = "fixture password 备份".toCharArray()

    private fun fixture(test: (HealthOverviewDatabases, HealthBackupRepository) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val repo = HealthBackupRepository(context, names)
        try { test(names, repo) } finally {
            repo.cleanup(Long.MAX_VALUE)
            clearHealthOverviewFixture(context, names)
        }
    }

    private fun original(names: HealthOverviewDatabases, bytes: ByteArray) =
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use {
            it.importOriginal(UUID.randomUUID().toString(), bytes.inputStream(), "test report.pdf", "application/pdf", "file")
        }

    private fun seed(names: HealthOverviewDatabases, file: HealthOriginal? = null, index: Int = 0): HealthObservation =
        HealthRecordStore(context, names.records).use {
            val evidence = file?.let { HealthEvidence(it.id, UUID.randomUUID().toString(), "backup-fixture", it.sha256, 1,
                "PRIVATE_OCR_FIXTURE", confirmed = true) }
            (it.save(HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to "7.5"), "h",
                1_700_000_000_000L + index, note = "PRIVATE_MEASUREMENT_FIXTURE", evidence = evidence)) as HealthSaveResult.Saved).record
        }

    private fun create(repo: HealthBackupRepository, preview: HealthBackupPreview) = password.let {
        try { repo.generate(preview, it, CancellationSignal()) } finally { it.fill('\u0000') }
    }

    private fun verify(bytes: ByteArray, password: CharArray = this.password, originals: (HealthBackupOriginal) -> java.io.OutputStream? = { null },
        records: (HealthObservation) -> Unit = {}): HealthBackupManifest = try {
        bytes.inputStream().use { HealthBackupCodec.verify(it, password, onOriginal = originals, onRecord = records) }
    } finally { password.fill('\u0000') }

    private fun failure(block: () -> Unit) = (runCatching(block).exceptionOrNull() as? HealthBackupException)?.issue

    @Test fun verifiedSaveSurvivesReopenFailedRetryAndPrivateCleanup() = fixture { names, repo ->
        seed(names)
        val result = create(repo, repo.preview("PRIVATE_OWNER", CancellationSignal()))
        val reopened = HealthBackupRepository(context, names)
        val generated = requireNotNull(reopened.history(result.id))
        assertEquals(HealthBackupGeneration.READY, generated.receipt.generation)
        assertEquals(HealthBackupSave.NONE, generated.receipt.save)
        assertEquals(1L, generated.receipt.records)
        assertTrue(generated.available)
        val output = ByteArrayOutputStream()
        val saved = reopened.saveVerified(result.id, CancellationSignal(), { output }, { output.toByteArray().inputStream() }) {
            fail("Verified output must not be discarded")
        }
        assertEquals(HealthBackupSave.VERIFIED, saved.receipt.save)
        assertTrue(saved.receipt.savedAt > 0)
        assertArrayEquals(repo.file(result).readBytes(), output.toByteArray())
        var discarded = false
        assertTrue(runCatching {
            reopened.saveVerified(result.id, CancellationSignal(), { ByteArrayOutputStream() }, { byteArrayOf(0).inputStream() }) {
                discarded = true
            }
        }.isFailure)
        assertTrue(discarded)
        val failed = requireNotNull(reopened.history(result.id))
        assertEquals(HealthBackupSave.FAILED, failed.receipt.save)
        assertEquals(saved.receipt.savedAt, failed.receipt.savedAt)
        reopened.forget(result)
        assertFalse(requireNotNull(repo.history(result.id)).available)
        assertEquals(saved.receipt.savedAt, repo.historyPage(null).rows.single().receipt.savedAt)
        context.openOrCreateDatabase(names.backups, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM backups", null).use {
                assertTrue(it.moveToFirst())
                val raw = String(it.getBlob(0), Charsets.ISO_8859_1)
                assertFalse(raw.contains("PRIVATE_OWNER"))
                assertFalse(raw.contains(result.hash))
            }
        }
    }

    @Test fun historyReconcilesACompletedPublishAndDoesNotInventAnInterruptedSave() = fixture { names, repo ->
        val result = create(repo, repo.preview("", CancellationSignal()))
        val receipt = requireNotNull(repo.history(result.id)).receipt
        val unfinished = receipt.copy(id = UUID.randomUUID().toString(), generation = HealthBackupGeneration.GENERATING)
        HealthBackupHistoryStore(context, names.backups).use {
            it.put(receipt.copy(generation = HealthBackupGeneration.GENERATING))
            it.put(unfinished)
        }
        assertTrue(runCatching { repo.history(result.id, CancellationSignal().apply { cancel() }) }
            .exceptionOrNull() is OperationCanceledException)
        assertTrue(repo.file(result).isFile)
        val recovered = requireNotNull(repo.history(result.id))
        assertEquals(HealthBackupGeneration.READY, recovered.receipt.generation)
        assertTrue(recovered.available)
        assertEquals(HealthBackupGeneration.INTERRUPTED, repo.history(unfinished.id)?.receipt?.generation)
        HealthBackupHistoryStore(context, names.backups).use { it.put(receipt.copy(save = HealthBackupSave.SAVING)) }
        assertEquals(HealthBackupSave.INTERRUPTED, repo.history(result.id)?.receipt?.save)
        assertEquals(0L, repo.history(result.id)?.receipt?.savedAt)
    }

    @Test fun cancelledGenerationAndEqualTimestampPagesRemainDistinguishable() = fixture { names, repo ->
        val preview = repo.preview("", CancellationSignal())
        val secret = password
        try {
            assertTrue(runCatching { repo.generate(preview, secret, CancellationSignal().apply { cancel() }) }
                .exceptionOrNull() is OperationCanceledException)
        } finally { secret.fill('\u0000') }
        val cancelled = requireNotNull(repo.history(preview.manifest.id)).receipt
        assertEquals(HealthBackupGeneration.CANCELLED, cancelled.generation)
        val ids = (0..30).map { UUID.randomUUID().toString() }.sortedDescending()
        HealthBackupHistoryStore(context, names.backups).use { history ->
            ids.forEach { history.put(cancelled.copy(id = it, created = cancelled.created + 1, generation = HealthBackupGeneration.FAILED)) }
        }
        val first = repo.historyPage(null)
        val second = repo.historyPage(requireNotNull(first.next))
        assertEquals(ids + cancelled.id, (first.rows + second.rows).map { it.receipt.id })
        assertNull(second.next)
    }

    @Test fun nativeHistoryReopensVerifiedReceiptAfterPrivateCopyIsRemoved() = fixture { names, repo ->
        assumeFalse("Backup history UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        seed(names)
        val artifact = create(repo, repo.preview("", CancellationSignal()))
        val folder = File(context.cacheDir, "health-backups")
        check(folder.isDirectory || folder.mkdirs())
        val output = File(folder, "backup-history-fixture-${artifact.id}.ghbackup")
        check(output.createNewFile())
        val destination = FileProvider.getUriForFile(context, "${context.packageName}.files", output)
        val filter = IntentFilter(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addDataType("application/octet-stream")
        }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val monitor = instrumentation.addMonitor(filter,
            Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(destination)), true)
        val intent = Intent(context, HealthBackupActivity::class.java).putExtra("health_backup_test_id", names.fixture)
            .putExtra("backup_history", true)
        try { ActivityScenario.launch<HealthBackupActivity>(intent).use { scenario ->
            fun await(tag: String, matches: (View) -> Boolean = { true }) {
                val deadline = SystemClock.elapsedRealtime() + 12_000L
                do {
                    var present = false
                    scenario.onActivity { present = it.window.decorView.findViewWithTag<View>(tag)?.let(matches) == true }
                    if (present) return
                    SystemClock.sleep(50)
                } while (SystemClock.elapsedRealtime() < deadline)
                fail("Missing backup history view: $tag")
            }
            val row = "health-backup-history-${artifact.id}"
            await(row)
            scenario.onActivity { assertTrue(requireNotNull(it.window.decorView.findViewWithTag<View>(row)).performClick()) }
            await("health-backup-save")
            scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>("health-backup-save").performClick()) }
            await("health-backup-save-state") { (it as android.widget.TextView).text.toString() == context.getString(R.string.health_backup_saved) }
            assertEquals(1, monitor.hits)
            assertArrayEquals(repo.file(artifact).readBytes(), output.readBytes())
            repo.forget(artifact)
            scenario.recreate()
            await("health-backup-save-state")
            scenario.onActivity {
                val state = requireNotNull(it.window.decorView.findViewWithTag<android.widget.TextView>("health-backup-save-state"))
                assertEquals(context.getString(R.string.health_backup_saved), state.text.toString())
                assertNull(it.window.decorView.findViewWithTag<View>("health-backup-save"))
                it.onBackPressed()
            }
            await(row)
        } } finally {
            instrumentation.removeMonitor(monitor)
            output.delete()
        }
    }

    @Test fun portableBundlePreservesPagedRecordsOriginalDigestAndExactLink() = fixture { names, repo ->
        val bytes = Random(19).nextBytes(2 * 1024 * 1024 + 17)
        val file = original(names, bytes)
        val expected = (0 until 65).map { index -> seed(names, file.takeIf { index == 0 }, index) }.sortedBy { it.id }
        val preview = repo.preview("Fixture owner", CancellationSignal())
        assertEquals(65L, preview.manifest.records)
        assertEquals(1L, preview.manifest.linked)
        assertEquals(1, preview.manifest.originals)
        val artifact = create(repo, preview)
        val sealed = ByteArrayOutputStream()
        assertEquals(artifact.size, repo.save(artifact, sealed, CancellationSignal()))
        val ciphertext = sealed.toByteArray()
        assertFalse(ciphertext.toString(Charsets.ISO_8859_1).contains("PRIVATE_MEASUREMENT_FIXTURE"))
        assertFalse(ciphertext.toString(Charsets.ISO_8859_1).contains("Fixture owner"))
        val restoredOriginal = ByteArrayOutputStream()
        val records = arrayListOf<HealthObservation>()
        val verified = verify(ciphertext, originals = { entry ->
            assertEquals(file.sha256, entry.sha256)
            assertEquals(file.id, entry.id)
            assertEquals(file.size, entry.bytes)
            restoredOriginal
        }, records = records::add)
        assertEquals(preview.manifest, verified)
        assertEquals(expected, records)
        assertArrayEquals(bytes, restoredOriginal.toByteArray())
    }

    @Test fun passwordAndVersionErrorsAreDistinctFromTamperingAndTruncation() = fixture { names, repo ->
        seed(names)
        val artifact = create(repo, repo.preview("", CancellationSignal()))
        val bytes = repo.file(artifact).readBytes()
        assertEquals(HealthBackupIssue.UNLOCK, failure { verify(bytes, "incorrect fixture password".toCharArray()) })
        assertEquals(HealthBackupIssue.FORMAT, failure { verify("""{"records":[]}""".toByteArray()) })
        assertEquals(HealthBackupIssue.OLDER_VERSION, failure { verify(bytes.clone().also { it[11] = 0 }) })
        assertEquals(HealthBackupIssue.NEWER_VERSION, failure { verify(bytes.clone().also { it[11] = 2 }) })
        assertEquals(HealthBackupIssue.DAMAGED, failure { verify(bytes.copyOf(bytes.size - 1)) })
        assertEquals(HealthBackupIssue.DAMAGED, failure { verify(bytes + byteArrayOf(0)) })
        assertEquals(HealthBackupIssue.DAMAGED, failure { verify(bytes.clone().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }) })
    }

    @Test fun missingBytesKeepProvenanceButDoNotClaimCompleteness() = fixture { names, repo ->
        val file = original(names, ByteArray(8) { it.toByte() })
        val row = seed(names, file)
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { assertTrue(it.removeOriginalBytes(file)) }
        val preview = repo.preview("", CancellationSignal())
        assertEquals(1, preview.manifest.missing)
        assertEquals(0L, preview.manifest.originalBytes)
        val artifact = create(repo, preview)
        assertEquals(1, artifact.missing)
        val records = arrayListOf<HealthObservation>()
        val verified = verify(repo.file(artifact).readBytes(), originals = { error("Missing bytes must not be extracted") }, records = records::add)
        assertEquals(listOf(row), records)
        assertEquals(1, verified.missing)
        assertEquals(1L, verified.linked)
    }

    @Test fun reviewOnlySourcesNeverExportBytesAndSharedDigestsUseRetainedOriginals() = fixture { names, repo ->
        val bytes = ByteArray(128) { it.toByte() }
        val retained = original(names, bytes)
        val (same, unique) = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
            fun temporary(payload: ByteArray): HealthOriginal {
                val id = UUID.randomUUID().toString()
                store.createJob(HealthImportJob(id, "content://fixture/report", 1L, keepOriginal = false))
                return store.importOriginal(id, payload.inputStream(), "review.pdf", "application/pdf", "file").also {
                    assertTrue(store.present(it))
                }
            }
            val pending = temporary(byteArrayOf(55, 44, 33))
            assertTrue(pending.reviewOnly)
            temporary(bytes) to temporary(byteArrayOf(8, 9, 10))
        }
        val first = seed(names, same, 1)
        val second = seed(names, unique, 2)
        val preview = repo.preview("", CancellationSignal())
        assertEquals(2, preview.manifest.originals)
        assertEquals(1, preview.manifest.missing)
        assertEquals(retained.size, preview.manifest.originalBytes)
        val result = create(repo, preview)
        val linked = mutableMapOf<String, HealthEvidence>()
        val missing = mutableListOf<String>()
        val restored = ByteArrayOutputStream()
        val secret = password
        try {
            repo.file(result).inputStream().use { input ->
                HealthBackupCodec.verify(input, secret, onOriginal = { item ->
                    assertEquals(retained.id, item.id)
                    restored
                }, onMissingOriginal = { missing += it.id },
                    onRecord = { row -> linked[row.id] = requireNotNull(row.draft.evidence) })
            }
        } finally { secret.fill('\u0000') }
        assertArrayEquals(bytes, restored.toByteArray())
        assertEquals(listOf(unique.id), missing)
        assertEquals(first.draft.evidence!!.copy(originalId = retained.id), linked[first.id])
        assertEquals(second.draft.evidence, linked[second.id])
    }

    @Test fun validCiphertextWithIncorrectOriginalDigestIsRejected() = fixture { names, repo ->
        val content = byteArrayOf(1, 2, 3, 4)
        original(names, content)
        val preview = repo.preview("", CancellationSignal())
        val output = ByteArrayOutputStream()
        val secret = password
        try {
            HealthBackupCodec.write(output, secret, preview.manifest, preview.examples.asSequence(),
                { _, sink -> sink.write(byteArrayOf(1, 2, 3, 5)) }, emptySequence())
        } finally { secret.fill('\u0000') }
        assertEquals(HealthBackupIssue.DAMAGED, failure { verify(output.toByteArray()) })
    }

    @Test fun largeOriginalVerificationCanStopMidStream() = fixture { names, repo ->
        val bytes = Random(76).nextBytes(16 * 1024 * 1024)
        original(names, bytes)
        val artifact = create(repo, repo.preview("", CancellationSignal()))
        val signal = CancellationSignal()
        var scanned = 0L
        val secret = password
        try {
            val failure = runCatching {
                repo.file(artifact).inputStream().use { input ->
                    HealthBackupCodec.verify(input, secret, signal::throwIfCanceled, onOriginal = {
                        object : java.io.OutputStream() {
                            override fun write(value: Int) = error("Expected bulk write")
                            override fun write(buffer: ByteArray, offset: Int, length: Int) {
                                scanned += length
                                if (scanned >= 1024 * 1024) signal.cancel()
                            }
                        }
                    })
                }
            }.exceptionOrNull()
            assertTrue(failure is OperationCanceledException)
            assertEquals(1024 * 1024L, scanned)
        } finally { secret.fill('\u0000'); bytes.fill(0) }
    }

    @Test fun sourceChangesAndCancellationCannotPublishBackup() = fixture { names, repo ->
        seed(names)
        val stale = repo.preview("", CancellationSignal())
        seed(names, index = 1)
        assertEquals(HealthBackupIssue.SOURCE_CHANGED, failure { create(repo, stale) })
        val cancelled = repo.preview("", CancellationSignal())
        val signal = CancellationSignal().apply { cancel() }
        val secret = password
        try { assertTrue(runCatching { repo.generate(cancelled, secret, signal) }.exceptionOrNull() is OperationCanceledException) }
        finally { secret.fill('\u0000') }
        val folder = java.io.File(context.cacheDir, "health-backup-test-${names.fixture}")
        assertTrue(folder.listFiles().orEmpty().isEmpty())
    }

    @Test fun damagedOriginalCannotBePublishedEvenWithAnUnchangedManifest() = fixture { names, repo ->
        val file = original(names, Random(21).nextBytes(130_000))
        seed(names, file)
        val preview = repo.preview("", CancellationSignal())
        val encrypted = java.io.File(names.originalRoot(context), file.relativePath)
        java.io.RandomAccessFile(encrypted, "rw").use {
            it.seek(it.length() - 1)
            val byte = it.read()
            it.seek(it.length() - 1)
            it.write(byte xor 1)
        }
        assertTrue(runCatching { create(repo, preview) }.isFailure)
        val folder = java.io.File(context.cacheDir, "health-backup-test-${names.fixture}")
        assertTrue(folder.listFiles().orEmpty().isEmpty())
    }

    @Test fun nativeManifestRequiresConfirmationBeforePasswordPrompt() = fixture { names, _ ->
        assumeFalse("Backup UI requires unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        seed(names)
        val intent = Intent(context, HealthBackupActivity::class.java).putExtra("health_backup_test_id", names.fixture)
        fun find(root: View, tag: String): View? = if (root.tag == tag) root else if (root is ViewGroup)
            (0 until root.childCount).firstNotNullOfOrNull { find(root.getChildAt(it), tag) } else null
        ActivityScenario.launch<HealthBackupActivity>(intent).use { scenario ->
            scenario.onActivity { assertTrue(requireNotNull(find(it.window.decorView, "health-backup-preview")).performClick()) }
            val deadline = SystemClock.elapsedRealtime() + 15_000
            do {
                var found = false
                scenario.onActivity {
                    val generate = find(it.window.decorView, "health-backup-encrypt")
                    if (generate != null) {
                        assertNotNull(find(it.window.decorView, "health-backup-manifest"))
                        assertFalse(generate.isEnabled)
                        found = true
                    }
                }
                if (found) return@fixture
                SystemClock.sleep(50)
            } while (SystemClock.elapsedRealtime() < deadline)
            fail("Missing native backup manifest")
        }
    }
}
