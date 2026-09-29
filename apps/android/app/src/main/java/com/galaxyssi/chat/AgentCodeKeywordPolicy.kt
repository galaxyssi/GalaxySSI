package com.galaxyssi.chat

/** Lexical hints for routing only; field names are not requests to execute code. */
internal object AgentCodeKeywordPolicy {
    fun contains(text: String, term: String): Boolean {
        if (term in ambiguousScopes && officeDeliverable.findAll(text).any { match ->
                !negatedArtifactVerb.containsMatchIn(text.substring(0, match.range.first))
            } &&
            softwareContext.none { containsLiteral(text, it) }) return false
        return containsLiteral(text, term)
    }

    private fun containsLiteral(text: String, term: String): Boolean {
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

    // A warehouse/project document is not a software workspace. Explicit software
    // work still wins, including requests to document a repository after changing it.
    private val ambiguousScopes = setOf("仓库", "项目", "project")
    private val negatedArtifactVerb = Regex(
        "(?:不要|不能|无需|不用|勿|\\bdo not|\\bdon't|\\bnever)\\s*$", RegexOption.IGNORE_CASE
    )
    private val officeDeliverable = Regex(
        "(?:生成|制作|创建|导出|编写|修改|更新|create|generate|export|write|edit|update)" +
            "[^。！？.!?;；\\n]{0,80}(?<![a-z0-9_])(?:docx|word|xlsx|excel|pptx|ppt|powerpoint)(?![a-z0-9_])",
        RegexOption.IGNORE_CASE
    )
    private val softwareContext = listOf(
        "python", "code", "script", "codebase", "repository", "git", "github", "gradle", "apk",
        "compile", "debug", "clone", "checkout", "pull request", "unit test",
        "代码", "脚本", "编程", "编译", "调试", "克隆", "检出", "单元测试", "提交pr", "提交 pr"
    )

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
