package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class AttentionArticleBlock(
    val kind: String,
    val text: String = "",
    val url: String = "",
    val width: Int = 0,
    val height: Int = 0,
    val emphasis: List<String> = emptyList()
)

internal data class AttentionArticleDocument(val blocks: List<AttentionArticleBlock>) {
    val body get() = blocks.filter { it.kind != "image" }.joinToString("\n\n") { it.text }
    val cover get() = blocks.firstOrNull { it.kind == "image" }

    fun encode(): String = JSONArray().apply {
        blocks.forEach { block -> put(JSONObject().put("kind", block.kind).put("text", block.text)
            .put("url", block.url).put("width", block.width).put("height", block.height)
            .put("emphasis", JSONArray(block.emphasis))) }
    }.toString()

    companion object {
        fun decode(value: String): AttentionArticleDocument? = runCatching {
            if (value.isBlank()) return null
            val array = JSONArray(value)
            require(array.length() <= 2000)
            AttentionArticleDocument((0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                val emphasis = item.optJSONArray("emphasis") ?: JSONArray()
                AttentionArticleBlock(item.getString("kind"), item.optString("text"), item.optString("url"),
                    item.optInt("width"), item.optInt("height"), (0 until emphasis.length()).map(emphasis::getString))
            })
        }.getOrNull()

        fun plain(body: String) = AttentionArticleDocument(body.split(Regex("\n\\s*\n"))
            .filter(String::isNotBlank).map { AttentionArticleBlock("paragraph", it.trim()) })
    }
}

internal data class AttentionArticleSource(val article: AgentPublicArticle, val document: AttentionArticleDocument)

internal data class AttentionArticlePresentation(
    val preview: String,
    val cover: AttentionArticleBlock?,
    val publisher: String,
    val published: Long,
    val document: AttentionArticleDocument? = null
)

/** Extractive reading aids never add claims or remove qualifications from the source. */
internal object AttentionArticleReadingPolicy {
    private val boilerplate = Regex("^(\u611f\u8c22.*(\u7f51\u53cb|\u7ebf\u7d22|\u6295\u9012)|\u8d23\u4efb\u7f16\u8f91[\uff1a:]|\u7f16\u8f91[\uff1a:]|\u672c\u6587\u6765\u6e90[\uff1a:]|" +
        "\u5e7f\u544a\u58f0\u660e[\uff1a:]|\u76f8\u5173\u9605\u8bfb[\uff1a:]|\u63a8\u8350\u9605\u8bfb[\uff1a:]|\u70b9\u51fb.*(\u5173\u6ce8|\u8ba2\u9605)|thanks? to .*tip|" +
        "subscribe to |sign up for )", RegexOption.IGNORE_CASE)

    fun informative(text: String): Boolean = text.isNotBlank() && !boilerplate.containsMatchIn(text.trim())

    fun excerpts(document: AttentionArticleDocument): List<String> = document.blocks.asSequence()
        .filter { it.kind in setOf("paragraph", "list") && informative(it.text) && it.text.length >= 25 }
        .map { block ->
            val firstSentence = Regex("^.*?[。！？](?:[”’\"])?").find(block.text)?.value
            firstSentence?.takeIf { it.length in 25..180 } ?: block.text.takeIf { it.length <= 180 }
        }.filterNotNull().distinct().take(3).toList()

    fun preview(document: AttentionArticleDocument): String = excerpts(document).firstOrNull()
        ?: document.blocks.firstOrNull { it.kind in setOf("paragraph", "list", "quote") && informative(it.text) }
            ?.text?.take(500).orEmpty()
}
