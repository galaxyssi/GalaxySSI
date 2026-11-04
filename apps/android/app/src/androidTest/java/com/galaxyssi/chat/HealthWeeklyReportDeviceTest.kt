package com.galaxyssi.chat

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthWeeklyReportDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val scope = HealthWeeklyScope(LocalDate.of(2024, 11, 3), ZoneId.of("UTC"), setOf(HealthMetric.SLEEP_DURATION), records = true)
    private fun fixture(test: (HealthRecordStore, String, String) -> Unit) {
        val id = UUID.randomUUID()
        val database = "health-weekly-test-$id.db"; val privacy = "health-privacy-test-$id.db"
        try { HealthRecordStore(context, database).use { test(it, database, privacy) } }
        finally { context.deleteDatabase(database); context.deleteDatabase(privacy) }
    }
    private fun add(store: HealthRecordStore, offset: Int, metric: HealthMetric = HealthMetric.SLEEP_DURATION, value: String = "6",
        note: String = "PRIVATE_NOTE", time: Long = scope.from + offset * 1000L): HealthObservation =
        (store.save(HealthDraft(metric, metric.requiredFields.associateWith { value }, metric.units.first(), time, note = note)) as HealthSaveResult.Saved).record

    @Test fun weeklyAndBaselineWindowsExcludeDraftDeletedOutOfScopeAndOtherPersonRows() = fixture { store, name, _ ->
        val included = add(store, 1)
        val foreign = add(store, 2)
        val plain = foreign.copy(profileId = "different-person").json().toString().toByteArray()
        try { store.tableDatabase.update("observations", ContentValues().apply {
            put("payload", AgentStorageCipher.encryptBinary(plain, "$name|health|${foreign.id}|${foreign.revision}".toByteArray()))
        }, "id=?", arrayOf(foreign.id)) } finally { plain.fill(0) }
        val deleted = add(store, 3); store.delete(deleted.id, deleted.revision)
        add(store, 4, HealthMetric.STEPS, "7000")
        add(store, 5, time = scope.until)
        add(store, 6, time = scope.from - 1000)
        store.saveDraft(HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to "8"), measuredAt = scope.from + 6000))
        val report = HealthWeeklyRepository.calculate(store, scope)
        assertEquals(1L, report.recordCount)
        assertEquals(1L, report.sleep!!.baseline.records)
        assertEquals(listOf(included.id), HealthWeeklyRepository.page(store, report.stamp, null).records.map { it.id })
    }
    @Test fun metricVersionRejectsEditsAndNewBaselineRecordsButNotUnrelatedMetrics() = fixture { store, _, _ ->
        val row = add(store, 1)
        val original = HealthWeeklyRepository.calculate(store, scope)
        add(store, 2, HealthMetric.STEPS, "7000")
        assertEquals(original, HealthWeeklyRepository.calculate(store, scope, original.stamp))
        store.save(row.editable().copy(values = mapOf("sleep_duration" to "7")))
        assertTrue(runCatching { HealthWeeklyRepository.calculate(store, scope, original.stamp) }.exceptionOrNull() is HealthWeeklyChanged)
        val updated = HealthWeeklyRepository.calculate(store, scope)
        add(store, 4, time = scope.from - 4000)
        assertTrue(runCatching { HealthWeeklyRepository.page(store, updated.stamp, null) }.exceptionOrNull() is HealthWeeklyChanged)
    }
    @Test fun rawPreviewPagesAllRecordsWithoutNotesOrDuplicates() = fixture { store, _, _ ->
        val expected = (1..65).map { add(store, it).id }.toSet()
        val report = HealthWeeklyRepository.calculate(store, scope)
        val ids = hashSetOf<String>(); var after: HealthPageCursor? = null
        do {
            val page = HealthWeeklyRepository.page(store, report.stamp, after)
            assertTrue(page.records.size <= 30)
            page.records.forEach { assertTrue(ids.add(it.id)); assertFalse(it.toString().contains("PRIVATE_NOTE")) }
            after = page.next
        } while (after != null)
        assertEquals(expected, ids)
    }
    @Test fun summaryAndPdfAccessRespectPrivacyWithScopedAudit() = fixture { store, _, privacy ->
        add(store, 1)
        HealthPrivacyStore(context, privacy).use { access ->
            access.change(HealthPrivacyOption.CONFIRMED_METRICS, false, access.policy().version)
            var ran = false
            assertTrue(runCatching { access.track(HealthAccessScope.weekly(scope)) { ran = true } }.exceptionOrNull() is HealthAccessBlocked)
            assertFalse(ran)
            access.change(HealthPrivacyOption.CONFIRMED_METRICS, true, access.policy().version)
            val report = access.track(HealthAccessScope.weekly(scope)) { HealthWeeklyRepository.calculate(store, scope) }
            access.track(HealthAccessScope.weekly(scope, save = true)) {
                HealthWeeklyPdf.write(context, store, report, ByteArrayOutputStream())
            }
            val save = access.page().entries.single { it.scope.purpose == HealthAccessPurpose.SAVE_WEEKLY_REPORT }
            assertEquals(HealthAccessFormat.PDF, save.scope.format)
            assertEquals(HealthAccessOutcome.COMPLETE, save.outcome)
            assertEquals(scope.baselineScope().from, save.scope.baselineFrom)
            assertTrue(save.scope.reportRecords)
        }
    }
    @Test fun realPdfRendersMultipleNonblankPagesAndKeepsSectionScope() = fixture { store, _, _ ->
        repeat(65) { add(store, it + 1) }
        val report = HealthWeeklyRepository.calculate(store, scope)
        val file = File.createTempFile("health-weekly-test-", ".pdf", context.cacheDir)
        try {
            file.outputStream().use { HealthWeeklyPdf.write(context, store, report, it) }
            val header = ByteArray(5)
            assertEquals(5, file.inputStream().use { it.read(header) })
            assertEquals("%PDF-", header.toString(Charsets.US_ASCII))
            PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
                assertTrue(renderer.pageCount > 1)
                renderer.openPage(0).use { page ->
                    val bitmap = Bitmap.createBitmap(595, 842, Bitmap.Config.ARGB_8888)
                    try {
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        var ink = 0
                        for (x in 35..550 step 3) for (y in 60..660 step 3) if (bitmap.getPixel(x, y) != Color.WHITE) ink++
                        assertTrue(ink > 150)
                    } finally { bitmap.recycle() }
                }
            }
        } finally { file.delete() }
    }
    @Test fun changedDataCannotWriteAnyPdfBytes() = fixture { store, _, _ ->
        add(store, 1)
        val report = HealthWeeklyRepository.calculate(store, scope)
        add(store, 2)
        val output = ByteArrayOutputStream()
        assertTrue(runCatching { HealthWeeklyPdf.write(context, store, report, output) }.exceptionOrNull() is HealthWeeklyChanged)
        assertEquals(0, output.size())
    }
}
