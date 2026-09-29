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
            val prefix = text.substring((start - 80).coerceAtLeast(0), start)
            val negated = negativeMention.containsMatchIn(prefix)
            if (!embedded && !quotedField && !negated) return true
            start = text.indexOf(term, end)
        }
        return false
    }

    private fun Char.isAsciiWord(): Boolean = this in 'a'..'z' || this in '0'..'9' || this == '_'

    // A delivery constraint such as "do not return code" is not a code-execution request.
    // Stop at clause boundaries so a later affirmative instruction is still recognized.
    private val negativeMention = Regex(
        "(?:(?:不要|不能|不必|无需|不用|勿)(?:只)?" +
            "(?:给出|提供|返回|输出|展示|显示|附上|包含|给|写|编写|生成|执行|运行)" +
            "[^。！？;；,，\\n]{0,40}|(?:不要|无需|不用|不需要)\\s*|" +
            "\\b(?:do not|don't|never|no need to)\\s+(?:only\\s+|just\\s+)?" +
            "(?:give|return|provide|show|output|include|write|generate|run|execute)" +
            "[^.!?;,\\n]{0,40})$", RegexOption.IGNORE_CASE
    )
}
