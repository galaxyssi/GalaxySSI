package com.galaxyssi.chat

import org.json.JSONObject

internal data class HealthPhotoBatch(val id: String, val mode: String, val createdAt: Long, val submitted: Boolean = false,
    val keepOriginal: Boolean = true) {
    fun json() = JSONObject().put("id", id).put("mode", mode).put("created", createdAt).put("submitted", submitted)
        .put("keep_original", keepOriginal)
    companion object { fun from(j: JSONObject) = HealthPhotoBatch(j.getString("id"), j.getString("mode"), j.getLong("created"),
        j.getBoolean("submitted"), j.optBoolean("keep_original", true)) }
}
internal data class HealthPhotoPage(val jobId: String, val batchId: String, val position: Int, val quality: HealthPhotoQuality? = null) {
    fun json() = JSONObject().put("job", jobId).put("batch", batchId).put("position", position).apply { quality?.let { put("quality", it.json()) } }
    companion object { fun from(j: JSONObject) = HealthPhotoPage(j.getString("job"), j.getString("batch"), j.getInt("position"), j.optJSONObject("quality")?.let(HealthPhotoQuality::from)) }
}
internal data class HealthPhotoQuality(val width: Int, val height: Int, val rotation: Int, val detail: Double, val luminance: Double) {
    val lowDetail get() = detail < 45.0
    val dark get() = luminance < 35.0
    val small get() = minOf(width, height) < 800
    val needsReview get() = lowDetail || dark || small
    fun json() = JSONObject().put("width", width).put("height", height).put("rotation", rotation).put("detail", detail).put("luminance", luminance)
    companion object { fun from(j: JSONObject) = HealthPhotoQuality(j.getInt("width"), j.getInt("height"), j.getInt("rotation"), j.getDouble("detail"), j.getDouble("luminance")) }
}

/** A capture-quality hint, not a diagnosis or a guarantee of OCR accuracy. */
internal object HealthPhotoQualityPolicy {
    fun inspect(gray: IntArray, width: Int, height: Int): Pair<Double, Double> {
        require(width >= 3 && height >= 3 && gray.size == width * height && gray.all { it in 0..255 })
        var sum = 0.0; var squared = 0.0; var count = 0
        for (y in 1 until height - 1) for (x in 1 until width - 1) {
            val i = y * width + x
            val laplacian = 4.0 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - width] - gray[i + width]
            sum += laplacian; squared += laplacian * laplacian; count++
        }
        return (squared / count - (sum / count) * (sum / count)).coerceAtLeast(0.0) to gray.average()
    }
}
