package com.galaxyssi.chat

/** A window of the extracted body, not a claim that the original page or claim was verified. */
internal object AgentWebReadingWindow {
    const val MAX_CHARS = 8_000

    fun document(document: AgentWebIntelligenceDocument, arguments: AgentNativeJsonObject): AgentNativeJsonObject {
        var offset = ((arguments["offset"] as? Number)?.toInt() ?: 0).coerceIn(0, document.content.length)
        if (offset in 1 until document.content.length && Character.isLowSurrogate(document.content[offset]) &&
            Character.isHighSurrogate(document.content[offset - 1])) offset--
        val length = ((arguments["length"] as? Number)?.toInt() ?: MAX_CHARS).coerceIn(256, MAX_CHARS)
        var end = (offset + length).coerceAtMost(document.content.length)
        if (end < document.content.length && Character.isHighSurrogate(document.content[end - 1]) &&
            Character.isLowSurrogate(document.content[end])) end--
        val expected = arguments["document_sha256"]?.toString().orEmpty()
        val version = AgentNativeJsonCodec.sha256(document.content)
        return document.publicValue() + mapOf("reading_window" to linkedMapOf(
            "offset" to offset,
            "end_offset" to end,
            "total_chars" to document.content.length,
            "next_offset" to if (end < document.content.length) end else null,
            "document_sha256" to version,
            "version_changed" to (expected.isNotBlank() && expected != version),
            "scope" to "extracted_readable_body_not_original_page",
            "semantic_verification" to "not_independently_verified"
        ))
    }

    fun searchAllowance(totalMillis: Long, readMillis: Long): Long =
        (totalMillis - minOf(readMillis, totalMillis / 2)).coerceAtLeast(1_000L)
}
