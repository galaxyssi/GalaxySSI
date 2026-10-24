package com.galaxyssi.chat

import org.jsoup.Jsoup

internal data class AttentionChineseArticle(val title: String, val body: String, val provider: String)

/** Publication requires an extracted body, not a feed description or an HTTP success alone. */
internal object AttentionArticlePolicy {
    const val REVISION = 2
    fun visible(message: GlobalProactiveMessage): Boolean =
        !ProactiveAttentionPolicy.isAttention(message) && !message.id.startsWith("attention-feed:") ||
            message.newsArticleKey.isNotBlank() && message.newsArticleRevision >= REVISION

    fun extract(page: AgentWebIntelligenceFetched): AgentPublicArticle {
        require(page.contentType.contains("html", true)) { "article_not_html" }
        require(AgentDynamicWebFallbackPolicy.reason(page) == null) { "article_challenge_or_script_shell" }
        val html = AgentWebTextDecoder.decode(page.body, page.contentType, page.url)
        val document = Jsoup.parse(html, page.url)
        require(document.select("[itemprop=isAccessibleForFree][content=false]").isEmpty() &&
            !Regex("\"isAccessibleForFree\"\\s*:\\s*(false|\"false\")", RegexOption.IGNORE_CASE).containsMatchIn(html)) {
            "article_paywall"
        }
        val article = requireNotNull(AttentionArticleExtractor.parse(page.url, document)) { "article_body_missing" }
        require(article.content.length in 200 until AgentWebIntelligenceService.MAX_CONTENT_CHARS) { "article_body_missing_or_truncated" }
        val lower = article.content.take(1500).lowercase()
        require(listOf("verify you are human", "enable javascript and cookies", "access denied", "sign in to continue",
            "subscribe to continue reading").none(lower::contains)) { "article_access_gate" }
        return article
    }

    fun chinese(text: String): Boolean {
        if (text.any { it in '\u3040'..'\u30ff' || it in '\uac00'..'\ud7af' }) return false
        val letters = text.count(Char::isLetter)
        return letters > 0 && text.count { it in '\u3400'..'\u9fff' }.toDouble() / letters >= .35
    }

    fun parts(text: String, limit: Int = 1200): List<String> {
        require(limit >= 32)
        return text.split(Regex("\n\\s*\n")).flatMap { paragraph ->
            val parts = mutableListOf<String>()
            var remaining = paragraph.trim()
            while (remaining.length > limit) {
                var end = remaining.take(limit).indexOfLast { it.isWhitespace() || it in ".!?;\u3002\uff01\uff1f\uff1b" } + 1
                if (end < limit / 2) end = limit
                if (Character.isHighSurrogate(remaining[end - 1])) end--
                parts += remaining.substring(0, end).trim()
                remaining = remaining.substring(end).trim()
            }
            if (remaining.isNotEmpty()) parts += remaining
            parts
        }
    }

    fun validateTranslation(source: String, translated: String) {
        require(translated.isNotBlank() && !Regex("<[A-Za-z/!][^>]*>").containsMatchIn(translated) &&
            !translated.contains("```")) { "article_translation_invalid" }
        val identifier = Regex("[A-Za-z0-9_./:+#@%\\-]+")
        require(chinese(translated) || translated == source.trim() &&
            (!source.any(Char::isLetter) || source.length <= 120 && identifier.matches(source.trim()))) {
            "article_translation_not_chinese"
        }
        val translatedNumbers = AttentionArticleNumbers.values(translated)
        require(AttentionArticleNumbers.values(source).all { (number, count) -> (translatedNumbers[number] ?: 0) >= count }) {
            "article_translation_numbers_changed"
        }
    }

    fun translationChunks(text: String): List<String> {
        val chunks = mutableListOf<String>()
        var chunk = ""
        for (part in parts(text)) {
            if (chunk.isNotEmpty() && chunk.length + part.length > 1200) {
                chunks += chunk
                chunk = ""
            }
            chunk += (if (chunk.isEmpty()) "" else "\n\n") + part
        }
        if (chunk.isNotEmpty()) {
            // Keep short bylines and numeric tails in linguistic context, not as isolated requests.
            if (chunks.isNotEmpty() && chunk.length < 120) chunks[chunks.lastIndex] += "\n\n$chunk"
            else chunks += chunk
        }
        return chunks
    }

}

internal class AttentionArticleTranslation(private val translate: suspend (String) -> String) {
    suspend fun run(title: String, body: String): AttentionChineseArticle {
        require(body.length >= 200) { "article_body_missing" }
        var translatedAny = false
        suspend fun convert(text: String): String {
            if (!text.any(Char::isLetter) || AttentionArticlePolicy.chinese(text)) return text
            val result = translate(text).trim()
            AttentionArticlePolicy.validateTranslation(text, result)
            translatedAny = translatedAny || result != text
            return result
        }
        val chineseTitle = convert(title)
        val paragraphs = AttentionArticlePolicy.translationChunks(body).map { convert(it) }
        return AttentionChineseArticle(chineseTitle, paragraphs.joinToString("\n\n"),
            if (translatedAny) AttentionMlKitTranslator.PROVIDER else "")
    }
}
