package com.galaxyssi.chat

import org.json.JSONObject
import org.jsoup.Jsoup
import java.net.URI

/** Reads public server-rendered search data, never executes page scripts. */
internal object AgentPublicImageSearchParser {
    const val SOGOU = "sogou_image"
    val directParsers = setOf(SOGOU, "brave_image", "duckduckgo_image")

    fun sogou(html: String, limit: Int): List<AgentWebIntelligenceRawResult> {
        val script = Jsoup.parse(html).select("script").asSequence()
            .map { it.data().trim() }
            .firstOrNull { it.startsWith("window.__INITIAL_STATE__=") }
            ?: throw AgentWebMediaException("invalid_engine_response", "Image search did not return public result data")
        val root = JSONObject(script.substringAfter('=').trim().removeSuffix(";"))
        val values = root.optJSONObject("searchList")?.optJSONArray("searchList")
            ?: throw AgentWebMediaException("invalid_engine_response", "Image search result schema changed")
        val seen = hashSetOf<String>()
        return buildList {
            for (index in 0 until minOf(values.length(), 100)) {
                val row = values.optJSONObject(index) ?: continue
                val title = AgentWebIntelligenceText.clean(row.optString("title"), 512)
                val source = publicUrl(row.optString("url"), httpsOnly = false)
                val thumbnail = publicUrl(row.optString("thumbUrl"))
                val original = publicUrl(row.optString("oriPicUrl")).ifBlank { publicUrl(row.optString("picUrl")) }
                val image = original.ifBlank { thumbnail }
                if (title.isBlank() || source.isBlank() || image.isBlank() || !seen.add(image)) continue
                add(AgentWebIntelligenceRawResult(
                    engineId = SOGOU, rank = size + 1, title = title, url = source,
                    excerpt = AgentWebIntelligenceText.clean(row.optString("content_major"), 2_048),
                    vertical = AgentWebIntelligenceVertical.IMAGE, imageUrl = image,
                    thumbnailUrl = thumbnail,
                    imageWidth = row.optInt(if (original.isBlank()) "thumbWidth" else "width").coerceIn(0, 100_000),
                    imageHeight = row.optInt(if (original.isBlank()) "thumbHeight" else "height").coerceIn(0, 100_000)
                ))
                if (size >= limit) break
            }
        }
    }

    private fun publicUrl(value: String, httpsOnly: Boolean = true): String = runCatching {
        require(value.length <= 4_096)
        val uri = URI(value.trim())
        require(uri.scheme == "https" || (!httpsOnly && uri.scheme == "http"))
        require(!uri.host.isNullOrBlank() && uri.rawUserInfo == null)
        require(!uri.host.equals("localhost", true) && !uri.host.endsWith(".local", true))
        uri.toASCIIString()
    }.getOrDefault("")
}
