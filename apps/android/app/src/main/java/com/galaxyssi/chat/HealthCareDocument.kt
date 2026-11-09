package com.galaxyssi.chat

import org.json.JSONObject

/** Selecting an original establishes provenance, not a verified diagnosis or instruction. */
internal data class HealthCareDocumentRef(val originalId: String, val sha256: String, val size: Long, val mime: String,
    val page: Int? = null, val pageCount: Int? = null) {
    init {
        require(HealthProfilePolicy.uuid(originalId) && sha256.matches(Regex("[0-9a-f]{64}")) && size > 0)
        require(mime.isNotBlank() && mime.length <= 200 && mime == mime.trim())
        require((page == null) == (pageCount == null))
        if (page != null) {
            require(page > 0 && pageCount!! >= page)
            require(mime == "application/pdf" || mime.startsWith("image/") && page == 1 && pageCount == 1)
        }
    }
    fun matches(original: HealthOriginal) = original.id == originalId && original.sha256 == sha256 && original.size == size &&
        original.mime == mime && !original.reviewOnly
    fun json() = JSONObject().put("original", originalId).put("sha256", sha256).put("size", size).put("mime", mime)
        .put("page", page ?: JSONObject.NULL).put("page_count", pageCount ?: JSONObject.NULL)
    companion object {
        fun from(original: HealthOriginal, page: Int? = null, pageCount: Int? = null) =
            HealthCareDocumentRef(original.id, original.sha256, original.size, original.mime, page, pageCount).also { require(it.matches(original)) }
        fun from(j: JSONObject) = HealthCareDocumentRef(j.getString("original"), j.getString("sha256"), j.getLong("size"), j.getString("mime"),
            j.takeUnless { it.isNull("page") }?.getInt("page"), j.takeUnless { it.isNull("page_count") }?.getInt("page_count"))
    }
}

internal data class HealthCareDocumentLink(val id: String, val concernId: String, val encounterId: String, val revision: Int,
    val expectedConcern: Int, val expectedEncounter: Int, val source: HealthCareDocumentRef, val createdAt: Long) {
    init {
        require(listOf(id, concernId, encounterId).all(HealthProfilePolicy::uuid))
        require(expectedConcern in 1 until Int.MAX_VALUE && revision == expectedConcern + 1)
        require(expectedEncounter in 1..expectedConcern && createdAt > 0)
    }
    fun json() = JSONObject().put("id", id).put("concern", concernId).put("encounter", encounterId).put("revision", revision)
        .put("expected_concern", expectedConcern).put("expected_encounter", expectedEncounter).put("source", source.json())
        .put("created_at", createdAt).put("provenance", "user_selected_original")
    companion object {
        fun from(j: JSONObject): HealthCareDocumentLink {
            require(j.getString("provenance") == "user_selected_original")
            return HealthCareDocumentLink(j.getString("id"), j.getString("concern"), j.getString("encounter"), j.getInt("revision"),
                j.getInt("expected_concern"), j.getInt("expected_encounter"), HealthCareDocumentRef.from(j.getJSONObject("source")), j.getLong("created_at"))
        }
    }
}
internal data class HealthCareDocumentPage(val items: List<HealthCareDocumentLink>, val next: Int?)
