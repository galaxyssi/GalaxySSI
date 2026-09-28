package com.galaxyssi.chat

/** Lexical hints for routing only; field names are not requests to execute code. */
internal object AgentCodeKeywordPolicy {
    fun contains(text: String, term: String): Boolean {
        if (term.isEmpty()) return false
        var start = text.indexOf(term)
        while (start >= 0) {
            val end = start + term.length
            val embedded = (term.first().isAsciiWord() && text.getOrNull(start - 1)?.isAsciiWord() == true) ||
                (term.last().isAsciiWord() && text.getOrNull(end)?.isAsciiWord() == true)
            val quote = text.getOrNull(start - 1)
            var next = end + 1
            if (quote == '\"' || quote == '\'') {
                while (next < text.length && text[next].isWhitespace()) next++
            }
            val quotedField = (quote == '\"' || quote == '\'') && text.getOrNull(end) == quote &&
                text.getOrNull(next) == ':'
            if (!embedded && !quotedField) return true
            start = text.indexOf(term, end)
        }
        return false
    }

    private fun Char.isAsciiWord(): Boolean = this in 'a'..'z' || this in '0'..'9' || this == '_'
}
