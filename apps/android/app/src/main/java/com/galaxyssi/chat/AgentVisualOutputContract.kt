package com.galaxyssi.chat

import org.json.JSONObject

/** Presentation is declared by the model, never inferred from keywords in a user's goal. */
internal object AgentVisualOutputContract {
    const val PROMPT = "Prefer a galaxyssi-html fenced block with unescaped complete HTML/CSS/JS for playable animation. " +
        "Visual delivery also supports presentation=inline_html and " +
        "rich_output:{\"version\":1,\"blocks\":[{\"type\":\"html\",\"title\":\"animation.html\",\"text\":\"complete HTML/CSS/JS\",\"fallback_text\":\"description\"}]}. " +
        "Or fence this JSON as galaxyssi-rich in final_response. The phone saves/plays it isolated; no Linux or Playwright required. " +
        "No external assets/network/forms/device APIs. Limit 32000 characters; larger files use workspace export. " +
        "Use presentation=source only for requested source. Video uses presentation=video plus completion_requirements.artifacts " +
        "with observed workspace_id/MP4 path: encode, export actual MP4, verify media metadata. HTML is not video. " +
        "Short discovery terms; zero matches is not inability. Stopped Linux starts on demand via runtime.execute. " +
        "Preserve verified files/hashes on recovery."

    const val COMPACT_PROMPT = "Animations: galaxyssi-html fence with complete self-contained HTML/CSS/JS (no JSON escaping), or rich_output HTML. " +
        "Phone saves/plays privately; no Linux/Playwright, network or device APIs. Code only: presentation=source. " +
        "Video requires declared MP4 artifacts, encoding/export and real media verification; HTML is not video. Preserve files/hashes on recovery."

    fun htmlIssue(html: String): String? = when {
        html.isBlank() -> "empty_html"
        html.length > 32_000 -> "inline_html_too_large_use_workspace_export"
        OPEN_HTML.containsMatchIn(html) && !CLOSE_HTML.containsMatchIn(html) -> "incomplete_html_document"
        OPEN_SCRIPT.findAll(html).count() != CLOSE_SCRIPT.findAll(html).count() -> "incomplete_html_script"
        else -> null
    }

    fun isDocumentCode(block: AgentRichBlock): Boolean = block.type == AgentRichBlockType.CODE &&
        block.language.equals("html", true) && OPEN_HTML.containsMatchIn(block.text)

    fun rejection(raw: String): String? {
        val root = envelope(raw)
        val text = if (root?.optString("disposition") == "respond") root.optString("final_response") else raw
        if (root?.has("rich_output") == true && root.optJSONObject("rich_output") == null)
            return "rich_output requires a JSON object, not an array, string or null"
        root?.optJSONObject("rich_output")?.let { rich ->
            richIssue(rich)?.let { return it }
        }
        for (fence in RICH_FENCE.findAll(text)) {
            val rich = runCatching { JSONObject(fence.groupValues[1]) }.getOrNull()
                ?: return "invalid_rich_output_json"
            richIssue(rich)?.let { return it }
        }
        val blocks = AgentRichContentCodec.fromText(text)
        if (root?.optString("presentation") == "video" && AgentCompletionRequirements.parse(
                root.optJSONObject("completion_requirements"))?.artifacts.orEmpty().none { it.path.endsWith(".mp4", true) }) {
            return "video_delivery_requires_exported_mp4: declare completion_requirements.artifacts for the requested MP4, " +
                "execute and export it with verified media opening evidence; HTML or prose is not a video."
        }
        if (root?.optString("presentation") == "inline_html" &&
            (blocks + AgentRichContentCodec.decode(root.optJSONObject("rich_output")?.toString().orEmpty()))
                .none { it.type == AgentRichBlockType.HTML }) {
            return "inline_html_presentation_requires_rich_output: preserve the complete HTML in a declared HTML block"
        }
        blocks.filter { it.type == AgentRichBlockType.HTML }.forEach {
            htmlIssue(it.text)?.let { reason -> return reason }
        }
        if ((blocks.any(::isDocumentCode) || RAW_DOCUMENT.containsMatchIn(text) && blocks.none { it.type == AgentRichBlockType.HTML }) &&
            root?.optString("presentation") != "source") {
            return "html_source_is_not_animation_delivery: classify the requested presentation. " +
                "Change the fence to galaxyssi-html or use rich_output HTML for playback; presentation=source is only for requested source code. " +
                "Preserve the existing complete HTML; do not regenerate or repeat research. A video needs a real exported media file."
        }
        return null
    }

    fun envelope(raw: String): JSONObject? = runCatching { JSONObject(raw.trim()
        .removePrefix("```json").removePrefix("```JSON").removeSuffix("```").trim()) }.getOrNull()

    private fun richIssue(rich: JSONObject): String? {
        val array = rich.optJSONArray("blocks") ?: return "rich_output requires a blocks array"
        for (index in 0 until array.length()) {
            val block = array.optJSONObject(index) ?: continue
            if (block.optString("type").equals("html", true)) htmlIssue(block.optString("text"))?.let { return it }
        }
        return if (AgentRichContentCodec.normalize(rich.toString()).isBlank()) "rich_output has no renderable content" else null
    }

    private val OPEN_HTML = Regex("<html(?:\\s|>)", RegexOption.IGNORE_CASE)
    private val CLOSE_HTML = Regex("</html\\s*>", RegexOption.IGNORE_CASE)
    private val OPEN_SCRIPT = Regex("<script(?:\\s|>)", RegexOption.IGNORE_CASE)
    private val CLOSE_SCRIPT = Regex("</script\\s*>", RegexOption.IGNORE_CASE)
    private val RAW_DOCUMENT = Regex("(?im)^\\s*(?:<!doctype\\s+html[^>]*>|<html(?:\\s|>))")
    private val RICH_FENCE = Regex("(?ms)^\\s*```galaxyssi-rich[^\\S\\r\\n]*\\r?\\n(.*?)\\r?\\n[ \\t]*```[ \\t]*$")
}
