package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class HealthReportImportOutcome(
    val saved: Int, val duplicates: Int, val skipped: Int, val partial: Boolean, val imageBytes: Int,
    val recordIds: List<String>
) {
    init {
        require(listOf(saved, duplicates, skipped).all { it in 0..HealthReportVisionResult.MAX_ROWS })
        require(saved + duplicates + skipped <= HealthReportVisionResult.MAX_ROWS)
        require(imageBytes in 0..HealthReportCodexGateway.MAX_IMAGE_BYTES)
        require(recordIds.size <= saved + duplicates && recordIds.distinct() == recordIds &&
            recordIds.all(HealthProfilePolicy::uuid))
    }
    fun json() = JSONObject().put("saved", saved).put("duplicates", duplicates).put("skipped", skipped)
        .put("partial", partial).put("image_bytes", imageBytes).put("records", JSONArray(recordIds))

    companion object {
        fun from(j: JSONObject) = HealthReportImportOutcome(j.getInt("saved"), j.getInt("duplicates"),
            j.getInt("skipped"), j.getBoolean("partial"), j.getInt("image_bytes"),
            j.getJSONArray("records").let { a -> List(a.length(), a::getString) })
    }
}
