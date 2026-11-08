package com.galaxyssi.chat

import android.content.Context
import android.os.CancellationSignal

internal data class HealthCareInstructionSnapshot(val visit: HealthCareEncounterSnapshot, val page: HealthCareInstructionPage,
    val selected: HealthCareInstruction? = null, val available: Boolean = false, val history: HealthCareInstructionPage? = null)
internal data class HealthCareInstructionReading(val visit: HealthCareEncounterSnapshot, val document: HealthCareDocumentLink,
    val original: HealthOriginal, val page: HealthOcrPage, val pageCount: Int, val capturedAt: Long)

internal class HealthCareInstructionRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    private val encounters = HealthCareEncounterRepository(context, names)
    private val documents = HealthCareDocumentRepository(context, names)
    private fun originals() = HealthExportShare.openOriginals(context, names.fixture)
    fun load(id: String, encounterId: String, before: Int = Int.MAX_VALUE, expectedRevision: Int? = null,
        selected: String? = null, historyBefore: Int? = null): HealthCareInstructionSnapshot {
        val visit = encounters.load(id, selectedId = encounterId)
        if (before != Int.MAX_VALUE && expectedRevision != visit.issue.revision) throw HealthCareConflict()
        val result = HealthCareStore(context, names.care).use { store ->
            val value = selected?.let { store.instruction(it)?.takeIf { value -> value.concernId == id && value.encounterId == encounterId } ?: throw HealthCareConflict() }
            val available = value?.let { instruction -> originals().use { originals ->
                val link = store.encounterDocument(instruction.source.documentId)
                val original = originals.original(instruction.source.original.originalId)
                link != null && link.concernId == id && link.encounterId == encounterId && original != null &&
                    instruction.source.original.matches(original) && originals.present(original)
            } } == true
            HealthCareInstructionSnapshot(visit, if (selected == null) store.instructions(id, encounterId, before) else HealthCareInstructionPage(emptyList(), null),
                value, available, if (selected != null && historyBefore != null) store.instructionHistory(id, selected, historyBefore) else null)
        }
        encounters.commit(visit) { }; return result
    }
    fun read(id: String, encounterId: String, documentId: String, page: Int, signal: CancellationSignal): HealthCareInstructionReading {
        val visit = encounters.load(id, selectedId = encounterId)
        val link = HealthCareStore(context, names.care).use { it.encounterDocument(documentId) } ?: throw HealthCareConflict()
        if (link.concernId != id || link.encounterId != encounterId || link.source.page != null && link.source.page != page) throw HealthCareConflict()
        val original = originals().use { it.original(link.source.originalId) } ?: throw HealthCareConflict()
        require(link.source.matches(original))
        val verified = documents.prepare(visit, original, page, signal)
        val recognized = originals().use { store ->
            signal.throwIfCanceled()
            HealthOcrEngine().use { engine ->
                if (original.mime.startsWith("image/")) engine.image(store, original)
                else {
                    require(original.mime == "application/pdf")
                    HealthPdfTextReader.open(context, store, original, signal::throwIfCanceled).use { pdf ->
                        var result: HealthOcrPage? = null
                        engine.pdf(store, original, page - 1, signal::throwIfCanceled, { require(it == verified.source.pageCount) },
                            { result = it }, pdf, lastPageExclusive = page)
                        result ?: throw HealthImportFailure("page_empty")
                    }
                }
            }
        }
        signal.throwIfCanceled()
        require(recognized.page == page)
        originals().use { if (it.original(original.id) != original || !it.present(original)) throw HealthCareConflict() }
        encounters.commit(visit) { }
        return HealthCareInstructionReading(visit, link, original, recognized, verified.source.pageCount!!, System.currentTimeMillis())
    }
    fun create(reading: HealthCareInstructionReading, selected: Set<Int>, operationId: String, now: Long = System.currentTimeMillis()): HealthCareInstructionReceipt {
        require(now >= reading.capturedAt && now - reading.capturedAt < 600_000L)
        val source = HealthCareInstructionSource.select(reading.document, reading.page, reading.pageCount, selected)
        return save(reading.visit, operationId, null, source, HealthCareInstructionDraft(), operationId, now)
    }
    fun update(snapshot: HealthCareInstructionSnapshot, draft: HealthCareInstructionDraft, operationId: String, now: Long = System.currentTimeMillis()): HealthCareInstructionReceipt {
        val before = snapshot.selected ?: throw HealthCareConflict()
        return save(snapshot.visit, before.id, before.revision, before.source, draft, operationId, now)
    }
    private fun save(visit: HealthCareEncounterSnapshot, id: String, expected: Int?, source: HealthCareInstructionSource,
        draft: HealthCareInstructionDraft, operationId: String, now: Long) = encounters.commit(visit) { care ->
        val original = originals().use { store -> store.original(source.original.originalId)?.takeIf { source.original.matches(it) && store.present(it) } }
        if (original == null) throw HealthCareConflict()
        care.saveInstruction(visit.issue.id, visit.issue.revision, visit.selected!!.id, id, expected, source, draft, operationId, now)
    }
    fun delete(snapshot: HealthCareInstructionSnapshot) = encounters.commit(snapshot.visit) { care ->
        val value = snapshot.selected ?: throw HealthCareConflict()
        care.deleteInstruction(value.concernId, snapshot.visit.issue.revision, value.id, value.revision, System.currentTimeMillis())
    }
}
