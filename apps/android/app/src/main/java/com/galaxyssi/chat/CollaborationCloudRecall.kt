package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import org.json.JSONArray
import org.json.JSONObject

/** Read-only group capability, advertised only for an already bound managed cloud assignment. */
internal object CollaborationCloudRecall {
    const val NAME = CloudGoalPageProtocol.RECALL_TOOL
    private val fields = setOf("mode", "cursor", "query", "object_id", "revision", "evidence_id", "sha256", "offset", "record_id", "topic")

    fun install(prepared: PreparedCloudConversationStream) {
        val properties = JSONObject().put("mode", JSONObject().put("type", "string")
            .put("enum", JSONArray(listOf("evidence", "workspace", "goal_contract", "archive", "evolution", "capabilities", "method_history", "evolution_rules", "problems"))))
        fields.filterNot { it == "mode" }.forEach { field ->
            properties.put(field, JSONObject().put("type", if (field in setOf("revision", "offset")) "integer" else "string"))
        }
        properties.getJSONObject("topic").put("enum", JSONArray(CollaborationEvolutionProtocol.topicIds()))
        val schema = JSONObject().put("type", "object").put("properties", properties)
            .put("required", JSONArray(listOf("mode"))).put("additionalProperties", false)
        val function = JSONObject().put("name", NAME)
            .put("description", "Read this assigned member's saved group workspace or original host tool evidence. Browse first; " +
                "read an exact object_id/revision or evidence_id/sha256, following next_offset/cursor. " +
                "Evidence pages expose source_reference for citing the original observation; galaxyssi_evidence_receipt only records this recall. " +
                "mode=goal_contract takes only cursor and returns the host-pinned original goal, criteria and context fragments; follow next_cursor. " +
                "mode=archive with record_id and offset reads full originals of assigned dependency handoffs; follow next_offset. " +
                "mode=evolution browses scoped learning records; mode=evolution_rules with topic=catalog discovers typed contracts, " +
                "then topic=<id>/offset reads the chosen schema. Omitted topic reads all; retain the same topic when paging. " +
                "mode=capabilities takes query and cursor to find task-related saved methods, tools and failure lessons; follow next_cursor even after an empty page. " +
                "mode=method_history takes exact method object_id/revision/sha256 and cursor; read returned record_id/offset for prior usage conditions, failures and delivery. These are not quality measurements. " +
                "mode=problems takes cursor and lists original tool failures for evidence-based gap diagnosis. " +
                "Returned output is not proof of a claim.")
        val tools = prepared.body.optJSONArray("tools") ?: JSONArray().also { prepared.body.put("tools", it) }
        when (prepared.provider) {
            ModelStreamProvider.OPENAI_COMPATIBLE -> tools.put(JSONObject().put("type", "function")
                .put("function", function.put("parameters", schema)))
            ModelStreamProvider.ANTHROPIC -> tools.put(function.put("input_schema", schema))
            ModelStreamProvider.GEMINI -> tools.put(JSONObject().put("functionDeclarations", JSONArray()
                .put(function.put("parameters", schema.apply { remove("additionalProperties") }))))
        }
    }

    fun execute(context: Context, access: CollaborationWorkspaceAccess, input: JSONObject,
                recordCoverage: Boolean = true): String {
        val result = try {
            require(input.keys().asSequence().all { it in fields }) { "Unexpected recall argument" }
            require(input.optString("mode") in setOf("workspace", "evidence", "goal_contract", "archive", "evolution", "capabilities", "method_history", "evolution_rules", "problems")) { "Invalid recall mode" }
            require(CollaborationGroupStore(context).load(access.groupId)?.members?.any { it.id == access.personId } == true) {
                "Member access was removed"
            }
            listOf("offset", "revision").filter(input::has).forEach { key ->
                require(CollaborationRemoteEvidenceProtocol.integer(input, key)?.let {
                    it in (if (key == "revision") 1L else 0L)..Int.MAX_VALUE.toLong()
                } == true) { "Invalid page number" }
            }
            fields.minus(setOf("offset", "revision")).filter(input::has).forEach { key ->
                require(input.opt(key) is String && input.getString(key).length <= (if (key == "query") 1000 else 512)) { "Invalid reference" }
            }
            require(!input.has("query") || input.optString("mode") == "capabilities") { "Query is only supported for capability search" }
            require(!input.has("topic") || input.optString("mode") == "evolution_rules") { "Topic is only supported for evolution rules" }
            CollaborationScopedRecall.read(context, input.keys().asSequence().associateWith { input.get(it) }, access, recordCoverage)
        } catch (_: IllegalArgumentException) {
            AgentNativeToolExecutionResult.failure("recall_unavailable", "Invalid arguments or revoked member access.")
        }
        return JSONObject(result.output).put("status", if (result.isSuccess) "returned" else "failed").apply {
            result.error?.let { put("error", JSONObject().put("code", it.code).put("message", it.message)) }
        }.toString()
    }
}
