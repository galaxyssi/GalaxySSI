package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.OpenableColumns
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.Button
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthExportShareDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val resolver get() = context.contentResolver
    private fun id() = UUID.randomUUID().toString()

    private fun fixture(test: (String, HealthRecordStore, HealthOriginalStore, HealthRecordExportStore) -> Unit) {
        val token = id()
        val names = HealthOverviewDatabases(token)
        try {
            HealthRecordStore(context, names.records).use { records ->
                HealthExportShare.openOriginals(context, token).use { originals ->
                    HealthExportShare.openRecords(context, token).use { exports -> test(token, records, originals, exports) }
                }
            }
        } finally {
            clearHealthOverviewFixture(context, names)
            context.deleteDatabase(HealthExportShare.recordDatabase(token))
            File(context.cacheDir, "health-record-export-test-$token").deleteRecursively()
            File(context.cacheDir, "health-original-export-test-$token").deleteRecursively()
        }
    }

    private fun generate(records: HealthRecordStore, originals: HealthOriginalStore, exports: HealthRecordExportStore,
                         bundle: Boolean = false): HealthRecordExportSession {
        val original = if (bundle) originals.importOriginal(id(), "fixture bytes".byteInputStream(), "fixture.pdf", "application/pdf", "file") else null
        assertTrue(records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "61"), "kg", System.currentTimeMillis() - 60_000,
            evidence = original?.let { HealthEvidence(it.id, it.id, "fixture", it.sha256, 1, "", confirmed = true) })) is HealthSaveResult.Saved)
        val session = exports.create(HealthRecordExportScope(uploadedOriginals = bundle))
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.prepare(records, originals, exports, session.id, session.dispatch))
        val queued = exports.queue(session.id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.generate(exports, queued.id, queued.dispatch, originals = originals))
        return requireNotNull(exports.session(queued.id)).also { assertEquals(HealthRecordExportState.GENERATED, it.state) }
    }

    private fun shell(command: String) = ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command))
        .use { it.readBytes() }

    @Suppress("DEPRECATION")
    @Test fun chooserGrantsOnlyTheExactReadOnlyArtifactUri() = fixture { token, records, originals, exports ->
        val session = generate(records, originals, exports)
        val item = HealthExportShareItem.records(session)
        val uri = HealthExportShare.uri(context, item, token)
        val chooser = HealthExportShare.chooser(context, item, token)
        val send = requireNotNull(chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT))
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("text/csv", send.type)
        assertNull(send.`package`); assertNull(send.component)
        assertEquals(uri, send.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        assertEquals(uri, send.clipData!!.getItemAt(0).uri)
        assertEquals(uri, chooser.clipData!!.getItemAt(0).uri)
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, send.flags and GRANT_FLAGS)
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, chooser.flags and GRANT_FLAGS)
        val expected = exports.input(session).use { it.readBytes() }
        val shellUid = context.packageManager.getApplicationInfo("com.android.shell", 0).uid
        fun readAsShell(target: Uri = uri) = shell("content read --uri $target")
        fun permission(target: Uri = uri) = context.checkUriPermission(target, -1, shellUid, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        assertEquals(PackageManager.PERMISSION_DENIED, permission())
        assertFalse(expected.contentEquals(readAsShell()))
        context.grantUriPermission("com.android.shell", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            assertEquals(PackageManager.PERMISSION_GRANTED, permission())
            assertArrayEquals(expected, readAsShell())
            val neighbor = HealthExportShare.uri(context, item.copy(attempt = id()), token)
            assertEquals(PackageManager.PERMISSION_DENIED, permission(neighbor))
            assertFalse(expected.contentEquals(readAsShell(neighbor)))
        } finally { context.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        assertEquals(PackageManager.PERMISSION_DENIED, permission())
        assertFalse(expected.contentEquals(readAsShell()))
        assertEquals(HealthRecordExportState.GENERATED, exports.session(session.id)!!.state)
    }

    @Test fun providerBindsMetadataAndBytesToTheCurrentCompletedAttempt() = fixture { token, records, originals, exports ->
        val session = generate(records, originals, exports, bundle = true)
        val item = HealthExportShareItem.records(session)
        val uri = HealthExportShare.uri(context, item, token)
        assertEquals("application/zip", resolver.getType(uri))
        resolver.query(uri, arrayOf(OpenableColumns.SIZE, OpenableColumns.DISPLAY_NAME, "local_path"), null, null, null)!!.use {
            assertTrue(it.moveToFirst()); assertEquals(2, it.columnCount)
            assertEquals(session.artifactBytes, it.getLong(0)); assertEquals(item.name, it.getString(1))
        }
        assertArrayEquals(exports.input(session).use { it.readBytes() }, resolver.openInputStream(uri)!!.use { it.readBytes() })
        assertTrue(runCatching { resolver.openFileDescriptor(uri, "rw")?.close() }.isFailure)
        val wrongAttempt = HealthExportShare.uri(context, item.copy(attempt = id()), token)
        assertTrue(runCatching { resolver.openFileDescriptor(wrongAttempt, "r")?.close() }.isFailure)
        val malformed = uri.buildUpon().appendQueryParameter("path", "ignored").build()
        assertTrue(runCatching { resolver.openFileDescriptor(malformed, "r")?.close() }.isFailure)
        val preparing = exports.create(HealthRecordExportScope())
        val claimed = requireNotNull(exports.claimPrepare(preparing.id, preparing.dispatch))
        val notReady = HealthExportShare.uri(context, HealthExportShareItem.records(claimed), token)
        assertTrue(runCatching { resolver.openFileDescriptor(notReady, "r")?.close() }.isFailure)
        assertEquals(HealthRecordExportState.GENERATED, exports.session(session.id)!!.state)
    }

    @Test fun originalArchiveSupportsAuthenticatedSeeksAndRejectsTamperedCiphertext() = fixture { token, _, originals, _ ->
        val library = HealthExportShare.originalLibrary(context, originals, token)
        val source = ByteArray(190_000).also(java.util.Random(53)::nextBytes)
        val original = originals.importOriginal(id(), source.inputStream(), "fixture.bin", "application/octet-stream", "file")
        val id = library.createSelection().id
        library.select(id, listOf(original.id), true)
        library.prepare(id)
        val queued = library.queue(id)
        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, library, id, queued.dispatch))
        val session = requireNotNull(library.session(id))
        val uri = HealthExportShare.uri(context, HealthExportShareItem.originals(session), token)
        val expected = library.input(session).use { it.readBytes() }
        ParcelFileDescriptor.AutoCloseInputStream(resolver.openFileDescriptor(uri, "r")!!).use { stream ->
            assertEquals(expected.size.toLong(), stream.channel.size())
            for (offset in listOf(65_000L, 150_000L, 100L)) {
                val buffer = ByteBuffer.allocate(1500)
                stream.channel.position(offset)
                while (buffer.hasRemaining()) assertTrue(stream.channel.read(buffer) > 0)
                assertArrayEquals(expected.copyOfRange(offset.toInt(), offset.toInt() + 1500), buffer.array())
            }
        }
        RandomAccessFile(library.file(session), "rw").use { it.seek(256); val byte = it.read(); it.seek(256); it.write(byte xor 1) }
        assertTrue(runCatching { resolver.openInputStream(uri)!!.use { it.readBytes() } }.isFailure)
        assertEquals(HealthOriginalExportState.GENERATED, library.session(id)!!.state)
    }

    @Test fun nativeShareRequiresConfirmationAndCancellingSystemChooserDoesNotSave() = fixture { token, records, originals, exports ->
        assumeFalse("An unlocked Android 10+ screen is required", android.os.Build.VERSION.SDK_INT < 29 ||
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val session = generate(records, originals, exports, bundle = true)
        val intent = Intent(context, HealthRecordExportActivity::class.java).putExtra("record_export", session.id)
            .putExtra("health_record_export_test_id", token)
        ActivityScenario.launch<HealthRecordExportActivity>(intent).use { scenario ->
            fun await(label: String, check: () -> Boolean) {
                val deadline = SystemClock.elapsedRealtime() + 10_000
                do { if (check()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < deadline)
                fail(label)
            }
            fun share(): Boolean {
                var clicked = false
                scenario.onActivity { clicked = it.window.decorView.findViewWithTag<View>("health-record-export-share")?.performClick() == true }
                return clicked
            }
            fun confirmation(which: Int) = scenario.onActivity {
                val button = WindowInspector.getGlobalWindowViews().mapNotNull { root -> root.findViewById<Button>(which) }.last()
                assertTrue(button.performClick())
            }
            await("Share action not shown", ::share)
            confirmation(android.R.id.button2)
            assertEquals(HealthRecordExportState.GENERATED, exports.session(session.id)!!.state)
            await("Share action unavailable after cancellation", ::share)
            confirmation(android.R.id.button1)
            fun chooserVisible(): Boolean = shell("dumpsys activity activities").toString(Charsets.UTF_8).lineSequence()
                .filter { it.contains("ResumedActivity:", ignoreCase = true) }
                .any { it.contains(Regex("ChooserActivity|ResolverActivity|sharelive", RegexOption.IGNORE_CASE)) }
            await("Android share chooser did not appear", ::chooserVisible)
            instrumentation.uiAutomation.waitForIdle(100, 5000)
            shell("input keyevent KEYCODE_BACK")
            await("Android share chooser did not dismiss") { !chooserVisible() }
            assertEquals(HealthRecordExportState.GENERATED, exports.session(session.id)!!.state)
            assertEquals(1L, records.count())
        }
    }

    companion object {
        private const val GRANT_FLAGS = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
    }
}
