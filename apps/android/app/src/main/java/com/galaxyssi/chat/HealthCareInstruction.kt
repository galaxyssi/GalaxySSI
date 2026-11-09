package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthCareInstructionKind { MEDICATION, TEST, FOLLOW_UP, REHABILITATION, LIFESTYLE, OTHER }
internal enum class HealthCareInstructionField { NAME, DOSE, UNIT, ROUTE, FREQUENCY, START, END, DETAILS }
internal enum class HealthCareFieldReview { UNREVIEWED, TRANSCRIBED, NOT_STATED }
internal data class HealthCareInstructionValue(val text: String = "", val review: HealthCareFieldReview = HealthCareFieldReview.UNREVIEWED) {
    init {
        require(text.length <= 1000 && text == text.trim())
        require(review != HealthCareFieldReview.TRANSCRIBED || text.isNotBlank())
        require(review != HealthCareFieldReview.NOT_STATED || text.isEmpty())
    }
    fun json() = JSONObject().put("text", text).put("review", review.name)
    companion object { fun from(j: JSONObject) = HealthCareInstructionValue(j.getString("text"), HealthCareFieldReview.valueOf(j.getString("review"))) }
}

/** Field review records the user's transcription, never clinician approval or authority to execute. */
internal data class HealthCareInstructionDraft(val kind: HealthCareInstructionKind = HealthCareInstructionKind.OTHER,
    val fields: Map<HealthCareInstructionField, HealthCareInstructionValue> = emptyMap()) {
    val required: Set<HealthCareInstructionField> get() = when (kind) {
        HealthCareInstructionKind.MEDICATION -> HealthCareInstructionField.entries.toSet()
        else -> setOf(HealthCareInstructionField.NAME, HealthCareInstructionField.DETAILS, HealthCareInstructionField.START,
            HealthCareInstructionField.END, HealthCareInstructionField.FREQUENCY)
    }
    init { require(fields.keys.all { it in required }) }
    val reviewed get() = required.all { fields[it]?.review != null && fields[it]?.review != HealthCareFieldReview.UNREVIEWED }
    val missing get() = required.filter { fields[it]?.review == HealthCareFieldReview.NOT_STATED }.toSet()
    fun json() = JSONObject().put("kind", kind.name).put("fields", JSONObject(fields.mapKeys { it.key.name }.mapValues { it.value.json() }))
    companion object {
        fun from(j: JSONObject) = HealthCareInstructionDraft(HealthCareInstructionKind.valueOf(j.getString("kind")),
            j.getJSONObject("fields").let { f -> f.keys().asSequence().associate { HealthCareInstructionField.valueOf(it) to HealthCareInstructionValue.from(f.getJSONObject(it)) } })
    }
}

internal data class HealthCareInstructionSource(val documentId: String, val original: HealthCareDocumentRef,
    val recognition: HealthRecognition, val quote: String, val lines: List<Int>, val boxes: List<List<Int>>, val blurry: Boolean) {
    init {
        require(HealthProfilePolicy.uuid(documentId) && original.page != null)
        require(quote.isNotBlank() && quote.length <= 8000 && lines.size in 1..200 && lines == lines.distinct().sorted() && lines.all { it >= 0 })
        require(boxes.size <= lines.size && boxes.all { b -> b.size == 4 && b.all { it in 0..1000 } && b[0] <= b[2] && b[1] <= b[3] })
    }
    fun json() = JSONObject().put("document", documentId).put("original", original.json()).put("recognition", recognition.name)
        .put("quote", quote).put("lines", JSONArray(lines)).put("boxes", JSONArray(boxes.map(::JSONArray))).put("blurry", blurry)
    companion object {
        fun from(j: JSONObject) = HealthCareInstructionSource(j.getString("document"), HealthCareDocumentRef.from(j.getJSONObject("original")),
            HealthRecognition.valueOf(j.getString("recognition")), j.getString("quote"), j.getJSONArray("lines").let { a -> (0 until a.length()).map(a::getInt) },
            j.getJSONArray("boxes").let { a -> (0 until a.length()).map { n -> a.getJSONArray(n).let { b -> (0 until b.length()).map(b::getInt) } } }, j.getBoolean("blurry"))
        fun select(link: HealthCareDocumentLink, page: HealthOcrPage, count: Int, selected: Set<Int>): HealthCareInstructionSource {
            require(selected.isNotEmpty() && selected.all { it in page.lines.indices })
            require(link.source.page == null || link.source.page == page.page && link.source.pageCount == count)
            val lines = selected.sorted(); val source = link.source.copy(page = page.page, pageCount = count)
            return HealthCareInstructionSource(link.id, source, page.recognition, lines.joinToString("\n") { page.lines[it].text }, lines,
                lines.map { page.lines[it].box }.filter(List<Int>::isNotEmpty), page.blurry)
        }
    }
}

internal data class HealthCareInstruction(val id: String, val concernId: String, val encounterId: String, val revision: Int,
    val source: HealthCareInstructionSource, val draft: HealthCareInstructionDraft, val createdAt: Long, val updatedAt: Long) {
    init { require(listOf(id, concernId, encounterId).all(HealthProfilePolicy::uuid) && revision > 1 && createdAt > 0 && updatedAt >= createdAt) }
    fun json() = JSONObject().put("id", id).put("concern", concernId).put("encounter", encounterId).put("revision", revision)
        .put("source", source.json()).put("draft", draft.json()).put("created", createdAt).put("updated", updatedAt).put("provenance", "user_transcribed")
    companion object {
        fun from(j: JSONObject): HealthCareInstruction {
            require(j.getString("provenance") == "user_transcribed")
            return HealthCareInstruction(j.getString("id"), j.getString("concern"), j.getString("encounter"), j.getInt("revision"),
                HealthCareInstructionSource.from(j.getJSONObject("source")), HealthCareInstructionDraft.from(j.getJSONObject("draft")), j.getLong("created"), j.getLong("updated"))
        }
    }
}
internal data class HealthCareInstructionReceipt(val operationId: String, val expectedConcern: Int, val expectedInstruction: Int?, val value: HealthCareInstruction) {
    init { require(HealthProfilePolicy.uuid(operationId) && expectedConcern in 1 until Int.MAX_VALUE && value.revision == expectedConcern + 1 &&
        (expectedInstruction == null || expectedInstruction in 2..expectedConcern)) }
    fun json() = JSONObject().put("operation", operationId).put("expected_concern", expectedConcern)
        .put("expected_instruction", expectedInstruction ?: JSONObject.NULL).put("value", value.json())
    companion object { fun from(j: JSONObject) = HealthCareInstructionReceipt(j.getString("operation"), j.getInt("expected_concern"),
        j.takeUnless { it.isNull("expected_instruction") }?.getInt("expected_instruction"), HealthCareInstruction.from(j.getJSONObject("value"))) }
}
internal data class HealthCareInstructionPage(val items: List<HealthCareInstruction>, val next: Int?)
internal class HealthCareSourceInUse : IllegalStateException("Remove the instruction drafts before removing their source association")
