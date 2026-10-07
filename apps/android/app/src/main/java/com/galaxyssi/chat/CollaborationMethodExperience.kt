package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Host observations of method use, not scientific evaluations or model-authored memories. */
internal class CollaborationMethodExperience(private val rows: CollaborationWorkspaceRows, private val group: String) {
    private val root = "group:${hash(group)}:method-use:"

    fun record(access: CollaborationWorkspaceAccess, method: JSONObject, binding: JSONObject,
               record: AgentTeamExecutionRecord, member: AgentTeamMember, result: AgentSubagentChildResult) {
        require(result.supervisorId == record.request.runId && result.childId == member.memberId && result.status.isTerminal)
        val value = JSONObject().put("group_id", group).put("run_id", access.runId).put("turn_id", access.turnId)
            .put("round", access.round).put("node_id", access.nodeId).put("person_id", access.personId)
            .put("method", method).put("binding", binding).put("work_id", member.context[CollaborationGoalLoop.WORK_ID].orEmpty())
            .put("goal", record.request.goal).put("assignment", member.objective)
            .put("agent_id", member.agentId).put("selected_model_id", member.context["collaboration_model_id"].orEmpty())
            .put("status", result.status.name.lowercase()).put("error", result.errorMessage)
            .put("started_at", result.startedAtMillis).put("completed_at", result.completedAtMillis)
            .put("elapsed_ms", if (result.startedAtMillis > 0 && result.completedAtMillis >= result.startedAtMillis)
                result.completedAtMillis - result.startedAtMillis else JSONObject.NULL)
            .put("output_sha256", hash(result.output)).put("output_truncated", result.outputTruncated)
            .put("delivery", result.collaborationDelivery?.encode() ?: JSONObject.NULL)
            .put("quality_effect", JSONObject.NULL).put("causal_contribution", JSONObject.NULL)
            .put("trust", "host_execution_observation_not_method_effectiveness")
        val id = hash(canonical(value))
        val key = root + "record:" + id
        // Replayed completion events do not create new experience or change the original facts.
        if (rows.read(key) != null) return
        value.put("record_id", id)
        value.put("sha256", hash(value.toString()))
        val index = index(method) + result.completedAtMillis.coerceAtLeast(0).toString().padStart(19, '0') + ":" + id
        rows.commit(mapOf(key to value.toString(), index to id))
    }

    fun browse(access: CollaborationWorkspaceAccess, method: JSONObject, cursor: String): JSONObject {
        val prefix = index(method)
        val scope = hash(JSONArray().put(access.groupId).put(access.runId).put(access.turnId).put(access.round)
            .put(access.nodeId).put(access.personId).put(JSONArray(access.dependencyNodes.sorted()))
            .put(method.getString("sha256")).toString())
        require(cursor.length <= 512) { "Method history cursor is too long" }
        val after = if (cursor.isBlank()) "" else {
            val value = try { JSONObject(cursor) } catch (_: Exception) { throw IllegalArgumentException("Invalid method history cursor") }
            require(value.optString("scope") == scope) { "Method or assignment changed; restart without cursor" }
            value.getString("after").also {
                require(it.startsWith(prefix) && it.removePrefix(prefix).matches(Regex("[0-9]{19}:[a-f0-9]{64}"))) { "Invalid method history cursor" }
            }
        }
        val keys = rows.page(prefix, after, 21)
        val selected = keys.take(20)
        val records = selected.mapNotNull { key ->
            val saved = read(access, requireNotNull(rows.read(key))) ?: return@mapNotNull null
            require(CollaborationResearchCandidates.same(method, saved.getJSONObject("method"))) { "Method history index changed" }
            JSONObject().apply {
                listOf("record_id", "sha256", "run_id", "turn_id", "node_id", "person_id", "work_id", "status",
                    "started_at", "completed_at", "elapsed_ms", "output_sha256", "output_truncated", "quality_effect")
                    .forEach { put(it, saved.get(it)) }
                saved.optJSONObject("delivery")?.let { delivery ->
                    put("delivery_status", delivery.optString("status"))
                    put("archive_record_id", delivery.optString("archive_record_id"))
                }
            }
        }
        val next = if (keys.size > selected.size) JSONObject().put("scope", scope).put("after", selected.last()).toString() else null
        return JSONObject().put("method", method).put("records", JSONArray(records)).put("next_cursor", next ?: JSONObject.NULL)
            .put("snapshot", false).put("trust", "host_execution_observation_not_method_effectiveness")
            .put("guidance", "Records are terminal observations, not independent attempts or quality measurements. " +
                "A late recovery can add a newer observation for the same node; compare identities and times. " +
                "Follow next_cursor even after an empty page. Read record_id/offset for conditions and errors. " +
                "No records means unknown history, not an unused or reliable method. Independent validation is still required.")
    }

    fun read(access: CollaborationWorkspaceAccess, id: String): JSONObject? {
        require(id.matches(Regex("[a-f0-9]{64}"))) { "Invalid method history record ID" }
        val value = rows.read(root + "record:" + id)?.let(::JSONObject) ?: return null
        val body = JSONObject(value.toString()).apply { remove("sha256") }
        require(value.getString("record_id") == id && value.getString("group_id") == group &&
            hash(body.toString()) == value.getString("sha256")) { "Method history integrity check failed" }
        return value.takeIf(access::canRead)
    }

    private fun index(method: JSONObject) = root + "index:" + method.getString("sha256") + ":"

    companion object {
        val TASKS = mapOf(CollaborationWorkflowWork.TASK to "method", CollaborationProcedureWork.TASK to "procedure")

        fun capture(record: AgentTeamExecutionRecord, provider: (() -> CollaborationResearchWorkspace)?) {
            val latest = record.events.lastOrNull()?.result?.takeIf { it.status.isTerminal } ?: return
            if (record.definition.members.none { it.memberId == latest.childId && TASKS.keys.any(it.context::containsKey) }) return
            val result = if (CollaborationTeamOrganization.enabled(record)) {
                val projection = CollaborationTeamOrganizationProjection.current(record)
                if (!projection.safeToApply) return
                projection.verifiedResults[latest.childId] ?: return
            } else latest
            provider?.invoke()?.recordMethodExperience(record, result)
        }

        private fun hash(value: String) = AgentNativeJsonCodec.sha256(value)
        private fun canonical(value: Any?): String = when (value) {
            is JSONObject -> value.keys().asSequence().sorted().joinToString(prefix = "{", postfix = "}") {
                JSONObject.quote(it) + ":" + canonical(value.get(it))
            }
            is JSONArray -> (0 until value.length()).joinToString(prefix = "[", postfix = "]") { canonical(value.get(it)) }
            is String -> JSONObject.quote(value)
            null, JSONObject.NULL -> "null"
            else -> value.toString()
        }
    }
}
