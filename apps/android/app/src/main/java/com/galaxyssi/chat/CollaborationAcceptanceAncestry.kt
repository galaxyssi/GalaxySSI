package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Exact prior-version and declared-parent provenance, never a scientific truth verdict. */
internal object CollaborationAcceptanceAncestry {
    private val idPattern = Regex("[a-f0-9]{64}")
    private data class Frame(val key: Pair<String, Int>, val parents: JSONArray,
                             var previous: JSONObject?, var nextParent: Int = 0)

    fun contributors(root: JSONObject, read: (String, Int) -> JSONObject?): Set<String> {
        CollaborationReviewContract.validateReference(root)
        val pending = java.util.ArrayDeque<Frame>()
        val active = hashSetOf<Pair<String, Int>>()
        val inspectedDigests = hashMapOf<Pair<String, Int>, String>()
        val authors = linkedSetOf<String>()
        fun enter(ref: JSONObject) {
            val id = ref.getString("object_id")
            val version = CollaborationRemoteEvidenceProtocol.integer(ref, "revision")
            require(id.matches(idPattern) && version != null && version in 1..Int.MAX_VALUE.toLong()) {
                "Invalid exact ancestry reference"
            }
            val key = id to version.toInt()
            inspectedDigests[key]?.let { digest ->
                require(!ref.has("sha256") || ref.opt("sha256") == digest) { "Delivery ancestor digest changed" }
                require(key !in active) { "Delivery ancestry contains a cycle" }
                return
            }
            val saved = requireNotNull(read(id, version.toInt())) { "Delivery ancestry is incomplete or isolated" }
            require(!ref.has("sha256") || ref.opt("sha256") == saved.getString("sha256")) { "Delivery ancestor digest changed" }
            inspectedDigests[key] = saved.getString("sha256")
            active.add(key)
            val author = saved.getString("person_id")
            require(author.isNotBlank()) { "Delivery ancestor has no host author" }
            authors.add(author)
            val previous = if (version > 1) {
                JSONObject().put("object_id", id).put("revision", version - 1)
                    .put("sha256", saved.getString("previous_sha256"))
                    .also(CollaborationReviewContract::validateReference)
            } else {
                require(saved.getString("previous_sha256").isEmpty()) { "Initial ancestry revision has a previous digest" }
                null
            }
            pending.addLast(Frame(key, saved.getJSONArray("parents"), previous))
        }
        enter(root)
        // Advance one exact edge at a time; shared nodes retain only their checked digest, not their bodies.
        while (pending.isNotEmpty()) {
            val frame = pending.peekLast()
            val previous = frame.previous
            when {
                previous != null -> {
                    frame.previous = null
                    enter(previous)
                }
                frame.nextParent < frame.parents.length() -> enter(frame.parents.getJSONObject(frame.nextParent++))
                else -> {
                    active.remove(frame.key)
                    pending.removeLast()
                }
            }
        }
        return authors
    }
}
