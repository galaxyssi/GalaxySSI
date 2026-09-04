package com.galaxyssi.chat

/** Keeps inline model tool protocols out of user-visible streaming text. */
internal class InlineToolProtocolStreamGuard {
    private val raw = StringBuilder()
    private val pendingTag = StringBuilder()
    private var suppressProtocol = false

    fun append(fragment: String): String {
        if (fragment.isEmpty()) return ""
        raw.append(fragment)
        if (suppressProtocol) return ""

        val visible = StringBuilder()
        fragment.forEach { character ->
            if (suppressProtocol) return@forEach
            if (pendingTag.isEmpty()) {
                if (character == '<') pendingTag.append(character) else visible.append(character)
                return@forEach
            }

            pendingTag.append(character)
            val candidate = pendingTag.toString()
            if (looksLikeInternalProtocol(candidate)) {
                suppressProtocol = true
                pendingTag.clear()
            } else if (character == '>') {
                visible.append(candidate)
                pendingTag.clear()
            } else if (pendingTag.length >= MAX_PENDING_TAG_CHARS) {
                visible.append(candidate)
                pendingTag.clear()
            }
        }
        return visible.toString()
    }

    fun finishVisibleText(): String {
        if (suppressProtocol || pendingTag.isEmpty()) return ""
        val tail = pendingTag.toString()
        pendingTag.clear()
        return if (CloudWebGrounding.containsInternalToolProtocol(raw.toString())) "" else tail
    }

    fun rawText(): String = raw.toString()

    private fun looksLikeInternalProtocol(candidate: String): Boolean {
        val lower = candidate.lowercase()
        return "dsml" in lower || "tool_calls" in lower ||
            (candidate.endsWith('>') && CloudWebGrounding.containsInternalToolProtocol(candidate))
    }

    private companion object {
        const val MAX_PENDING_TAG_CHARS = 1_024
    }
}
