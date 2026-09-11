package com.galaxyssi.chat

import java.net.URI

/** Presentation policy for discovered images, not a claim of visual verification. */
internal object CloudImageSearchEvidence {
    private val itemFields = setOf("citation_id", "source_kind", "evidence_level", "url", "title",
        "content_sha256", "rank", "published_at", "retrieved_at_millis", "media_evidence_level")

    fun prepare(output: AgentNativeJsonObject): AgentNativeJsonObject {
        val pack = output["evidence_pack"] as? Map<*, *> ?: return output
        val items = (pack["items"] as? Iterable<*>)?.mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            val images = (item["images"] as? Iterable<*>)?.mapNotNull { entry ->
                val media = entry as? Map<*, *> ?: return@mapNotNull null
                val original = media["url"]?.toString().orEmpty()
                val preview = media["thumbnail_url"]?.toString().orEmpty().takeIf(::secureUrl)
                media.entries.associate { it.key.toString() to it.value }.toMutableMap().apply {
                    if (preview != null && preview != original) {
                        put("url", preview)
                        put("original_url", original)
                        put("display_kind", "search_preview")
                        // Original dimensions do not describe the smaller search preview.
                        remove("width")
                        remove("height")
                    }
                }
            }.orEmpty()
            item.entries.filter { it.key in itemFields }.associate { it.key.toString() to it.value }.toMutableMap().apply {
                put("excerpt", item["excerpt"]?.toString().orEmpty().take(240))
                put("images", images)
            }
        }.orEmpty()
        val contract = (pack["synthesis_contract"] as? Map<*, *>)?.entries
            ?.associate { it.key.toString() to it.value }.orEmpty() + mapOf(
            "image_response" to mapOf(
                "format" to "Markdown images with source links; no duplicate JSON galleries",
                "selection" to "Show the requested subject itself. Do not fill a count with adjacent topics. " +
                    "For an object or species, prefer identity/appearance sources over recipes or comparison pages. " +
                    "Check each image's own title/alt, not only the parent page title. Preserve all requested " +
                    "subjects and qualifiers such as interior, exterior, diagram or real photograph. " +
                    "If evidence is insufficient, refine the query instead of filling the count with off-topic pictures.",
                "display" to "Use images.url, a search preview where available. Keep original_url for an explicit " +
                    "original-resolution request; it has not been downloaded or validated.",
                "verification" to "Titles and source relevance are evidence, not visual identification."
            ))
        val prepared = pack.entries.associate { it.key.toString() to it.value }.toMutableMap().apply {
            put("items", items)
            put("synthesis_contract", contract)
            put("presentation", "compact_image_candidates")
        }
        return output + ("evidence_pack" to AgentWebEvidenceVerification.attach(prepared))
    }

    private fun secureUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        value.length <= 4_096 && uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null
    }.getOrDefault(false)
}
