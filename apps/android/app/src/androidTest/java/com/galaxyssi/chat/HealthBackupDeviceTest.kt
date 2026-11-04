package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
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
