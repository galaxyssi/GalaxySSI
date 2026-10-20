package com.galaxyssi.chat

import java.util.Locale

/** Metadata matching only: this never selects a provider or changes execution location. */
internal object AgentCapabilitySearch {
    private val token = Regex("[a-z0-9_.-]+|[\\p{IsHan}]+")
    private val aliases = mapOf(
        "搜索" to "search", "查询" to "search", "查找" to "search",
        "网页" to "web", "网站" to "web", "图片" to "image", "照片" to "image",
        "新闻" to "news", "资料" to "research", "浏览器" to "browser",
        "文件" to "file", "下载" to "download", "读取" to "read", "安装" to "install"
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
