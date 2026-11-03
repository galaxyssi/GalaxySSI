package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthImportState { QUEUED, COPYING, RECOGNIZING, CAPTURE_READY, REVIEW, TABLE_REVIEW, ORIGINAL_ONLY, FAILED, CANCELLED }
internal data class HealthImportJob(
    val id: String, val sourceUri: String, val createdAt: Long,
    val mode: String = "report", val cameraToken: String = "",
    val name: String = "", val mime: String = "", val totalBytes: Long = 0,
    val copiedBytes: Long = 0, val originalId: String = "", val nextPage: Int = 0,
    val pageCount: Int = 0, val state: HealthImportState = HealthImportState.QUEUED, val error: String = "",
    val captureBatch: String = "", val captureSubmitted: Boolean = false, val documentPage: Int = 0
) {
    fun json() = JSONObject().put("id", id).put("uri", sourceUri).put("created", createdAt).put("mode", mode)
        .put("camera", cameraToken).put("name", name).put("mime", mime).put("total", totalBytes).put("copied", copiedBytes)
        .put("original", originalId).put("next_page", nextPage).put("page_count", pageCount).put("state", state.name).put("error", error)
        .put("capture_batch", captureBatch).put("capture_submitted", captureSubmitted)
        .put("document_page", documentPage)
    companion object {
        fun from(j: JSONObject) = HealthImportJob(j.getString("id"), j.getString("uri"), j.getLong("created"), j.getString("mode"),
            j.getString("camera"), j.getString("name"), j.getString("mime"), j.getLong("total"), j.getLong("copied"),
            j.getString("original"), j.getInt("next_page"), j.getInt("page_count"), HealthImportState.valueOf(j.getString("state")), j.getString("error"),
            j.optString("capture_batch"), j.optBoolean("capture_submitted"), j.optInt("document_page"))
    }
}
internal data class HealthOriginal(
    val id: String, val streamId: String, val name: String, val mime: String, val size: Long,
    val sha256: String, val importedAt: Long, val relativePath: String, val source: String
) {
    fun json() = JSONObject().put("id", id).put("stream", streamId).put("name", name).put("mime", mime).put("size", size)
        .put("sha256", sha256).put("imported", importedAt).put("path", relativePath).put("source", source)
    companion object {
        fun from(j: JSONObject) = HealthOriginal(j.getString("id"), j.getString("stream"), j.getString("name"), j.getString("mime"),
            j.getLong("size"), j.getString("sha256"), j.getLong("imported"), j.getString("path"), j.getString("source"))
    }
}
internal data class HealthOcrLine(val text: String, val box: List<Int> = emptyList()) {
    fun json() = JSONObject().put("text", text).put("box", JSONArray(box))
    companion object {
        fun from(j: JSONObject) = HealthOcrLine(j.getString("text"), j.getJSONArray("box").let { a -> (0 until a.length()).map(a::getInt) })
    }
}
internal data class HealthOcrPage(val page: Int, val width: Int, val height: Int, val lines: List<HealthOcrLine>, val blurry: Boolean = false) {
    fun json() = JSONObject().put("page", page).put("width", width).put("height", height).put("lines", JSONArray(lines.map { it.json() }))
        .put("blurry", blurry)
    companion object {
        fun from(j: JSONObject) = HealthOcrPage(j.getInt("page"), j.getInt("width"), j.getInt("height"),
            j.getJSONArray("lines").let { a -> (0 until a.length()).map { HealthOcrLine.from(a.getJSONObject(it)) } }, j.getBoolean("blurry"))
    }
}

internal data class HealthEvidence(
    val originalId: String, val jobId: String, val candidateId: String, val sha256: String, val page: Int,
    val rawText: String, val boxes: List<List<Int>> = emptyList(), val confirmed: Boolean = false, val documentPage: Int = 0,
    val kind: String = "ocr", val tableRow: Long = 0
) {
    fun json() = JSONObject().put("original", originalId).put("job", jobId).put("candidate", candidateId)
        .put("sha256", sha256).put("page", page).put("text", rawText).put("boxes", JSONArray(boxes.map { JSONArray(it) }))
        .put("confirmed", confirmed)
        .put("document_page", documentPage)
        .put("kind", kind).put("table_row", tableRow)
    fun valid(): Boolean = listOf(originalId, jobId).all { runCatching { java.util.UUID.fromString(it).toString() == it }.getOrDefault(false) } &&
        candidateId.matches(Regex("[a-zA-Z0-9_-]{1,80}")) && sha256.matches(Regex("[0-9a-f]{64}")) &&
        page > 0 && documentPage >= 0 && rawText.length <= 8000 &&
        (kind == "ocr" && tableRow == 0L || kind == "table" && tableRow > 0 && documentPage == 0 && boxes.isEmpty()) &&
        boxes.all { it.size == 4 && it.all { value -> value in 0..1000 } && it[0] <= it[2] && it[1] <= it[3] }
    companion object {
        fun from(j: JSONObject) = HealthEvidence(j.getString("original"), j.getString("job"), j.getString("candidate"), j.getString("sha256"),
            j.getInt("page"), j.getString("text"), j.getJSONArray("boxes").let { a -> (0 until a.length()).map { i ->
                val box = a.getJSONArray(i); (0 until box.length()).map(box::getInt)
            } }, j.getBoolean("confirmed"), j.optInt("document_page"), j.optString("kind", "ocr"), j.optLong("table_row"))
    }
}

internal class HealthImportFailure(val code: String) : java.io.IOException(code)
