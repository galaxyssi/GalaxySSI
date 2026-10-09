package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A work contract opts into named peers; a sender cannot relax another member's isolation. */
internal object CollaborationPeerExchangePolicy {
    const val FIELD = "peer_updates_from"
    const val CONTEXT = "collaboration_research_peer_updates_from"
    const val RECIPIENT_INSTRUCTIONS = "Address requests[].to using exact member IDs from the supplied roster. " +
        "IDs are opaque strings, not necessarily UUIDs; copy them unchanged, never invent a UUID or substitute a display name. " +
        "A coordination request asks the coordinator to assess work; it does not address a peer. " +
        "To offer a result to a peer, publish requests with that recipient ID and the relevant exact workspace versions. "
    const val INSTRUCTIONS = "For useful communication during execution, a work item may set peer_updates_from:[exact roster member IDs]. " +
        "Only explicitly addressed interim publications from these peers can enter that assignment. Omitted/empty keeps it isolated; " +
        "independent_review assignments remain frozen and cannot opt in. Choose peers whose evidence can change an action, not all members by default. " +
        "This is not a completion dependency, model wakeup or permission to change an already admitted work contract. "

    fun read(item: JSONObject): Set<String> {
        if (!item.has(FIELD)) return emptySet()
        val values = requireNotNull(item.optJSONArray(FIELD)) { "$FIELD must be an array of exact member IDs" }
        val result = linkedSetOf<String>()
        repeat(values.length()) { index ->
            val value = values.opt(index) as? String
            require(!value.isNullOrBlank() && value == value.trim() && value.length <= AgentTeamMessageEnvelope.MAX_ID_CHARS &&
                value != item.optString("member") && result.add(value)) { "$FIELD requires distinct other member IDs" }
        }
        require(result.isEmpty() || !item.optBoolean("independent_review")) { "Independent reviews cannot receive live peer updates" }
        return result
    }

    fun context(item: JSONObject): Map<String, String> = mapOf(CONTEXT to JSONArray(read(item).sorted()).toString())
    fun allowed(member: AgentTeamMember): Set<String> = member.context[CONTEXT]?.let(::JSONArray)?.let { array ->
        read(JSONObject().put("member", member.context[CollaborationResearchWorkflow.PERSON])
            .put("independent_review", member.context[CollaborationWorkGraph.INDEPENDENT] == "true").put(FIELD, array))
    }.orEmpty()

    fun restore(item: JSONObject, member: AgentTeamMember): JSONObject = item.put(FIELD, JSONArray(allowed(member).sorted()))

    fun requests(artifact: JSONObject, recipient: String? = null): JSONArray = JSONArray().apply {
        val requests = artifact.optJSONArray("requests") ?: return@apply
        repeat(requests.length()) { index ->
            val item = requests.getJSONObject(index)
            val to = item.getJSONArray("to").let { array -> (0 until array.length()).map(array::getString).distinct() }
            if (recipient == null || recipient in to) put(JSONObject().put("to", JSONArray(if (recipient == null) to else listOf(recipient)))
                .put("question", item.getString("question").trim()).put("candidate_id", item.optString("candidate_id")))
        }
    }
}
