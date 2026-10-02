package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import org.json.JSONArray
import org.json.JSONObject

/** Read-only group capability, advertised only for an already bound managed cloud assignment. */
internal object CollaborationCloudRecall {
    const val NAME = "collaboration_recall"
    private val fields = setOf("mode", "cursor", "object_id", "revision", "evidence_id", "sha256", "offset")

    fun install(prepared: PreparedCloudConversationStream) {
        val properties = JSONObject().put("mode", JSONObject().put("type", "string")
            .put("enum", JSONArray(listOf("evidence", "workspace", "goal_contract"))))
        fields.filterNot { it == "mode" }.forEach { field ->
            properties.put(field, JSONObject().put("type", if (field in setOf("revision", "offset")) "integer" else "string"))
        }
        val schema = JSONObject().put("type", "object").put("properties", properties)
            .put("required", JSONArray(listOf("mode"))).put("additionalProperties", false)
        val function = JSONObject().put("name", NAME)
            .put("description", "Read this assigned member's saved group workspace or original host tool evidence. Browse first; " +
                "read an exact object_id/revision or evidence_id/sha256, following next_offset/cursor. " +
                "mode=goal_contract takes only cursor and returns the host-pinned original goal, criteria and context fragments; follow next_cursor. " +
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

    fun execute(context: Context, access: CollaborationWorkspaceAccess, input: JSONObject): String {
        val result = try {
            require(input.keys().asSequence().all { it in fields }) { "Unexpected recall argument" }
            require(input.optString("mode") in setOf("workspace", "evidence", "goal_contract")) { "Invalid recall mode" }
            require(CollaborationGroupStore(context).load(access.groupId)?.members?.any { it.id == access.personId } == true) {
                "Member access was removed"
            }
            listOf("offset", "revision").filter(input::has).forEach { key ->
                require(CollaborationRemoteEvidenceProtocol.integer(input, key)?.let {
                    it in (if (key == "revision") 1L else 0L)..Int.MAX_VALUE.toLong()
                } == true) { "Invalid page number" }
            }
            fields.minus(setOf("offset", "revision")).filter(input::has).forEach { key ->
                require(input.opt(key) is String && input.getString(key).length <= 512) { "Invalid reference" }
            }
            CollaborationScopedRecall.read(context, input.keys().asSequence().associateWith { input.get(it) }, access)
        } catch (_: IllegalArgumentException) {
            AgentNativeToolExecutionResult.failure("recall_unavailable", "Invalid arguments or revoked member access.")
        }
        return JSONObject(result.output).put("status", if (result.isSuccess) "returned" else "failed").apply {
            result.error?.let { put("error", JSONObject().put("code", it.code).put("message", it.message)) }
        }.toString()
    }
}
