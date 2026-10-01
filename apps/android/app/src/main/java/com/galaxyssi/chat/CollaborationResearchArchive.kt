package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Immutable originals and keyed full-text retrieval, isolated from personal memory and other groups. */
internal class CollaborationResearchArchive(private val context: Context, private val groupId: String) {
    private val name = databaseName(groupId)
    private fun store() = SQLiteAgentKnowledgeStore(context, name, "${name}_legacy", publish = { _, _ -> })

    fun record(execution: AgentTeamMemberExecutionContext, raw: String, input: Boolean = false): String {
        if (groupId.isBlank() || CollaborationGroupStore(context).load(groupId) == null) return ""
        val member = execution.member
        val id = AgentNativeJsonCodec.sha256("${execution.request.parentRunId}:${member.memberId}:$input:$raw")
        val document = JSONObject().put("id", id).put("group_id", groupId)
            .put("run_id", execution.request.parentRunId).put("node_id", member.memberId)
            .put("turn_id", execution.request.messageId).put("task_id", execution.request.taskId)
            .put("member_id", member.context[CollaborationResearchWorkflow.PERSON].orEmpty().ifBlank { member.memberId })
            .put("name", member.context["collaboration_name"]).put("stage", member.context[CollaborationResearchWorkflow.STAGE])
            .put("record_type", if (input) "assignment" else "result")
            .put("provider_id", member.agentId).put("model_id", member.context["collaboration_model_id"])
            .put("goal", execution.request.goal).put("raw_output", raw)
            .put("memory", CollaborationResearchArtifact.decode(raw)?.optJSONArray("memory") ?: org.json.JSONArray())
            .put("dependencies", org.json.JSONArray(member.dependsOnAgentIds.toList()))
            .put("inbox", org.json.JSONArray(execution.request.context["team_messages"] as? List<*> ?: emptyList<Any>()))
            .put("evidence_status", "model_reported_not_host_verified")
        synchronized(LOCK) {
            if (CollaborationGroupStore.cached(groupId) == null) return ""
            val storage = store()
            if (storage.findByIds(setOf(id)).isEmpty()) storage.upsert(AgentKnowledgeItem(
                id = id, kind = AgentKnowledgeKind.TASK,
                title = "${member.context["collaboration_name"]}: ${member.context[CollaborationResearchWorkflow.STAGE].orEmpty()} ${execution.request.goal.take(120)}",
                content = document.toString(), summary = (CollaborationResearchArtifact.memoryText(raw).take(900) + "\n" +
                    CollaborationResearchArtifact.publicText(raw).take(1500)).trim(),
                source = "group:$groupId:$id", tags = listOf("group-research", "unverified"),
                cloudAccess = AgentKnowledgeCloudAccess.DENY, agentAccess = AgentKnowledgeAgentAccess.LOCAL_ONLY))
        }
        return id
    }

    data class Page(val records: List<AgentKnowledgeItem>, val nextCursor: String?, val total: Int)

    fun browse(cursor: String = "", excludeTurn: String = ""): Page = synchronized(LOCK) {
        if (CollaborationGroupStore(context).load(groupId) == null) return@synchronized Page(emptyList(), null, 0)
        val position = cursor.takeIf(String::isNotBlank)?.let { raw ->
            val json = JSONObject(raw)
            AgentKnowledgeSourceCursor(json.getLong("updated"), json.getString("key"), json.getLong("revision"), json.getString("scope"))
        }
        val storage = store()
        val page = storage.sourcePage(position, 12)
        val ids = page.groups.flatMap { storage.sourceItemIds(requireNotNull(it.reference)) }.toSet()
        val records = storage.findByIds(ids).filter {
            excludeTurn.isBlank() || JSONObject(it.content).optString("turn_id") != excludeTurn
        }
        Page(records, page.next?.let {
            JSONObject().put("updated", it.updated).put("key", it.groupKey).put("revision", it.revision).put("scope", it.scope).toString()
        }, page.total)
    }

    fun search(query: String, limit: Int = 6, excludeTurn: String = ""): List<AgentKnowledgeItem> {
        if (CollaborationGroupStore(context).load(groupId) == null) return emptyList()
        return synchronized(LOCK) {
            if (CollaborationGroupStore.cached(groupId) == null) emptyList()
            else (if (query.isBlank()) store().list(48) else store().search(query.take(1000), 48))
                .filter { excludeTurn.isBlank() || JSONObject(it.content).optString("turn_id") != excludeTurn }
                .take(limit.coerceIn(1, 12))
        }
    }

    fun read(id: String): AgentKnowledgeItem? {
        if (!id.matches(Regex("[a-f0-9]{64}")) || CollaborationGroupStore(context).load(groupId) == null) return null
        return synchronized(LOCK) {
            if (CollaborationGroupStore.cached(groupId) == null) null else store().findByIds(setOf(id)).singleOrNull()
        }
    }

    fun context(query: String, excludeTurn: String): String = search(query, excludeTurn = excludeTurn).joinToString("\n\n") {
        "record_id=${it.id}; recorded_at=${it.updatedAtMillis}; ${it.title}\n${it.summary.take(750)}"
    }.take(5_500)

    companion object {
        private val LOCK = Any()
        private fun databaseName(group: String) = "galaxyssi_group_research_${AgentNativeJsonCodec.sha256(group)}.db"

        fun remove(context: Context, group: String) = synchronized(LOCK) {
            val name = databaseName(group)
            AgentKnowledgeDatabase.release(context, name)
            val path = context.getDatabasePath(name)
            // Paths are derived from a SHA-256 ID, never a caller-provided filesystem path.
            listOf(".primary", ".payloads").forEach { suffix -> java.io.File(path.absolutePath + suffix).deleteRecursively() }
            context.deleteDatabase(name)
        }
    }
}
