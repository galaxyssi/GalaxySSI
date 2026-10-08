package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Offered versions are durable read grants, not evidence of delivery, comprehension or verification. */
internal class CollaborationCoordinatorJournal(
    private val rows: CollaborationWorkspaceRows,
    private val access: CollaborationWorkspaceAccess
) {
    private val scope = MqttImmutableContent.sha256(JSONArray().put(access.groupId).put(access.runId)
        .put(access.turnId).put(access.round).put(access.nodeId).put(access.personId)
        .put(JSONArray(access.dependencyNodes.sorted())).put(JSONArray(access.pinnedReads.sorted())).toString())
    private val prefix = "group:${MqttImmutableContent.sha256(access.groupId)}:coordinator-updates:$scope:"

    fun offered(): List<JSONObject> = state().getJSONArray("offered").let { array ->
        (0 until array.length()).map(array::getJSONObject)
    }

    fun page(cursor: String, pending: (Set<String>) -> List<JSONObject>): JSONObject {
        val saved = state()
        val head = saved.getInt("pages")
        val index = if (cursor.isEmpty()) 0 else {
            require(cursor.startsWith("$scope:")) { "Updates cursor belongs to another assignment" }
            cursor.removePrefix("$scope:").toIntOrNull()?.also {
                require(it >= 0 && cursor == "$scope:$it") { "Invalid updates cursor" }
            } ?: throw IllegalArgumentException("Invalid updates cursor")
        }
        require(index <= head) { "Updates cursor is ahead of the saved journal" }
        if (index < head) return JSONObject(requireNotNull(rows.read("${prefix}page:$index")))
        val prior = offered()
        val additions = pending(prior.mapTo(hashSetOf()) { it.getString("token") })
        require(additions.map { it.getString("token") }.distinct().size == additions.size &&
            additions.none { item -> prior.any { it.getString("token") == item.getString("token") } }) {
            "Duplicate coordinator update"
        }
        val result = JSONObject().put("milestones", JSONArray(additions.map { JSONObject(it.toString()).apply { remove("grants") } }))
            .put("next_cursor", "$scope:${if (additions.isEmpty()) head else head + 1}")
            .put("caught_up_at_read", additions.isEmpty())
            .put("trust", "published_member_reports_not_verified_or_complete")
            .put("guidance", "Read exact workspace revisions and evidence pages before judging sufficiency. " +
                "Follow next_cursor; an empty page means no new published versions at this read. Reuse that cursor later. " +
                "The original goal/context snapshot is unchanged. This does not expose unpublished work or finish any task.")
        // Commit the immutable replay page and exact offered-version grants together.
        if (additions.isNotEmpty()) rows.commit(mapOf("${prefix}page:$index" to result.toString(),
            "${prefix}state" to JSONObject().put("pages", head + 1).put("offered", JSONArray(prior + additions)).toString()))
        return result
    }

    private fun state() = rows.read("${prefix}state")?.let(::JSONObject)
        ?: JSONObject().put("pages", 0).put("offered", JSONArray())
}
