package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.CancellationSignal
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
        save(source, draft(1))
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
                assertEquals(0L to 0L, count(target))
                scenario.onActivity {
                    val commit = requireNotNull(find(it.window.decorView, "health-restore-commit"))
                    assertFalse(commit.isEnabled)
                    (requireNotNull(find(it.window.decorView, "health-restore-consent")) as CheckBox).isChecked = true
                    assertTrue(commit.isEnabled)
                    assertTrue(commit.performClick())
                }
                awaitValue {
                    var ready = false
                    scenario.onActivity { ready = find(it.window.decorView, "health-restore-receipt") != null }
                    true.takeIf { ready }
                }
                assertEquals(1L, restore(target).recent().single().counts.added)
            }
        } finally { instrumentation.removeMonitor(monitor); picked.delete() }
    }

    private fun find(root: View, tag: String): View? = if (root.tag == tag) root else if (root is ViewGroup)
        (0 until root.childCount).firstNotNullOfOrNull { find(root.getChildAt(it), tag) } else null

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
