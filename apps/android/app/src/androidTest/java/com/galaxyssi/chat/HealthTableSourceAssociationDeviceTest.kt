package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.zip.ZipInputStream
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthTableSourceAssociationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()

    @Test fun secondCsvShowsTheExistingMeasurementAndExportsItsOwnExactSourceBytes() {
        assumeFalse("Visible original acceptance requires an unlocked device", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(id())
        val exportDb = "health-secondary-export-${names.fixture}.db"
        val exportRoot = File(context.cacheDir, exportDb.removeSuffix(".db"))
        val primaryBytes = "time,systolic,diastolic,unit,note\n2026-09-01T08:10:00Z,124,82,mmHg,Primary\n".toByteArray()
        val secondaryBytes = "time,systolic,diastolic,unit,note\n2026-09-01T08:10:00Z,124,82,mmHg,Secondary\n".toByteArray()
        try {
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
                val primary = originals.importOriginal(id(), primaryBytes.inputStream(), "first.csv", "text/csv", "file")
                val secondary = originals.importOriginal(id(), secondaryBytes.inputStream(), "second.csv", "text/csv", "file")
                HealthTableStore(context, names.records).use { tables ->
                    fun import(file: HealthOriginal, link: Boolean): String {
                        val staged = HealthTableImport.stage(originals, file, id(), tables)
                        tables.mapping(staged.id, staged.mappingRevision, staged.mapping.copy(zone = "UTC"), true)
                        while (tables.step(staged.id)) Unit
                        tables.confirmSave(staged.id, tables.batch(staged.id)!!.mappingRevision, linkDuplicates = link)
                        while (tables.step(staged.id)) Unit
                        return staged.id
                    }
                    import(primary, false)
                    val secondBatch = import(secondary, true)
                    assertEquals(1L, tables.counts(secondBatch)[HealthTableRowState.LINKED])
                }
                HealthRecordStore(context, names.records).use { records ->
                    assertEquals(1L, records.count())
                    val record = records.originalPage(primary.id).records.single()
                    val intent = Intent(context, HealthCaptureActivity::class.java).putExtra("original", secondary.id)
                        .putExtra("health_review_test_id", names.fixture)
                    ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                        val deadline = SystemClock.elapsedRealtime() + 12_000
                        var visible = false
                        do {
                            scenario.onActivity { activity ->
                                val labels = views(activity.window.decorView).filterIsInstance<TextView>().map { it.text.toString() }
                                visible = context.getString(R.string.health_linked_records) in labels &&
                                    context.getString(R.string.health_export_linked_records) in labels &&
                                    healthDisplayValue(record.draft) in labels
                            }
                            if (!visible) SystemClock.sleep(50)
                        } while (!visible && SystemClock.elapsedRealtime() < deadline)
                        assertTrue("Original detail did not show the linked measurement", visible)
                    }
                    HealthRecordExportStore(context, exportDb, exportRoot).use { exports ->
                        val requested = exports.create(HealthRecordExportScope(originalId = secondary.id,
                            format = HealthRecordExportFormat.JSON, uploadedOriginals = true))
                        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.prepare(records, originals, exports, requested.id, requested.dispatch))
                        assertEquals(1L, exports.session(requested.id)!!.count)
                        val queued = exports.queue(requested.id)
                        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.generate(exports, queued.id, queued.dispatch, originals = originals))
                        val result = requireNotNull(exports.session(requested.id))
                        val bytes = ByteArrayOutputStream().use { HealthRecordExportPipeline.save(exports, result, it); it.toByteArray() }
                        val entries = ZipInputStream(bytes.inputStream()).use { zip -> buildMap {
                            while (true) { val entry = zip.nextEntry ?: break; put(entry.name, zip.readBytes()); zip.closeEntry() }
                        } }
                        assertArrayEquals(secondaryBytes, entries[HealthOriginalArchiveNames.entry(secondary)])
                        assertFalse(HealthOriginalArchiveNames.entry(primary) in entries)
                        val json = JSONObject(entries.getValue("records.json").toString(Charsets.UTF_8))
                        val exported = HealthObservation.from(json.getJSONArray("records").getJSONObject(0))
                        assertEquals(record.id, exported.id)
                        assertEquals(secondary.id, exported.draft.evidence?.originalId)
                        assertEquals(secondary.sha256, exported.draft.evidence?.sha256)
                        assertEquals(primary.id, records.record(record.id)?.draft?.evidence?.originalId)
                    }
                }
            }
        } finally {
            primaryBytes.fill(0); secondaryBytes.fill(0)
            context.deleteDatabase(exportDb); exportRoot.deleteRecursively()
            clearHealthOverviewFixture(context, names)
        }
    }

    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
}
