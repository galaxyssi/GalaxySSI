package com.galaxyssi.chat

import java.security.MessageDigest

internal data class AgentChunkedField(
    val storedValue: String,
    val chunks: List<String>,
    val totalLength: Int,
    val sha256: String
) {
    val chunkCount: Int
        get() = chunks.size
}

internal object AgentLargeOutputPolicy {
    const val CHUNK_THRESHOLD_CHARACTERS = 16 * 1024
    const val CHUNK_CHARACTERS = 8 * 1024
    const val PREVIEW_CHARACTERS = 4 * 1024

    fun prepare(value: String, includePreview: Boolean): AgentChunkedField {
        if (value.length <= CHUNK_THRESHOLD_CHARACTERS) {
            return AgentChunkedField(
                storedValue = value,
                chunks = emptyList(),
                totalLength = value.length,
                sha256 = digest(value)
            )
        }
        return AgentChunkedField(
            storedValue = if (includePreview) {
                value.substring(0, safeBoundary(value, PREVIEW_CHARACTERS))
            } else {
                ""
            },
            chunks = split(value),
            totalLength = value.length,
            sha256 = digest(value)
        )
    }

    fun split(value: String): List<String> = buildList {
        var offset = 0
        while (offset < value.length) {
            var end = (offset + CHUNK_CHARACTERS).coerceAtMost(value.length)
            if (end < value.length) {
                val minimum = offset + CHUNK_CHARACTERS / 2
                val paragraph = value.lastIndexOf("\n\n", end - 1)
                    .takeIf { it >= minimum }
                    ?.plus(2)
                val line = value.lastIndexOf('\n', end - 1)
                    .takeIf { it >= minimum }
                    ?.plus(1)
                end = paragraph ?: line ?: end
            }
            end = safeBoundary(value, end)
            add(value.substring(offset, end))
            offset = end
        }
    }

    private fun safeBoundary(value: String, requestedEnd: Int): Int {
        val end = requestedEnd.coerceIn(0, value.length)
        return if (
            end in 1 until value.length &&
            Character.isHighSurrogate(value[end - 1]) &&
            Character.isLowSurrogate(value[end])
        ) {
            end - 1
        } else {
            end
        }
    }

    fun digest(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    fun hasDeferredContent(entry: AgentTranscriptEntry): Boolean =
        (entry.textChunkCount > 0 && entry.text.length < entry.textLength) ||
            (
                entry.richOutputChunkCount > 0 &&
                    entry.richOutputJson.length < entry.richOutputLength
                )
}
