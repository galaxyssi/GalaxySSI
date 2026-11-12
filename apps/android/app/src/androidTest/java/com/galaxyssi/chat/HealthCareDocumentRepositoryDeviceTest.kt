package com.galaxyssi.chat

import android.content.Context
import android.graphics.Color
import android.graphics.pdf.PdfDocument
import android.os.CancellationSignal
import android.os.OperationCanceledException
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal class HealthCareDocumentFixture(val context: Context) : AutoCloseable {
    val names = HealthOverviewDatabases(UUID.randomUUID().toString())
    val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
    val visit = HealthCareStore(context, names.care).use { it.saveEncounter(issue.id, it.concern(issue.id)!!.revision,
        UUID.randomUUID().toString(), null, HealthCareEncounterDraft("Synthetic visit"), UUID.randomUUID().toString(), System.currentTimeMillis()).encounter }
    val repository = HealthCareDocumentRepository(context, names)
    fun originals() = HealthExportShare.openOriginals(context, names.fixture)
    fun snapshot() = repository.load(issue.id, visit.id)
    fun pdf(): HealthOriginal {
        val bytes = ByteArrayOutputStream()
        val pdf = PdfDocument()
        try {
            listOf(Color.RED, Color.BLUE).forEachIndexed { index, color ->
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(250, 380, index + 1).create())
                page.canvas.drawColor(color); pdf.finishPage(page)
            }
            pdf.writeTo(bytes)
        } finally { pdf.close() }
        return originals().use { it.importOriginal(UUID.randomUUID().toString(), bytes.toByteArray().inputStream(),
            "synthetic-visit.pdf", "application/pdf", "file") }
    }
    override fun close() { context.deleteDatabase(names.care); clearHealthOverviewFixture(context, names) }
}

class HealthCareDocumentRepositoryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (HealthCareDocumentFixture) -> Unit) { HealthCareDocumentFixture(context).use(block) }
    @Test fun selectedPageIsVerifiedSavedReopenedAndRemovedWithoutDeletingTheOriginal(): Unit = fixture { f ->
        val original = f.pdf(); val before = f.snapshot()
        val raster = f.repository.raster(before.visit, original, 2, CancellationSignal())
        try { assertEquals(2, raster.pageCount); assertEquals(Color.BLUE, raster.bitmap.getPixel(10, 10)) }
        finally { HealthOriginalThumbnail.clear(raster.bitmap) }
        val candidate = f.repository.prepare(before.visit, original, 2, CancellationSignal())
        val saved = f.repository.confirm(candidate)
        assertEquals(2, saved.source.page); assertEquals(2, saved.source.pageCount)
        val current = f.snapshot(); assertEquals(saved, current.items.single().link); assertTrue(current.items.single().available)
        f.repository.remove(current, saved)
        assertTrue(f.snapshot().items.isEmpty())
        f.originals().use { assertTrue(it.present(original)); assertEquals(original, it.original(original.id)) }
    }
    @Test fun outOfRangePagesAndCancelledPreparationCannotBeSaved(): Unit = fixture { f ->
        val original = f.pdf(); val before = f.snapshot()
        assertThrows(IllegalArgumentException::class.java) { f.repository.raster(before.visit, original, 3, CancellationSignal()) }
        assertThrows(IllegalArgumentException::class.java) { f.repository.prepare(before.visit, original, 3, CancellationSignal()) }
        assertThrows(OperationCanceledException::class.java) {
            f.repository.prepare(before.visit, original, null, CancellationSignal().apply { cancel() })
        }
        assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun missingOriginalIsShownAsUnavailableAndCannotBeConfirmed(): Unit = fixture { f ->
        val original = f.pdf()
        val saved = f.repository.confirm(f.repository.prepare(f.snapshot().visit, original, null, CancellationSignal()))
        val candidate = f.repository.prepare(f.snapshot().visit, original, 1, CancellationSignal())
        f.originals().use { assertTrue(it.removeOriginalBytes(original)) }
        assertFalse(f.snapshot().items.single().available)
        assertThrows(HealthCareConflict::class.java) { f.repository.confirm(candidate) }
        f.repository.remove(f.snapshot(), saved); assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun corruptedEncryptedOriginalFailsVerificationWithoutPersistingALink(): Unit = fixture { f ->
        val original = f.pdf(); val before = f.snapshot()
        val file = File(f.names.originalRoot(context), original.relativePath)
        java.io.RandomAccessFile(file, "rw").use { it.seek(it.length() - 1); val byte = it.read(); it.seek(it.length() - 1); it.write(byte xor 0xff) }
        assertTrue(runCatching { f.repository.prepare(before.visit, original, null, CancellationSignal()) }.isFailure)
        assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun permissionOffOnInvalidatesPreparedSourceAndBlockedReads(): Unit = fixture { f ->
        val original = f.pdf()
        val candidate = f.repository.prepare(f.snapshot().visit, original, null, CancellationSignal())
        HealthPrivacyStore(context, f.names.privacy).use {
            it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version)
            assertThrows(HealthAccessBlocked::class.java) { f.snapshot() }
            assertThrows(HealthPrivacyConflict::class.java) { f.repository.confirm(candidate) }
            it.change(HealthPrivacyOption.PROFILE_CONTEXT, true, it.policy().version)
        }
        assertThrows(HealthPrivacyConflict::class.java) { f.repository.confirm(candidate) }
        assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun changedVisitOrMeasurementAndExpiredConfirmationCannotAttach(): Unit = fixture { f ->
        val original = f.pdf()
        val candidate = f.repository.prepare(f.snapshot().visit, original, null, CancellationSignal())
        assertThrows(IllegalArgumentException::class.java) { f.repository.confirm(candidate, candidate.preparedAt + 600000) }
        assertThrows(IllegalArgumentException::class.java) { f.repository.confirm(candidate, candidate.preparedAt - 1) }
        HealthRecordStore(context, f.names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
            mapOf("glucose" to "6.2"), "mmol/L", System.currentTimeMillis())) }
        assertThrows(HealthCareConflict::class.java) { f.repository.confirm(candidate) }
        val fresh = f.repository.prepare(f.snapshot().visit, original, null, CancellationSignal())
        HealthCareStore(context, f.names.care).use { store ->
            store.saveEncounter(f.issue.id, store.concern(f.issue.id)!!.revision, f.visit.id, f.visit.revision,
                f.visit.details.copy(note = "Updated synthetic visit"), UUID.randomUUID().toString(), System.currentTimeMillis())
        }
        assertThrows(HealthCareConflict::class.java) { f.repository.confirm(fresh) }
        assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun privateReviewOriginalIsNotSelectableAndCannotBeLinked(): Unit = fixture { f ->
        val original = f.originals().use { store ->
            val id = UUID.randomUUID().toString()
            store.createJob(HealthImportJob(id, "content://fixture/private", System.currentTimeMillis(), keepOriginal = false))
            store.importOriginal(id, "synthetic private review".byteInputStream(), "private.txt", "text/plain", "file")
        }
        assertTrue(original.reviewOnly)
        val before = f.snapshot()
        assertTrue(f.repository.library(before.visit, null, CancellationSignal()).originals.none { it.id == original.id })
        assertThrows(HealthCareConflict::class.java) { f.repository.prepare(before.visit, original, null, CancellationSignal()) }
    }
    @Test fun libraryAndLinksArePagedAndChangedLinkCursorIsRejected(): Unit = fixture { f ->
        val originals = f.originals().use { store -> (1..35).map { index ->
            store.importOriginal(UUID.randomUUID().toString(), "Synthetic source $index".byteInputStream(), "fixture-$index.txt", "text/plain", "file")
        } }
        var before = f.snapshot()
        val first = f.repository.library(before.visit, null, CancellationSignal())
        val second = f.repository.library(before.visit, first.next, CancellationSignal())
        assertEquals(30, first.originals.size)
        assertEquals(originals.map { it.id }.toSet(), (first.originals + second.originals).map { it.id }.toSet()); assertNull(second.next)
        originals.forEach { original ->
            f.repository.confirm(f.repository.prepare(before.visit, original, null, CancellationSignal())); before = f.snapshot()
        }
        val links = f.snapshot()
        assertEquals(30, links.items.size)
        val older = f.repository.load(f.issue.id, f.visit.id, links.next!!, links.visit.issue.revision)
        assertEquals(5, older.items.size); assertNull(older.next)
        f.repository.remove(links, links.items.first().link)
        assertThrows(HealthCareConflict::class.java) { f.repository.load(f.issue.id, f.visit.id, links.next, links.visit.issue.revision) }
    }
}
