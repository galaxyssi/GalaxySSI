package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.os.CancellationSignal
import android.os.OperationCanceledException
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun removeHealthInstructionTestTables(db: SQLiteDatabase) {
    db.execSQL("DROP TABLE instruction_events"); db.execSQL("DROP TABLE clinical_instructions")
}
internal class HealthCareInstructionFixture(context: Context) : AutoCloseable {
    val documents = HealthCareDocumentFixture(context)
    val repository = HealthCareInstructionRepository(context, documents.names)
    val original: HealthOriginal
    val link: HealthCareDocumentLink
    init {
        val bytes = ByteArrayOutputStream(); val pdf = PdfDocument()
        try {
            listOf(listOf("Unrelated first page"), listOf("Synthetic follow-up", "Review the recorded visit")).forEachIndexed { index, lines ->
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(400, 500, index + 1).create())
                page.canvas.drawColor(Color.WHITE)
                lines.forEachIndexed { row, text -> page.canvas.drawText(text, 20f, 60f + row * 40,
                    Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 18f }) }
                pdf.finishPage(page)
            }
            pdf.writeTo(bytes)
        } finally { pdf.close() }
        original = documents.originals().use { it.importOriginal(UUID.randomUUID().toString(), bytes.toByteArray().inputStream(),
            "synthetic-instructions.pdf", "application/pdf", "file") }
        link = documents.repository.confirm(documents.repository.prepare(documents.snapshot().visit, original, 2, CancellationSignal()))
    }
    fun read() = repository.read(documents.issue.id, documents.visit.id, link.id, 2, CancellationSignal())
    fun create() = repository.create(read(), setOf(0, 1), UUID.randomUUID().toString()).value
    fun snapshot(id: String? = null) = repository.load(documents.issue.id, documents.visit.id, selected = id)
    override fun close() = documents.close()
}

class HealthCareInstructionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (HealthCareInstructionFixture) -> Unit) { HealthCareInstructionFixture(context).use(block) }
    private fun id() = UUID.randomUUID().toString()
    @Test fun readsTheExactPdfTextLayerAndStoresOnlyAnUnreviewedSourceDraft(): Unit = fixture { f ->
        val reading = f.read()
        assertEquals(HealthRecognition.PDF_TEXT, reading.page.recognition); assertEquals(2, reading.page.page)
        assertTrue(reading.page.lines.any { it.text.contains("Synthetic follow-up") })
        assertFalse(reading.page.lines.any { it.text.contains("Unrelated") })
        val value = f.repository.create(reading, setOf(0, 1), id()).value
        assertFalse(value.draft.reviewed); assertTrue(value.draft.fields.isEmpty())
        assertEquals(value, f.snapshot(value.id).selected)
        HealthCareStore(context, f.documents.names.care).use {
            assertEquals(f.documents.issue.actions, it.concern(f.documents.issue.id)!!.actions)
            assertTrue(it.reminders(f.documents.issue.id).isEmpty())
        }
    }
    @Test fun selectedSourcePageCannotBeSubstitutedAndCancellationDoesNotCreateDrafts(): Unit = fixture { f ->
        assertThrows(HealthCareConflict::class.java) { f.repository.read(f.documents.issue.id, f.documents.visit.id, f.link.id, 1, CancellationSignal()) }
        assertThrows(OperationCanceledException::class.java) { f.repository.read(f.documents.issue.id, f.documents.visit.id, f.link.id, 2, CancellationSignal().apply { cancel() }) }
        assertTrue(f.snapshot().page.items.isEmpty())
    }
    @Test fun editsKeepTheOriginalQuoteAndStorePagedReviewHistoryWithoutScheduling(): Unit = fixture { f ->
        val first = f.create()
        var prior = first
        repeat(32) { index ->
            val fields = HealthCareInstructionDraft().required.associateWith { field ->
                if (field == HealthCareInstructionField.NAME) HealthCareInstructionValue("Synthetic review $index", HealthCareFieldReview.TRANSCRIBED)
                else HealthCareInstructionValue(review = HealthCareFieldReview.NOT_STATED)
            }
            prior = f.repository.update(f.snapshot(first.id), HealthCareInstructionDraft(fields = fields), id()).value
        }
        assertEquals(first.source, prior.source); assertEquals(first.createdAt, prior.createdAt)
        assertTrue(prior.draft.reviewed); assertTrue(prior.draft.missing.isNotEmpty())
        HealthCareStore(context, f.documents.names.care).use {
            val page = it.instructionHistory(first.concernId, first.id)
            val older = it.instructionHistory(first.concernId, first.id, page.next!!)
            assertEquals(30, page.items.size); assertEquals(3, older.items.size); assertEquals(first, older.items.last())
            assertTrue(it.reminders(first.concernId).isEmpty()); assertEquals(f.documents.issue.stage, it.concern(first.concernId)!!.stage)
        }
    }
    @Test fun replayIsIdempotentButCannotChangeSourceOrOverwriteStaleReview(): Unit = fixture { f ->
        val reading = f.read(); val operation = id()
        val receipt = f.repository.create(reading, setOf(0), operation)
        val value = receipt.value
        HealthCareStore(context, f.documents.names.care).use { store ->
            assertEquals(receipt, store.saveInstruction(value.concernId, receipt.expectedConcern, value.encounterId, value.id, null,
                value.source, value.draft, operation, System.currentTimeMillis()))
            assertThrows(HealthCareConflict::class.java) { store.saveInstruction(value.concernId, receipt.expectedConcern, value.encounterId, value.id,
                null, value.source.copy(quote = "Different synthetic text"), value.draft, operation, System.currentTimeMillis()) }
            assertThrows(HealthCareConflict::class.java) { store.saveInstruction(value.concernId, store.concern(value.concernId)!!.revision,
                value.encounterId, value.id, value.revision, value.source.copy(quote = "Different synthetic text"), value.draft, id(), System.currentTimeMillis()) }
        }
        val old = f.snapshot(value.id)
        f.repository.update(old, value.draft, id())
        assertThrows(HealthCareConflict::class.java) { f.repository.update(old, value.draft, id()) }
    }
    @Test fun sourceInUseCannotBeUnlinkedAndDeletingDraftPreservesTheOriginal(): Unit = fixture { f ->
        val value = f.create()
        assertThrows(HealthCareSourceInUse::class.java) { f.documents.repository.remove(f.documents.snapshot(), f.link) }
        f.repository.delete(f.snapshot(value.id))
        assertTrue(f.snapshot().page.items.isEmpty())
        HealthCareStore(context, f.documents.names.care).use { assertTrue(it.instructionHistory(value.concernId, value.id).items.isEmpty()) }
        f.documents.repository.remove(f.documents.snapshot(), f.link)
        f.documents.originals().use { assertTrue(it.present(f.original)) }
    }
    @Test fun missingFileKeepsHistoricalTextButBlocksNewFieldConfirmation(): Unit = fixture { f ->
        val value = f.create()
        f.documents.originals().use { it.removeOriginalBytes(f.original) }
        val snapshot = f.snapshot(value.id)
        assertEquals(value, snapshot.selected); assertFalse(snapshot.available)
        assertThrows(HealthCareConflict::class.java) { f.repository.update(snapshot, value.draft, id()) }
        f.repository.delete(snapshot); assertTrue(f.snapshot().page.items.isEmpty())
    }
    @Test fun revokedConsentAndExpiredReadingCannotSaveAnyDraft(): Unit = fixture { f ->
        val reading = f.read()
        assertThrows(IllegalArgumentException::class.java) { f.repository.create(reading, setOf(0), id(), reading.capturedAt + 600000) }
        HealthPrivacyStore(context, f.documents.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertThrows(HealthPrivacyConflict::class.java) { f.repository.create(reading, setOf(0), id()) }
        assertThrows(HealthAccessBlocked::class.java) { f.snapshot() }
        HealthCareStore(context, f.documents.names.care).use { assertTrue(it.instructions(f.documents.issue.id, f.documents.visit.id).items.isEmpty()) }
    }
    @Test fun ignoredWriteRollsBackBothReviewHistoryAndConcernRevision(): Unit = fixture { f ->
        val reading = f.read()
        val before = f.snapshot().visit.issue
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use {
            it.execSQL("CREATE TRIGGER ignore_instruction BEFORE INSERT ON clinical_instructions BEGIN SELECT RAISE(IGNORE); END")
        }
        try {
            assertThrows(IllegalStateException::class.java) { f.repository.create(reading, setOf(0), id()) }
            assertEquals(before, f.snapshot().visit.issue); assertTrue(f.snapshot().page.items.isEmpty())
            context.openOrCreateDatabase(f.documents.names.care, 0, null).use { db -> db.rawQuery("SELECT COUNT(*) FROM instruction_events", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            } }
        } finally { context.openOrCreateDatabase(f.documents.names.care, 0, null).use { it.execSQL("DROP TRIGGER ignore_instruction") } }
    }
    @Test fun contentIsEncryptedAndChangingOwnershipIndexFailsClosed(): Unit = fixture { f ->
        val value = f.create()
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { db ->
            listOf("clinical_instructions", "instruction_events").forEach { table -> db.rawQuery("SELECT payload FROM $table", null).use {
                assertTrue(it.moveToFirst()); val raw = it.getBlob(0).toString(Charsets.ISO_8859_1)
                assertFalse(raw.contains("Synthetic follow-up")); assertFalse(raw.contains(f.original.sha256))
            } }
            db.update("clinical_instructions", ContentValues().apply { put("encounter_id", id()) }, "id=?", arrayOf(value.id))
        }
        HealthCareStore(context, f.documents.names.care).use { store -> assertThrows(IllegalStateException::class.java) { store.instruction(value.id) } }
    }
    @Test fun schemaThirteenUpgradePreservesSourceLinksWithoutInventingInstructions(): Unit = fixture { f ->
        val before = f.snapshot().visit.issue
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { removeHealthInstructionTestTables(it); it.version = 13 }
        assertEquals(before, f.snapshot().visit.issue); assertTrue(f.snapshot().page.items.isEmpty())
        assertEquals(f.link, f.documents.snapshot().items.single().link)
        f.create()
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { assertEquals(15, it.version) }
    }
    @Test fun visitDeletionPurgesDraftsAndHistory(): Unit = fixture { f ->
        val value = f.create()
        HealthCareStore(context, f.documents.names.care).use { store ->
            store.deleteEncounter(value.concernId, store.concern(value.concernId)!!.revision, value.encounterId, f.documents.visit.revision, System.currentTimeMillis())
            assertNull(store.instruction(value.id)); assertTrue(store.instructionHistory(value.concernId, value.id).items.isEmpty())
        }
    }
    @Test fun currentDraftsPageWithoutDuplicatesAndRejectStaleContinuations(): Unit = fixture { f ->
        val first = f.create()
        HealthCareStore(context, f.documents.names.care).use { store -> repeat(31) {
            store.saveInstruction(first.concernId, store.concern(first.concernId)!!.revision, first.encounterId, id(), null,
                first.source, first.draft, id(), System.currentTimeMillis())
        } }
        val head = f.snapshot()
        val tail = f.repository.load(first.concernId, first.encounterId, head.page.next!!, head.visit.issue.revision)
        assertEquals(30, head.page.items.size); assertEquals(2, tail.page.items.size)
        assertEquals(32, (head.page.items + tail.page.items).map { it.id }.distinct().size)
        f.repository.update(f.snapshot(first.id), first.draft, id())
        assertThrows(HealthCareConflict::class.java) { f.repository.load(first.concernId, first.encounterId, head.page.next!!, head.visit.issue.revision) }
    }
    @Test fun anotherVisitCannotReadOrEditAnInstructionFromThisVisit(): Unit = fixture { f ->
        val value = f.create()
        val other = HealthCareStore(context, f.documents.names.care).use { store ->
            store.saveEncounter(value.concernId, store.concern(value.concernId)!!.revision, id(), null,
                HealthCareEncounterDraft("Separate synthetic visit"), id(), System.currentTimeMillis()).encounter
        }
        assertThrows(HealthCareConflict::class.java) { f.repository.load(value.concernId, other.id, selected = value.id) }
        assertThrows(HealthCareConflict::class.java) { f.repository.read(value.concernId, other.id, f.link.id, 2, CancellationSignal()) }
        assertEquals(value, f.snapshot(value.id).selected)
    }
    @Test fun retainedImageUsesLocalOcrAndKeepsItsPageAndExactRecognizedQuote(): Unit = fixture { f ->
        val bitmap = Bitmap.createBitmap(1200, 500, Bitmap.Config.ARGB_8888)
        val bytes = ByteArrayOutputStream()
        try {
            bitmap.eraseColor(Color.WHITE)
            Canvas(bitmap).drawText("合成测试：复查记录", 40f, 160f,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 64f })
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes))
        } finally { HealthOriginalThumbnail.clear(bitmap) }
        val original = f.documents.originals().use { it.importOriginal(id(), bytes.toByteArray().inputStream(), "synthetic-instructions.png", "image/png", "file") }
        val link = f.documents.repository.confirm(f.documents.repository.prepare(f.documents.snapshot().visit, original, 1, CancellationSignal()))
        val read = f.repository.read(f.documents.issue.id, f.documents.visit.id, link.id, 1, CancellationSignal())
        assertEquals(HealthRecognition.OCR, read.page.recognition); assertEquals(1, read.pageCount)
        val line = read.page.lines.indexOfFirst { it.text.contains("复查") }
        assertTrue("Local OCR must recognize the rendered synthetic image", line >= 0)
        val saved = f.repository.create(read, setOf(line), id()).value
        assertEquals(read.page.lines[line].text, saved.source.quote); assertEquals(1, saved.source.original.page)
        assertFalse(saved.draft.reviewed)
    }
}
