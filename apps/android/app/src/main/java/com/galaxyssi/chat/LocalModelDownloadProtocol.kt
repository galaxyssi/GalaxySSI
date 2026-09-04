package com.galaxyssi.chat

object LocalModelDownloadProtocol {
    private val contentRangePattern = Regex("bytes\\s+(\\d+)-(\\d+)/(\\d+|\\*)", RegexOption.IGNORE_CASE)

    fun resumeOffset(partialLength: Long, expectedLength: Long): Long =
        partialLength.takeIf { it in 0..expectedLength } ?: 0L

    fun shouldAppend(requestedOffset: Long, responseCode: Int, contentRange: String?): Boolean {
        if (requestedOffset <= 0L || responseCode != 206) return false
        val start = contentRange
            ?.let(contentRangePattern::matchEntire)
            ?.groupValues
            ?.getOrNull(1)
            ?.toLongOrNull()
        require(start == requestedOffset) { "Model source returned an invalid Content-Range" }
        return true
    }
}
