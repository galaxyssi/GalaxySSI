package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.CancellationSignal
import java.io.OutputStream
import java.util.UUID

internal data class HealthCareDocumentItem(val link: HealthCareDocumentLink, val original: HealthOriginal?, val available: Boolean)
internal data class HealthCareDocumentSnapshot(val visit: HealthCareEncounterSnapshot, val items: List<HealthCareDocumentItem>, val next: Int?)
internal data class HealthCareDocumentCandidate(val visit: HealthCareEncounterSnapshot, val original: HealthOriginal,
    val source: HealthCareDocumentRef, val operationId: String, val preparedAt: Long)
internal data class HealthCareDocumentRaster(val bitmap: Bitmap, val pageCount: Int)

internal class HealthCareDocumentRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    private val encounters = HealthCareEncounterRepository(context, names)
    private fun originals() = HealthExportShare.openOriginals(context, names.fixture)
    fun load(id: String, encounterId: String, before: Int = Int.MAX_VALUE, expectedRevision: Int? = null): HealthCareDocumentSnapshot {
        val visit = encounters.load(id, selectedId = encounterId)
        if (before != Int.MAX_VALUE && visit.issue.revision != expectedRevision) throw HealthCareConflict()
        val page = HealthCareStore(context, names.care).use { it.encounterDocuments(id, encounterId, before) }
        val items = originals().use { originals -> page.items.map { link ->
            val current = originals.original(link.source.originalId)
            HealthCareDocumentItem(link, current?.takeIf(link.source::matches), current != null && link.source.matches(current) && originals.present(current))
        } }
        encounters.commit(visit) { }
        return HealthCareDocumentSnapshot(visit, items, page.next)
    }
    fun library(visit: HealthCareEncounterSnapshot, before: Pair<Long, String>?, signal: CancellationSignal): HealthLibraryPage {
        encounters.commit(visit) { }
        val result = originals().use { it.library(HealthLibraryFilter(), before, signal) }
        signal.throwIfCanceled(); encounters.commit(visit) { }
        return result
    }
    private fun current(store: HealthOriginalStore, original: HealthOriginal) {
        if (original.reviewOnly || store.original(original.id) != original || !store.present(original)) throw HealthCareConflict()
    }
    private fun pageCount(store: HealthOriginalStore, original: HealthOriginal): Int {
        if (original.mime.startsWith("image/")) return 1
        require(original.mime == "application/pdf")
        val descriptor = store.descriptor(original)
        val renderer = try { PdfRenderer(descriptor) } catch (failure: Throwable) { descriptor.close(); throw failure }
        return renderer.use { it.pageCount.also { count -> require(count > 0) } }
    }
    fun raster(visit: HealthCareEncounterSnapshot, original: HealthOriginal, page: Int, signal: CancellationSignal): HealthCareDocumentRaster {
        encounters.commit(visit) { }
        return originals().use { store ->
            current(store, original); signal.throwIfCanceled()
            val count = pageCount(store, original)
            require(page in 1..count)
            val bitmap = HealthReviewRaster.load(store, original, page)
            try {
                signal.throwIfCanceled(); current(store, original); encounters.commit(visit) { }
                HealthCareDocumentRaster(bitmap, count)
            } catch (failure: Throwable) { HealthOriginalThumbnail.clear(bitmap); throw failure }
        }
    }
    fun prepare(visit: HealthCareEncounterSnapshot, original: HealthOriginal, page: Int?, signal: CancellationSignal): HealthCareDocumentCandidate {
        encounters.commit(visit) { }
        val source = originals().use { store ->
            current(store, original)
            val count = page?.let { pageCount(store, original).also { count -> require(it in 1..count) } }
            // Verify the complete encrypted original without creating a plaintext file or retaining its bytes.
            store.copyVerified(original, object : OutputStream() {
                override fun write(value: Int) = Unit
                override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit
            }, signal::throwIfCanceled)
            current(store, original)
            HealthCareDocumentRef.from(original, page, count)
        }
        signal.throwIfCanceled(); encounters.commit(visit) { }
        return HealthCareDocumentCandidate(visit, original, source, UUID.randomUUID().toString(), System.currentTimeMillis())
    }
    fun confirm(candidate: HealthCareDocumentCandidate, now: Long = System.currentTimeMillis()): HealthCareDocumentLink {
        require(now >= candidate.preparedAt && now - candidate.preparedAt < 600_000L)
        val entry = candidate.visit.selected ?: throw HealthCareConflict()
        require(candidate.source.matches(candidate.original))
        return encounters.commit(candidate.visit) { care -> originals().use { store ->
            current(store, candidate.original)
            care.linkEncounterDocument(candidate.visit.issue.id, candidate.visit.issue.revision, entry.id, entry.revision,
                candidate.source, candidate.operationId, now)
        } }
    }
    fun remove(snapshot: HealthCareDocumentSnapshot, link: HealthCareDocumentLink) = encounters.commit(snapshot.visit) { care ->
        require(snapshot.visit.selected?.id == link.encounterId && link.concernId == snapshot.visit.issue.id)
        care.unlinkEncounterDocument(link.concernId, snapshot.visit.issue.revision, link.id, link.revision, System.currentTimeMillis())
    }
}
