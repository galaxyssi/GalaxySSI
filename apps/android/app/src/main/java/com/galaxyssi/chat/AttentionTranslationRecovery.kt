package com.galaxyssi.chat

import java.text.BreakIterator
import java.net.URI
import java.util.Locale

/** Bounded local retries, retaining all prose and rejecting unresolved numeric changes. */
internal object AttentionTranslationRecovery {
    private val identifier = Regex("[A-Za-z0-9_./:+#@%\\-]+")
    private val nameWord = Regex("\\p{Lu}[\\p{L}\\p{M}]*(?:[-'\u2019][\\p{L}\\p{M}]+)*\\.?")
    private val nameParticles = setOf("de", "del", "der", "van", "von", "da", "di", "du", "la", "le")
    private val citation = Regex("(?:[A-Za-z][A-Za-z.+-]*\\s+){1,4}[0-9][A-Za-z0-9:./()\\-]*\\.?")
    private val copyright = Regex("\u00a9\\s*(?:19|20)[0-9]{2},?\\s+(.+)")
    private val emailContact = Regex("(?:[A-Za-z][A-Za-z0-9 .&'-]{0,40}:\\s*)?[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
    private val proseStarts = setOf("The", "This", "That", "These", "Those", "A", "An", "New", "How", "Why", "What", "When", "We", "Our", "It", "You", "Your")

    fun technicalLabel(value: String): Boolean {
        val text = value.trim()
        if (webLink(text)) return true
        if (emailContact.matches(text)) return true
        if (text.length > 80 || text.isEmpty()) return false
        if (identifier.matches(text)) return true
        if (citation.matches(text)) return true
        copyright.matchEntire(text)?.let { match ->
            return match.groupValues[1].split(Regex("\\s+(?:and|&)\\s+|,\\s*")).all { credit ->
                val names = credit.split(Regex("\\s+"))
                names.size in 1..4 && names.any { nameWord.matches(it) } &&
                    names.all { nameWord.matches(it) || it in nameParticles }
            }
        }
        val words = text.split(Regex("\\s+"))
        return words.size in 2..4 && words.first() !in proseStarts && words.any { nameWord.matches(it) } &&
            words.all { nameWord.matches(it) || it in nameParticles }
    }

    fun sentences(text: String, limit: Int = 400): List<String> {
        val iterator = BreakIterator.getSentenceInstance(Locale.ENGLISH)
        iterator.setText(text)
        val result = mutableListOf<String>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            result += AttentionArticlePolicy.parts(text.substring(start, end), limit)
            start = end
            end = iterator.next()
        }
        return result
    }

    suspend fun convert(text: String, progress: AttentionTranslationProgress? = null, translate: suspend (String) -> String): String {
        if (webLink(text.trim())) return text.trim()
        val quotations = AttentionQuotedTranslation.ranges(text)
        if (quotations.isNotEmpty()) {
            var start = 0
            val result = StringBuilder()
            for (range in quotations) {
                result.append(text.substring(start, range.first))
                result.append(convert(text.substring(range), progress, translate))
                start = range.last + 1
            }
            result.append(text.substring(start))
            return result.toString().also { AttentionArticlePolicy.validateTranslation(text, it); progress?.save(text, it) }
        }
        suspend fun validated(source: String): String {
            progress?.read(source)?.let { cached ->
                if (runCatching { AttentionArticlePolicy.validateTranslation(source, cached) }.isSuccess) return cached
            }
            return translate(source).trim()
        }
        val result = AttentionArticlePolicy.translationChunks(text).map { source ->
            val first = validated(source)
            val failure = runCatching { AttentionArticlePolicy.validateTranslation(source, first) }.exceptionOrNull()
            if (failure == null) { progress?.save(source, first); first } else {
                if (failure.message !in setOf("article_translation_not_chinese", "article_translation_numbers_changed")) throw failure
                if (technicalLabel(source)) source.trim() else {
                    val smaller = sentences(source, 140)
                    if (smaller.size < 2) throw failure
                    smaller.joinToStringTranslated(progress, ::validated)
                }
            }
        }.joinToString("\n\n")
        AttentionArticlePolicy.validateTranslation(text, result)
        progress?.save(text, result)
        return result
    }

    private fun webLink(text: String): Boolean = text.length <= 8192 && runCatching {
        val uri = URI(text)
        uri.scheme?.lowercase(Locale.ROOT) in setOf("https", "http") && !uri.host.isNullOrBlank()
    }.getOrDefault(false)

    private suspend fun List<String>.joinToStringTranslated(progress: AttentionTranslationProgress?, translate: suspend (String) -> String): String {
        val translated = mutableListOf<String>()
        for (source in this) {
            val result = translate(source).trim()
            AttentionArticlePolicy.validateTranslation(source, result)
            progress?.save(source, result)
            translated += result
        }
        return translated.joinToString(" ")
    }
}
