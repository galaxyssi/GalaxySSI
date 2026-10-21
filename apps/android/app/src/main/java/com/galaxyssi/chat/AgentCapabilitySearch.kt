package com.galaxyssi.chat

import java.util.Locale

/** Metadata matching only: this never selects a provider or changes execution location. */
internal object AgentCapabilitySearch {
    private val token = Regex("[a-z0-9_.-]+|[\\p{IsHan}]+")
    private val aliases = mapOf(
        "\u641c\u7d22" to "search", "\u67e5\u8be2" to "search", "\u67e5\u627e" to "search",
        "\u7f51\u9875" to "web", "\u7f51\u7ad9" to "web", "\u56fe\u7247" to "image", "\u7167\u7247" to "image",
        "\u65b0\u95fb" to "news", "\u8d44\u6599" to "research", "\u6d4f\u89c8\u5668" to "browser",
        "\u6587\u4ef6" to "file", "\u4e0b\u8f7d" to "download", "\u8bfb\u53d6" to "read", "\u5b89\u88c5" to "install"
    )

    fun matches(query: String, tool: AgentNativeToolDescriptor): Boolean {
        if (query.isBlank()) return true
        val text = "${tool.id} ${tool.title} ${tool.description} ${tool.capabilities.joinToString(" ")}"
            .lowercase(Locale.ROOT)
        val translated = aliases.filterKeys(query::contains).values.distinct()
        if (translated.isNotEmpty()) return translated.all(text::contains)
        val words = token.findAll(query.lowercase(Locale.ROOT)).map { it.value }.toList()
        return words.isNotEmpty() && words.all { word ->
            text.contains(word) || (word.all { it.code > 127 } && word.length >= 2 &&
                word.windowed(2).any(text::contains))
        }
    }
}
