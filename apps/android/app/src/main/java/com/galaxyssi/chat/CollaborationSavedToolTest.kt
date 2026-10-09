package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A durable execution identity is separate from the short-lived transport nonce. */
internal class CollaborationSavedToolTest(
    private val rows: CollaborationWorkspaceRows,
    access: CollaborationWorkspaceAccess,
    private val process: String,
    private val now: () -> Long = System::currentTimeMillis
) {
    private val prefix = "group:${AgentNativeJsonCodec.sha256(access.groupId)}:saved-tool-test:" +
        AgentNativeJsonCodec.sha256(JSONArray(listOf(access.runId, access.turnId, access.round, access.nodeId, access.personId)).toString()) + ":"

    data class Admission(val record: JSONObject, val launch: Boolean)

    fun key(id: String) = prefix + AgentNativeJsonCodec.sha256(id)

    fun start(input: JSONObject): Admission = synchronized(LOCK) {
        validate(input)
        require(input.getString("mode") == "start")
        val id = input.getString("execution_id")
        val digest = AgentNativeJsonCodec.sha256(input.toNativeObject())
        read(id)?.let {
            require(it.getString("input_sha256") == digest) { "execution_id already names a different test; recover the original outcome first" }
            return@synchronized Admission(it, false)
        }
        val record = JSONObject().put("execution_id", id).put("input_sha256", digest)
            .put("input", JSONObject(input.toString())).put("owner_process", process)
            .put("state", "queued").put("created_at", now()).put("updated_at", now())
        save(id, record)
        Admission(JSONObject(record.toString()), true)
    }

    fun read(id: String): JSONObject? = synchronized(LOCK) {
        validateId(id)
        val record = rows.read(key(id))?.let(::JSONObject) ?: return@synchronized null
        require(record.getString("execution_id") == id) { "Execution identity changed" }
        if (record.getString("state") in ACTIVE && record.getString("owner_process") != process) {
            record.put("state", "interrupted").put("updated_at", now())
                .put("reason", "Process restarted; execution outcome may be incomplete. Recover original evidence before choosing a new execution ID.")
            save(id, record)
        }
        record
    }

    fun running(id: String): Boolean = synchronized(LOCK) {
        val record = read(id) ?: return@synchronized false
        if (record.getString("state") != "queued") return@synchronized false
        record.put("state", "running").put("updated_at", now())
        save(id, record)
        true
    }

    fun cancel(id: String): JSONObject? = synchronized(LOCK) {
        val record = read(id) ?: return@synchronized null
        if (record.getString("state") in ACTIVE) {
            record.put("state", if (record.getString("state") == "queued") "cancelled" else "cancelling")
                .put("updated_at", now())
            save(id, record)
        }
        record
    }

    fun finish(id: String, result: JSONObject): JSONObject = synchronized(LOCK) {
        val record = requireNotNull(read(id))
        require(record.getString("owner_process") == process) { "Execution process changed" }
        if (record.getString("state") !in ACTIVE) return@synchronized record
        record.put("state", "finished").put("result", JSONObject(result.toString())).put("updated_at", now())
        save(id, record)
        record
    }

    fun describe(record: JSONObject?): JSONObject = if (record == null) JSONObject().put("success", true).put("status", "not_recorded") else
        JSONObject().put("success", true).put("status", record.getString("state"))
            .put("execution_id", record.getString("execution_id")).put("input_sha256", record.getString("input_sha256"))
            .put("updated_at", record.getLong("updated_at")).put("result", record.optJSONObject("result") ?: JSONObject.NULL)
            .put("retry_after_ms", if (record.getString("state") in ACTIVE) 2_000 else JSONObject.NULL)
            .put("reason", record.optString("reason")).put("automatically_reexecuted", false)

    private fun save(id: String, record: JSONObject) = rows.commit(mapOf(key(id) to record.toString()))

    companion object {
        const val CONTRACT = "galaxyssi.collaboration-tool-test/1"
        const val REQUEST = "collaboration_tool_test_request"
        const val RESPONSE = "collaboration_tool_test_result"
        private val LOCK = Any()
        private val ACTIVE = setOf("queued", "running", "cancelling")
        private val HASH = Regex("[a-f0-9]{64}")

        fun validateId(id: String) = require(id.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}"))) {
            "execution_id must be a stable 1-128 character ASCII identifier"
        }

        fun validate(input: JSONObject) {
            validateId(input.getString("execution_id"))
            val fields = input.keys().asSequence().toSet()
            when (input.getString("mode")) {
                "start" -> {
                    require(fields == setOf("mode", "execution_id", CollaborationExecutableTool.TEST, "timeout_ms")) { "Start requires an exact saved test plan and timeout_ms; code overrides are not allowed" }
                    val ref = input.getJSONObject(CollaborationExecutableTool.TEST)
                    require(ref.keys().asSequence().toSet() == setOf("object_id", "revision", "sha256") &&
                        HASH.matches(ref.getString("object_id")) && HASH.matches(ref.getString("sha256")) &&
                        CollaborationRemoteEvidenceProtocol.integer(ref, "revision") in 1..Int.MAX_VALUE.toLong()) { "Use an exact object_id, integer revision and sha256" }
                    require(CollaborationRemoteEvidenceProtocol.integer(input, "timeout_ms") in 100..1_800_000L) { "timeout_ms must be an integer in the native runtime range 100..1800000" }
                }
                "status", "cancel" -> require(fields == setOf("mode", "execution_id")) { "Status/cancel accepts only an execution_id" }
                else -> error("Mode must be start, status or cancel")
            }
        }

        fun valid(request: JSONObject, now: Long): Boolean =
            CollaborationRemoteEvidenceProtocol.validScope(request) && request.opt("type") == REQUEST &&
                request.opt("contract") == CONTRACT && (request.opt("request_id") as? String)?.length in 1..128 &&
                CollaborationRemoteEvidenceProtocol.integer(request, "expires_at")?.let { it > now && it - now <= 60_000 } == true &&
                !request.has("delivery") && request.optJSONObject("arguments")?.let {
                    request.opt("phase") == it.opt("mode") && runCatching { validate(it) }.isSuccess
                } == true

        fun nativeInput(input: JSONObject): Map<String, Any?> = mapOf(
            CollaborationToolRuntime.INPUT to mapOf("mode" to "test", CollaborationExecutableTool.TEST to input.getJSONObject(CollaborationExecutableTool.TEST).toNativeObject()),
            "timeout_ms" to input.getLong("timeout_ms"), "network_enabled" to false
        )
    }
}
