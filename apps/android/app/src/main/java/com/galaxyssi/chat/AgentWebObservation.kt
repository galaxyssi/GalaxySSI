package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Give the planner evidence, not cache statistics or a broken slice of a JSON document. */
internal object AgentWebObservation {
    fun compact(value: String, maximumCharacters: Int, preserveReceipt: Boolean = false): String? {
        val source = runCatching { JSONObject(value) }.getOrNull() ?: return null
        if (source.optString("protocol") != "galaxyssi.web-intelligence.v1" &&
            !source.has("evidence_pack")) return null
        val root = JSONObject()
        root.put("protocol", "galaxyssi.web-intelligence.v1")
        listOf("operation", "query", "status", "url").forEach { key ->
            if (source.has(key)) root.put(key, source.optString(key).take(512))
        }
        val receipt = source.optJSONObject("_observation_receipt")
        if (receipt != null) root.put("_observation_receipt", if (preserveReceipt) receipt else JSONObject().apply {
            listOf("invocation_id", "tool_id", "status").forEach { put(it, receipt.optString(it)) }
        })
        val pack = source.optJSONObject("evidence_pack")
        val items = pack?.optJSONArray("items") ?: source.optJSONArray("results") ?: JSONArray()
        val result = JSONArray()
        if (pack != null) root.put("evidence_pack", JSONObject().put("items", result))
        else root.put("results", result)
        root.put("truncated", false)
        run {
            val receipts = source.optJSONArray("receipts")
            val failures = JSONArray()
            for (index in 0 until (receipts?.length() ?: 0)) {
                val r = receipts?.optJSONObject(index) ?: continue
                failures.put(JSONObject().put("source_id", r.optString("source_id"))
                    .put("status", r.optString("status")).put("error_code", r.optString("error_code")))
                if (failures.length() >= 3) break
            }
            if (failures.length() > 0) root.put("receipts", failures)
        }
        val budget = maximumCharacters.coerceAtLeast(1)
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val compact = JSONObject()
            listOf("title", "url", "citation_id", "published_at", "evidence_level", "media_evidence_level").forEach { key ->
                item.optString(key).takeIf(String::isNotBlank)?.let { compact.put(key, it) }
            }
            val images = item.optJSONArray("images")
            val image = images?.optJSONObject(0)?.optString("url").orEmpty()
            if (image.isNotBlank()) compact.put("images", JSONArray().put(JSONObject().put("url", image)))
            listOf("image_url", "thumbnail_url").forEach { key ->
                item.optString(key).takeIf(String::isNotBlank)?.let { compact.put(key, it) }
            }
            listOf("excerpt", "content").forEach { key ->
                item.optString(key).takeIf(String::isNotBlank)?.let { compact.put(key, it.take(500)) }
            }
            result.put(compact)
            if (root.toString().length > budget) {
                compact.remove("excerpt")
                compact.remove("content")
                if (root.toString().length > budget) {
                    result.remove(result.length() - 1)
                    break
                }
            }
        }
        val documents = source.optJSONArray("documents")
        if (result.length() == 0 && documents != null) {
            val documentResults = JSONArray()
            root.put("documents", documentResults)
            for (index in 0 until documents.length()) {
                val item = documents.optJSONObject(index) ?: continue
                val compact = JSONObject()
                listOf("title", "url", "content_sha256").forEach { compact.put(it, item.optString(it)) }
                val contentBudget = (budget - root.toString().length - compact.toString().length - 100).coerceAtLeast(0)
                compact.put("content", item.optString("content").take(contentBudget / 2))
                documentResults.put(compact)
                if (root.toString().length > budget) { documentResults.remove(documentResults.length() - 1); break }
            }
        }
        root.put("truncated", source.optBoolean("truncated") ||
            result.length() < items.length() || source.toString().length > budget)
        if (root.toString().length <= budget) return root.toString()
        if (!preserveReceipt) root.remove("_observation_receipt")
        root.remove("query")
        if (root.toString().length <= budget) return root.toString()
        return """{"truncated":true}""".takeIf { it.length <= budget }
    }
}
