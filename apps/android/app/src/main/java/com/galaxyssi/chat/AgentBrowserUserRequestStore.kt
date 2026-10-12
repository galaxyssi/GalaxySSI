package com.galaxyssi.chat

import android.content.Context
import android.util.AtomicFile
import java.io.File
import org.json.JSONObject

internal data class AgentBrowserUserRequest(
    val key: String,
    val generation: String,
    val scope: String,
    val sessionId: String,
    val conversationId: String,
    val turnId: String,
    val callerId: String,
    val workspaceId: String,
    val browserSessionId: String,
    val pageId: String,
    val handoffId: String = "",
    val state: String = "requested",
    val taskId: String = "",
    val modelLoopId: String = "",
    val runWorkspaceId: String = "",
    val runSessionId: String = "",
    val runWakeAcknowledged: Boolean = false,
    val runPlanningBinding: String = "",
    val hostProcessId: String = "",
    val interruptionCode: String = "",
    val modelObservationCommitted: Boolean = false,
    val actionPlanId: String = "",
    val actionPlanRevision: Int = -1,
    val actionId: String = "",
    val actionPlanBinding: String = "",
    val runtimeInstanceId: String = "",
    val localDispatchId: String = ""
) {
    val settled: Boolean get() = state in setOf("returned", "interrupted")
    val pendingRunWake: Boolean get() = settled && runWorkspaceId.isNotBlank() && !runWakeAcknowledged

    fun afterHostRestart(currentProcessId: String): AgentBrowserUserRequest {
        require(currentProcessId.isNotBlank())
        return if (!settled && hostProcessId.isNotBlank() && hostProcessId != currentProcessId)
            copy(state = "interrupted", interruptionCode = "browser_host_restarted") else this
    }

    fun sameOwner(context: AgentNativeToolInvocationContext): Boolean =
        sessionId == context.sessionId && conversationId == context.conversationId && turnId == context.turnId &&
            callerId == context.callerId && workspaceId == context.attributes["workspace_id"].orEmpty() &&
            taskId == context.attributes["task_id"].orEmpty() && scope == AgentInteractiveBrowserTools.scope(context)

    fun permitsSameGeneration(next: AgentBrowserUserRequest): Boolean =
        copy(handoffId = "", state = "", runWakeAcknowledged = false, interruptionCode = "", modelObservationCommitted = false,
            runtimeInstanceId = "") == next.copy(handoffId = "", state = "", runWakeAcknowledged = false,
            interruptionCode = "", modelObservationCommitted = false, runtimeInstanceId = "") &&
            (runtimeInstanceId == next.runtimeInstanceId || runtimeInstanceId.isBlank() && !settled && !next.settled) &&
            (handoffId.isEmpty() || handoffId == next.handoffId) &&
            (!settled || next.state == state && next.interruptionCode == interruptionCode) &&
            (state != "active" || next.state != "requested") &&
            (!runWakeAcknowledged || next.runWakeAcknowledged) &&
            (!next.runWakeAcknowledged || next.settled) &&
            (!modelObservationCommitted || next.modelObservationCommitted) &&
            (!next.modelObservationCommitted || next.settled) &&
            (if (next.state == "interrupted") AgentBrowserInterruptionPolicy.valid(next.interruptionCode)
             else next.interruptionCode.isBlank())

    fun toJson() = JSONObject().put("key", key).put("generation", generation).put("scope", scope)
        .put("session", sessionId).put("conversation", conversationId).put("turn", turnId).put("caller", callerId)
        .put("workspace", workspaceId).put("browser", browserSessionId).put("page", pageId)
        .put("handoff", handoffId).put("state", state).put("task", taskId).put("model_loop", modelLoopId)
        .put("run_workspace", runWorkspaceId).put("run_session", runSessionId).put("run_wake_ack", runWakeAcknowledged)
        .put("run_planning_binding", runPlanningBinding).put("host_process", hostProcessId)
        .put("interruption_code", interruptionCode)
        .put("model_observation_committed", modelObservationCommitted)
        .put("action_plan", actionPlanId).put("action_plan_revision", actionPlanRevision)
        .put("action", actionId).put("action_plan_binding", actionPlanBinding)
        .put("runtime_instance", runtimeInstanceId)
        .put("local_dispatch", localDispatchId)

    companion object {
        fun fromJson(json: JSONObject) = AgentBrowserUserRequest(json.getString("key"), json.getString("generation"),
            json.getString("scope"), json.getString("session"), json.getString("conversation"), json.getString("turn"),
            json.getString("caller"), json.getString("workspace"), json.getString("browser"), json.getString("page"),
            json.getString("handoff"), json.getString("state"), json.optString("task"), json.optString("model_loop"),
            json.optString("run_workspace"), json.optString("run_session"), json.optBoolean("run_wake_ack"),
            json.optString("run_planning_binding"), json.optString("host_process"), json.optString("interruption_code"),
            json.optBoolean("model_observation_committed"), json.optString("action_plan"),
            json.optInt("action_plan_revision", -1), json.optString("action"), json.optString("action_plan_binding"),
            json.optString("runtime_instance"), json.optString("local_dispatch"))

        fun key(scope: String, browser: String) = AgentNativeJsonCodec.sha256(mapOf("scope" to scope, "browser" to browser))
    }
}

/** One encrypted atomic record per browser; an old notification cannot target a later request. */
internal class AgentBrowserUserRequestStore(context: Context,
    private val directory: File = File(context.filesDir, "browser-user-requests")) {

    fun load(key: String): AgentBrowserUserRequest? = synchronized(lock) {
        val file = file(key)
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return@synchronized null
        val envelope = file.openRead().use { it.readBytes() }
        val bytes = try { AgentStorageCipher.decryptBinary(envelope, aad(key)) } finally { envelope.fill(0) }
        try {
            AgentBrowserUserRequest.fromJson(JSONObject(bytes.toString(Charsets.UTF_8))).also {
                check(it.key == key && key == AgentBrowserUserRequest.key(it.scope, it.browserSessionId))
            }
        } finally { bytes.fill(0) }
    }

    fun current(key: String, generation: String): AgentBrowserUserRequest =
        load(key)?.takeIf { it.generation == generation }
            ?: throw AgentBrowserControlFailure("browser_user_request_stale", mapOf("executed" to false))

    fun pendingWakes(currentProcessId: String = AgentProcessIdentity.instanceId): Sequence<AgentBrowserUserRequest> =
        directory.listFiles().orEmpty().asSequence()
        .map { it.name.removeSuffix(".bak") }.filter { it.matches(Regex("[a-f0-9]{64}\\.enc")) }.distinct()
        .mapNotNull { name -> synchronized(lock) {
            val previous = runCatching { load(name.removeSuffix(".enc")) }.getOrNull() ?: return@synchronized null
            var current = previous.afterHostRestart(currentProcessId)
            if (current != previous) save(current)
            if (current.state == "active" && current.hostProcessId == currentProcessId) {
                AgentRuntimeInstanceEvents.hub.interruption(current.runtimeInstanceId)?.let { event ->
                    interruptRuntime(current, event)?.let { current = it }
                }
            }
            current
        } }.filter { it.pendingRunWake }

    fun acknowledgeRunWake(record: AgentBrowserUserRequest) = synchronized(lock) {
        val latest = load(record.key)
        if (latest == record && latest.pendingRunWake) save(latest.copy(runWakeAcknowledged = true))
    }

    fun interruptObserved(record: AgentBrowserUserRequest, code: String,
        input: AgentNativeJsonObject): AgentBrowserUserRequest? = synchronized(lock) {
        // Compare the complete record, not only its browser key: late results cannot close a new lease.
        if (load(record.key) != record) return@synchronized null
        AgentBrowserInterruptionPolicy.observed(record, code, input)?.also { save(it) }
    }

    fun interruptRuntime(record: AgentBrowserUserRequest, event: AgentRuntimeInstanceEvent): AgentBrowserUserRequest? = synchronized(lock) {
        if (record.state != "active" || record.handoffId.isBlank() || record.runtimeInstanceId.isBlank() ||
            record.runtimeInstanceId != event.instanceId || load(record.key) != record) return@synchronized null
        record.copy(state = "interrupted", interruptionCode = event.browserCode).also { save(it) }
    }

    fun markObservationCommitted(record: AgentBrowserUserRequest) = synchronized(lock) {
        val latest = load(record.key)
        if (latest == record && latest.settled && !latest.modelObservationCommitted)
            save(latest.copy(modelObservationCommitted = true))
    }

    fun acknowledgeObservedRunWake(record: AgentBrowserUserRequest): Boolean = synchronized(lock) {
        val latest = load(record.key) ?: return@synchronized false
        if (latest.copy(modelObservationCommitted = record.modelObservationCommitted) != record ||
            !latest.modelObservationCommitted) return@synchronized false
        acknowledgeRunWake(latest)
        true
    }

    fun save(record: AgentBrowserUserRequest, replaceSettled: Boolean = false) = synchronized(lock) {
        check(record.key == AgentBrowserUserRequest.key(record.scope, record.browserSessionId))
        require(record.state in setOf("requested", "active", "returned", "interrupted"))
        require(!record.modelObservationCommitted || record.settled)
        require(if (record.state == "interrupted") AgentBrowserInterruptionPolicy.valid(record.interruptionCode)
            else record.interruptionCode.isBlank())
        val previous = load(record.key)
        require(previous?.generation == record.generation || !record.modelObservationCommitted) {
            "browser_observation_cannot_cross_generations"
        }
        check(previous == null || previous.generation == record.generation || replaceSettled && previous.settled) {
            "browser_user_request_owned"
        }
        if (previous?.generation == record.generation && !previous.permitsSameGeneration(record)) {
            throw AgentBrowserControlFailure("browser_user_request_binding_changed", mapOf("executed" to false))
        }
        val bytes = record.toJson().toString().toByteArray()
        val envelope = try { AgentStorageCipher.encryptBinary(bytes, aad(record.key)) } finally { bytes.fill(0) }
        val file = file(record.key)
        val output = file.startWrite()
        try { output.write(envelope); file.finishWrite(output) }
        catch (error: Throwable) { file.failWrite(output); throw error }
        finally { envelope.fill(0) }
    }

    private fun file(key: String): AtomicFile {
        require(key.matches(Regex("[a-f0-9]{64}")))
        check(directory.isDirectory || directory.mkdirs())
        return AtomicFile(File(directory, "$key.enc"))
    }

    private fun aad(key: String) = "browser-user-request:v1:$key".toByteArray()

    companion object { internal val lock = Any() }
}
