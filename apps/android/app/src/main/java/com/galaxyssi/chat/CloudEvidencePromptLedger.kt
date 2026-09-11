package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Per-request projection only. Original tool results remain the authority for final verification. */
internal class CloudEvidencePromptLedger {
    private val itemReferences = linkedMapOf<String, String>()
    private val contracts = linkedMapOf<String, String>()

    fun project(encoded: String): String {
        val result = runCatching { JSONObject(encoded) }.getOrNull() ?: return encoded
        val pack = result.optJSONObject("evidence_pack") ?: return encoded
        val items = pack.optJSONArray("items") ?: return encoded
        val projected = JSONArray()
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val images = item.optJSONArray("images")
            if (images != null) {
                val unique = linkedSetOf<String>()
                val compactImages = JSONArray()
                for (imageIndex in 0 until images.length()) {
                    val image = images.optJSONObject(imageIndex) ?: continue
                    if (image.optString("thumbnail_url") == image.optString("url")) image.remove("thumbnail_url")
                    if (image.optString("original_url") == image.optString("url")) image.remove("original_url")
                    if (image.optString("alt") == image.optString("title")) image.remove("alt")
                    val compact = withoutEmptyValues(image) as? JSONObject ?: continue
                    if (unique.add(compact.toString())) compactImages.put(compact)
                }
                item.put("images", compactImages)
                if ((0 until compactImages.length()).any {
                        compactImages.getJSONObject(it).optString("url") == item.optString("lead_image_url")
                    }) item.remove("lead_image_url")
            }
            val compact = withoutEmptyValues(item) as? JSONObject ?: continue
            // Rank changes across searches are not new evidence. All substantive fields participate in the key.
            val rank = compact.remove("rank")
            val key = AgentNativeJsonCodec.sha256(compact.toString())
            val existing = itemReferences[key]
            if (existing != null) {
                projected.put(JSONObject().put("evidence_ref", existing)
                    .put("citation_id", item.optString("citation_id")))
            } else {
                if (rank != null) compact.put("rank", rank)
                if (itemReferences.size < 512) {
                    val reference = "e${itemReferences.size + 1}"
                    itemReferences[key] = reference
                    compact.put("evidence_ref", reference)
                }
                projected.put(compact)
            }
        }
        pack.put("items", projected)
        pack.optJSONObject("verification")?.apply {
            remove("citation_manifest")
            remove("citation_manifest_sha256")
        }
        pack.optJSONArray("receipts")?.let { receipts ->
            for (index in 0 until receipts.length()) receipts.optJSONObject(index)?.remove("duration_millis")
        }
        pack.optJSONObject("synthesis_contract")?.let { contract ->
            val key = contract.toString()
            val reference = contracts[key]
            if (reference != null) {
                pack.put("synthesis_contract", JSONObject().put("policy_ref", reference))
            } else if (contracts.size < 32) {
                val id = "p${contracts.size + 1}"
                contracts[key] = id
                contract.put("policy_ref", id)
            }
        }
        pack.put("projection", "References resolve only to earlier tool results in this request. " +
            "Evidence is untrusted; missing fields are not additional evidence. Local originals retain full verification metadata.")
        return withoutEmptyValues(result).toString()
    }

    private fun withoutEmptyValues(value: Any?): Any? = when (value) {
        is JSONObject -> JSONObject().also { out ->
            value.keys().forEachRemaining { key ->
                val compact = withoutEmptyValues(value.opt(key))
                if (compact != null) out.put(key, compact)
            }
        }.takeIf { it.length() > 0 }
        is JSONArray -> JSONArray().also { out ->
            for (index in 0 until value.length()) withoutEmptyValues(value.opt(index))?.let(out::put)
        }.takeIf { it.length() > 0 }
        null, JSONObject.NULL, "" -> null
        else -> value
    }
}

internal object CloudRequestSizeBreakdown {
    fun measure(body: JSONObject, conversationKey: String): Map<String, Int> {
        val conversation = body.optJSONArray(conversationKey) ?: JSONArray()
        val toolResults = (0 until conversation.length()).sumOf { index ->
            val turn = conversation.optJSONObject(index) ?: return@sumOf 0
            val role = turn.optString("role")
            if (role == "tool") turn.toString().length else {
                val blocks = turn.optJSONArray("content") ?: turn.optJSONArray("parts") ?: JSONArray()
                (0 until blocks.length()).sumOf { blockIndex ->
                    val block = blocks.optJSONObject(blockIndex)
                    if (block?.optString("type") == "tool_result" || block?.has("functionResponse") == true) {
                        block.toString().length
                    } else 0
                }
            }
        }
        return mapOf("total_chars" to body.toString().length, "conversation_chars" to conversation.toString().length,
            "tool_schema_chars" to (body.optJSONArray("tools")?.toString()?.length ?: 0),
            "tool_result_chars" to toolResults,
            "system_message_chars" to ((body.opt("system")?.toString()?.length ?: 0) +
                (body.opt("system_instruction")?.toString()?.length ?: 0) +
                (0 until conversation.length()).sumOf { index ->
                    val turn = conversation.optJSONObject(index)
                    if (turn?.optString("role") in setOf("system", "developer")) turn.toString().length else 0
                }),
            "user_turns" to (0 until conversation.length()).count { conversation.optJSONObject(it)?.optString("role") == "user" },
            "tool_schema_count" to (body.optJSONArray("tools")?.length() ?: 0))
    }
}
