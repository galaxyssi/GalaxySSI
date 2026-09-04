package com.galaxyssi.chat

import okhttp3.HttpUrl.Companion.toHttpUrl

internal object Lfm25QnnDownloadCatalog {
    const val ARCHIVE_FILE_NAME = "lfm2.5-2.6b-qnn-w4a8-sm8850.zip"
    const val ESTIMATED_ARCHIVE_BYTES = 1_900_000_000L
    const val MAX_ARCHIVE_BYTES = 3L * 1024L * 1024L * 1024L

    fun sourceUrls(preferChinaMirror: Boolean): List<String> {
        val modelScope = "https://modelscope.cn/".toHttpUrl().newBuilder()
            .addPathSegments("api/v1/models/GalaxySSI/LFM2.5-2.6B-QNN/repo")
            .addQueryParameter("Revision", "master")
            .addQueryParameter("FilePath", ARCHIVE_FILE_NAME)
            .build()
            .toString()
        val huggingFace = huggingFaceUrl("https://huggingface.co/")
        val huggingFaceMirror = huggingFaceUrl("https://hf-mirror.com/")
        val github = "https://github.com/galaxyssi/GalaxySSI/releases/download/" +
            "android-qnn-models-v1/$ARCHIVE_FILE_NAME"
        return if (preferChinaMirror) {
            listOf(modelScope, huggingFaceMirror, huggingFace, github)
        } else {
            listOf(huggingFace, github, modelScope, huggingFaceMirror)
        }
    }

    fun responseTotalBytes(
        requestedOffset: Long,
        responseContentLength: Long,
        contentRange: String?,
        fallbackBytes: Long
    ): Long {
        val rangeTotal = contentRange
            ?.substringAfterLast('/', missingDelimiterValue = "")
            ?.toLongOrNull()
        val responseTotal = responseContentLength
            .takeIf { it >= 0L }
            ?.let { length -> safeAdd(requestedOffset, length) }
        return (rangeTotal ?: responseTotal ?: fallbackBytes)
            .also { total -> require(total in 1L..MAX_ARCHIVE_BYTES) { "Invalid QNN package size" } }
    }

    private fun huggingFaceUrl(baseUrl: String): String = baseUrl.toHttpUrl().newBuilder()
        .addPathSegments("GalaxySSI/LFM2.5-2.6B-QNN")
        .addPathSegment("resolve")
        .addPathSegment("main")
        .addPathSegment(ARCHIVE_FILE_NAME)
        .build()
        .toString()

    private fun safeAdd(left: Long, right: Long): Long =
        if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right
}
