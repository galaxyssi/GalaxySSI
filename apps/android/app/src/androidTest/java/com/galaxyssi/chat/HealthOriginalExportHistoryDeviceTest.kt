package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import android.view.View
import android.widget.TextView
import androidx.core.content.FileProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOriginalExportHistoryDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun olderHistoryReopensTheExactManifestAndVerifiesAnExplicitDocumentSave() {
        assumeFalse("Original export history UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val token = UUID.randomUUID().toString()
        val names = HealthOverviewDatabases(token)
        val fixtureDir = File(context.cacheDir, "health-original-export-test-$token")
        val output = File(context.cacheDir, "health-backups/original-history-$token.zip")
        try {
            HealthExportShare.openOriginals(context, token).use { originals ->
                val store = HealthExportShare.originalLibrary(context, originals, token)
                val original = originals.importOriginal(UUID.randomUUID().toString(), "synthetic-report".byteInputStream(),
                    "synthetic-report.bin", "application/octet-stream", "file")
                fun prepare(): HealthOriginalExportSession {
                    val id = store.createSelection().id
                    store.select(id, listOf(original.id), true)
                    return store.prepare(id)
                }
                val oldest = prepare()
                val queued = store.queue(oldest.id)
                assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthOriginalArchive.generate(originals, store, oldest.id, queued.dispatch))
                val generated = requireNotNull(store.session(oldest.id))
                SystemClock.sleep(5)
                repeat(30) { prepare() }
                assertTrue(store.history().take(30).none { it.id == oldest.id })
                val target = FileProvider.getUriForFile(context, "${context.packageName}.files", output.apply { parentFile!!.mkdirs(); check(createNewFile()) })
                val action = IntentFilter(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    addDataType("application/zip")
                }
                val intent = Intent(context, HealthOriginalExportHistoryActivity::class.java).putExtra("health_original_export_test_id", token)
                val row = "health-original-history-${oldest.id}"
                ActivityScenario.launch<HealthOriginalExportHistoryActivity>(intent).use { scenario ->
                    fun historyClick(tag: String) {
                        await("Missing history action: $tag") {
                            var clicked = false
                            scenario.onActivity { clicked = it.window.decorView.findViewWithTag<View>(tag)?.performClick() == true }
                            clicked
                        }
                    }
                    fun openOlder(): Activity {
                        val monitor = instrumentation.addMonitor(HealthOriginalExportActivity::class.java.name, null, false)
                        return try {
                            historyClick(row)
                            requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000))
                        } finally { instrumentation.removeMonitor(monitor) }
                    }
                    fun clickSave(detail: Activity) {
                        await("Missing ZIP save action") {
                            var clicked = false
                            instrumentation.runOnMainSync {
                                clicked = detail.window.decorView.findViewWithTag<View>("health-export-save")?.performClick() == true
                            }
                            clicked
                        }
                    }
                    historyClick("health-original-history-next")
                    scenario.recreate()
                    val detail = openOlder()
                    val cancel = instrumentation.addMonitor(action, Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null), true)
                    try {
                        clickSave(detail)
                        await("System document picker not requested") { cancel.hits == 1 }
                        instrumentation.waitForIdleSync()
                        assertEquals(generated, store.session(oldest.id))
                        assertEquals(0L, output.length())
                    } finally { instrumentation.removeMonitor(cancel) }
                    val save = instrumentation.addMonitor(action, Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(target)), true)
                    try {
                        clickSave(detail)
                        await("No verified save receipt") { store.session(oldest.id)?.verifiedSaveAt?.let { it > 0 } == true }
                        assertEquals(1, save.hits)
                        assertArrayEquals(store.input(generated).use { it.readBytes() }, output.readBytes())
                    } finally { instrumentation.removeMonitor(save) }
                    instrumentation.runOnMainSync { detail.finish() }
                    check(store.file(generated).delete())
                    val reopened = openOlder()
                    await("Verified save not shown in reopened history") {
                        var matched = false
                        instrumentation.runOnMainSync {
                            matched = reopened.window.decorView.findViewWithTag<TextView>("health-export-state")?.text ==
                                context.getString(R.string.health_library_saved) &&
                                reopened.window.decorView.findViewWithTag<View>("health-export-save") == null
                        }
                        matched
                    }
                    instrumentation.runOnMainSync { reopened.finish() }
                    assertTrue(originals.present(original))
                    assertEquals(HealthOriginalExportState.SAVED, store.session(oldest.id)?.state)
                }
            }
        } finally {
            output.delete()
            fixtureDir.deleteRecursively()
            clearHealthOverviewFixture(context, names)
        }
    }

    private fun await(message: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 12_000
        do { if (predicate()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < deadline)
        fail(message)
    }
}
