package com.galaxyssi.chat

import java.io.Closeable
import java.util.Base64
import org.json.JSONObject

internal object AgentResultRecoveryPageCodec {
    class Page(val manifest: AgentResultPageManifest, val bytes: ByteArray) : Closeable {
        override fun close() { bytes.fill(0) }
    }

    fun bindInline(observation: JSONObject, desktop: String, queryNonce: String): JSONObject? {
        val page = observation.optJSONObject("result_page") ?: return null
        if (observation.optString("status") !in AgentRemoteOutcomeCodec.TERMINAL ||
            page.opt("request_id") != queryNonce || !matches(page, observation) ||
            (page.has("desktop_id") && page.opt("desktop_id") != desktop)) return null
        val encoded = page.opt("data_b64") as? String ?: return null
        if (encoded.length > MAX_ENCODED) return null
        val fields = AgentResultRecoveryClient.FIELDS + listOf("type", "request_id", "status", "page_index",
            "execution_generation", "sha256", "total_bytes", "page_count", "page_sha256", "data_b64")
        return JSONObject().also { copy ->
            fields.forEach { name -> if (page.has(name)) copy.put(name, page.get(name)) }
            copy.put("desktop_id", desktop)
        }
    }

    fun inlineMatches(page: JSONObject, desktop: String, fields: JSONObject): Boolean =
        page.opt("desktop_id") == desktop && matches(page, fields)

    private fun matches(page: JSONObject, fields: JSONObject): Boolean {
        val expected = AgentRemoteOutcomeCodec.version(fields) ?: return false
        val nonce = page.opt("request_id") as? String ?: return false
        return page.opt("type") == "agent_task_result_page" && page.opt("status") == "ready" &&
            integer(page, "page_index") == 0L && nonce.length in 1..128 &&
            AgentRemoteOutcomeCodec.version(page)?.generation == expected.generation &&
            AgentResultRecoveryClient.FIELDS.all { page.opt(it) is String && page.opt(it) == fields.optString(it) }
    }

    fun decode(value: JSONObject, index: Int): Page? {
        if (value.opt("status") != "ready" || integer(value, "page_index") != index.toLong()) return null
        val total = integer(value, "total_bytes") ?: return null
        val count = integer(value, "page_count")?.takeIf { it in 1..Int.MAX_VALUE }?.toInt() ?: return null
        val manifest = AgentResultPageManifest(value.optString("sha256"), total, count)
        if (!manifest.valid() || index !in 0 until count) return null
        val encoded = value.opt("data_b64") as? String ?: return null
        if (encoded.length > MAX_ENCODED) return null
        val raw = runCatching { Base64.getDecoder().decode(encoded) }.getOrNull() ?: return null
        val hash = AgentResultRecoveryClient.sha256(raw)
        if (raw.size != manifest.pageBytes(index) || hash != value.opt("page_sha256") ||
            (count == 1 && hash != manifest.digest)) {
            raw.fill(0)
            return null
        }
        return Page(manifest, raw)
    }

    private fun integer(value: JSONObject, name: String): Long? = when (val number = value.opt(name)) {
        is Int -> number.toLong()
        is Long -> number
        else -> null
    }

    private const val MAX_ENCODED = ((AgentResultRecoveryClient.PAGE_BYTES + 2) / 3) * 4
}
