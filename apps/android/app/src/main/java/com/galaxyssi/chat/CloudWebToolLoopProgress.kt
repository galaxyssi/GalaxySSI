package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

/** Tracks semantic tool progress without imposing a fixed round or call count. */
internal class CloudWebToolLoopProgress {
    private val outputsByCall = linkedMapOf<String, String>()
    private val requestedRepairs = linkedSetOf<String>()
    private val evidenceKeys = linkedSetOf<String>()
    private val unavailableResources = linkedMapOf<String, String>()
    private val retrievedResources = linkedMapOf<String, String>()
    private var stagnantBatches = 0

    fun observeEvidenceBatch(outputs: List<String>): Boolean {
        var gainedEvidence = false
        outputs.forEach { encoded ->
            val output = runCatching { JSONObject(encoded) }.getOrNull() ?: return@forEach
            if (output.optString("tool") == CloudImageAnnotationPlan.TOOL &&
                output.optString("status") == "completed" && output.optBoolean("image_saved")
            ) {
                val hash = output.optString("image_sha256")
                if (hash.matches(Regex("[a-f0-9]{64}")) && evidenceKeys.add("annotation:$hash")) gainedEvidence = true
            }
            val items = output.optJSONObject("evidence_pack")?.optJSONArray("items") ?: JSONArray()
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val url = item.optString("url")
                if (url.isBlank()) continue
                val key = url + "|" + item.optString("content_sha256") + "|" +
                    item.optString("evidence_level") + "|" + canonicalJson(item.optJSONArray("images"))
                if (evidenceKeys.add(key)) gainedEvidence = true
            }
        }
        stagnantBatches = if (gainedEvidence) 0 else stagnantBatches + 1
        return stagnantBatches >= 3
    }

    var finalizationRequested: Boolean = false
        private set

    fun cached(toolName: String, arguments: JSONObject): String? =
        outputsByCall[semanticKey(toolName, arguments)] ?: resourceKey(toolName, arguments)?.let { url ->
            unavailableResources[url] ?: if (canReuseBody(toolName, arguments)) retrievedResources[url] else null
        }

    fun record(toolName: String, arguments: JSONObject, output: String): Boolean {
        val key = semanticKey(toolName, arguments)
        if (outputsByCall.containsKey(key)) return false
        outputsByCall[key] = output
        val errorCode = runCatching { JSONObject(output).optString("error_code") }.getOrDefault("")
        if (errorCode in setOf("web_source_timeout", "renderer_unavailable")) {
            resourceKey(toolName, arguments)?.let { unavailableResources[it] = output }
        }
        if (canReuseBody(toolName, arguments)) {
            val result = runCatching { JSONObject(output) }.getOrNull()
            val items = result?.optJSONObject("evidence_pack")?.optJSONArray("items")
            val requested = resourceKey(toolName, arguments)
            if (result?.optString("status") == "completed" && requested != null && items != null &&
                (0 until items.length()).any { index -> items.optJSONObject(index)?.let {
                    it.optString("evidence_level") == "retrieved_body" &&
                        AgentWebIntelligenceText.canonicalUrl(it.optString("url")) == requested
                } == true }) retrievedResources[requested] = output
        }
        return true
    }

    private fun canReuseBody(toolName: String, arguments: JSONObject): Boolean =
        toolName.lowercase(Locale.ROOT) in setOf("web_fetch", "web_extract") &&
            !arguments.optBoolean("force") && !arguments.has("content") &&
            (arguments.optJSONArray("fields")?.length() ?: 0) == 0 &&
            !arguments.has("focus")

    private fun resourceKey(toolName: String, arguments: JSONObject): String? {
        if (toolName.lowercase(Locale.ROOT) !in setOf("web_fetch", "web_extract", "web_diff")) return null
        val url = arguments.optString("url").trim()
        return url.takeIf { it.isNotBlank() }?.let(AgentWebIntelligenceText::canonicalUrl)
    }

    fun requestRepair(kind: String): Boolean = requestedRepairs.add(kind)

    fun requestFinalization(): Boolean {
        if (finalizationRequested) return false
        finalizationRequested = true
        return true
    }

    internal fun semanticKey(toolName: String, arguments: JSONObject): String {
        val material = toolName.trim().lowercase(Locale.ROOT) + "\u0000" + canonicalJson(arguments)
        return MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun canonicalJson(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") { key ->
            JSONObject.quote(key) + ":" + canonicalJson(value.opt(key))
        }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { index ->
            canonicalJson(value.opt(index))
        }
        is Number, is Boolean -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
}
