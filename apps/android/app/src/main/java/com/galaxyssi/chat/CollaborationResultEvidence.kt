package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Readiness for publication validation, never a receipt that a claim or goal was verified. */
internal class CollaborationResultEvidence private constructor(
    private val references: Set<Reference>,
    private val malformed: Boolean
) {
    private data class Reference(val id: String, val hash: String)

    fun awaiting(archivePending: () -> Boolean, original: (String) -> JSONObject?): Boolean {
        // Invalid submissions need validator feedback; an archive import cannot repair their schema.
        if (malformed || references.isEmpty() || !archivePending()) return false
        var missing = false
        for (ref in references) {
            val saved = original(ref.id)
            if (saved == null) missing = true
            else if (saved.getString("sha256") != ref.hash) return false
        }
        return missing
    }

    companion object {
        private val DIGEST = Regex("[a-f0-9]{64}")

        fun inspect(raw: String): CollaborationResultEvidence {
            val changes = CollaborationResearchArtifact.decode(raw)?.optJSONArray("workspace")
                ?: return CollaborationResultEvidence(emptySet(), false)
            val refs = linkedSetOf<Reference>()
            var malformed = false
            val pending = ArrayDeque<Any>()
            repeat(changes.length()) { index ->
                val item = changes.optJSONObject(index)
                if (item == null) malformed = true
                else {
                    if (item.has("observations") && item.optJSONArray("observations") == null) malformed = true
                    item.optJSONArray("observations")?.let { observations ->
                        repeat(observations.length()) { position ->
                            if (observations.optJSONObject(position)?.has("evidence_id") != true) malformed = true
                        }
                        pending.addLast(observations)
                    }
                    item.optJSONObject("body")?.let(pending::addLast)
                }
            }
            // Typed experiment/probe bodies can contain exact receipts below nested objects/arrays.
            // Prose, model-supplied host receipts and already published milestone IDs are not imports.
            while (pending.isNotEmpty()) {
                when (val value = pending.removeLast()) {
                    is JSONObject -> {
                        if (value.has("evidence_id")) {
                            val id = value.opt("evidence_id") as? String
                            val hash = value.opt("sha256") as? String
                            if (id == null || hash == null || !DIGEST.matches(id) || !DIGEST.matches(hash)) malformed = true
                            else refs.add(Reference(id, hash))
                        }
                        value.keys().forEach { key ->
                            value.opt(key)?.takeIf { it is JSONObject || it is JSONArray }?.let(pending::addLast)
                        }
                    }
                    is JSONArray -> repeat(value.length()) { index ->
                        value.opt(index)?.takeIf { it is JSONObject || it is JSONArray }?.let(pending::addLast)
                    }
                }
            }
            return CollaborationResultEvidence(refs, malformed)
        }
    }
}
