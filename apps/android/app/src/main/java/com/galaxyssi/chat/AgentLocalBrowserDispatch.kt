package com.galaxyssi.chat

import android.content.Context
import android.util.AtomicFile
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

internal data class AgentLocalBrowserDispatch(
    val identity: AgentLocalDispatchIdentity,
    val runWorkspaceId: String,
    val runSessionId: String,
    val targetLabel: String,
    val startedAtMillis: Long,
    val observedContextIds: Set<String> = emptySet(),
    val planBinding: String = "",
    val state: String = "pending",
    val managedOwner: AgentManagedBrowserOwner? = null
) {
    val scope get() = LocalModelLoopContinuation.scope(identity)
    val key get() = scope.loop
    val terminal get() = state in setOf("delivered", "cancelled")
}

internal object AgentLocalBrowserDispatchPolicy {
    const val CHECKPOINT = "local-browser-dispatch"

    fun planBinding(session: AgentSessionSnapshot, actionId: String): String? {
        val plan = session.currentPlan ?: return null
        val action = plan.actions.singleOrNull { it.id == actionId } ?: return null
        val node = AgentPlanNodeKey.from(session.sessionId, plan, action) ?: return null
        return AgentNativeJsonCodec.sha256(node.identity())
    }

    fun isWaiting(workspace: AgentWorkspace): Boolean {
        val local = workspace.eventJournal.asReversed().firstOrNull {
            it.kind in setOf(AgentTaskEventKinds.PROGRESS, AgentTaskEventKinds.HEARTBEAT) &&
                runCatching { JSONObject(it.payloadJson).optString("stage").startsWith("local_model.") }.getOrDefault(false)
        } ?: return false
        return JSONObject(local.payloadJson).optString("stage") == "local_model.loop_waiting"
    }

    fun owns(dispatch: AgentLocalBrowserDispatch, workspace: AgentWorkspace?, session: AgentSessionSnapshot?,
        requirePendingResponse: Boolean): Boolean {
        val id = dispatch.identity
        if (dispatch.terminal || workspace == null || session == null ||
            workspace.workspaceId != dispatch.runWorkspaceId || workspace.sessionId != dispatch.runSessionId ||
            workspace.conversationId != id.conversationId || workspace.taskId != id.turnId ||
            workspace.status.isTerminal || workspace.cancellationRequested || session.sessionId != id.taskId ||
            session.phase in setOf(AgentPhase.COMPLETED, AgentPhase.FAILED, AgentPhase.CANCELLED) ||
            session.lastActionResult?.actionId == "agent-paused" || session.executionLoopSnapshot?.phase?.isTerminal == true ||
            dispatch.planBinding.isBlank() || planBinding(session, id.actionId) != dispatch.planBinding)
            return false
        val result = session.lastActionResult
        val pending = session.phase == AgentPhase.WAITING_RESPONSE && result?.actionId == id.actionId &&
            result.metadata["source_message_id"]?.toLongOrNull() == id.sourceMessageId &&
            result.metadata["contact_id"] == id.contactId && result.metadata["awaiting_response"] == "true"
        if (requirePendingResponse) return pending
        return pending || session.phase == AgentPhase.EXECUTING && session.currentPlan?.actions?.any {
            it.id == id.actionId && it.status in setOf(AgentActionStatus.PROPOSED, AgentActionStatus.RUNNING,
                AgentActionStatus.WAITING_RESPONSE)
        } == true
    }

    fun matches(dispatch: AgentLocalBrowserDispatch, record: AgentBrowserUserRequest): Boolean {
        val scope = dispatch.scope
        return record.localDispatchId == dispatch.key && record.modelLoopId == scope.loop &&
            record.sessionId == scope.session && record.conversationId == scope.conversation &&
            record.turnId == scope.turn && record.taskId == scope.task && record.workspaceId == scope.workspace &&
            record.callerId == scope.caller && record.runWorkspaceId == dispatch.runWorkspaceId &&
            record.runSessionId == dispatch.runSessionId && record.actionPlanBinding.isBlank() &&
            record.managedOwnerRunId == dispatch.managedOwner?.ownerRunId.orEmpty() &&
            record.collaborationSourceMessageId == dispatch.managedOwner?.let { dispatch.identity.sourceMessageId }
    }
}

/** Small routing envelope only. Model prompts/results remain in the chunked encrypted loop journal. */
internal class AgentLocalBrowserDispatchStore(context: Context,
    private val directory: File = File(context.noBackupFilesDir, "local-browser-dispatches")) {
    private val app = context.applicationContext

    fun registerManagedIfOwned(identity: AgentLocalDispatchIdentity, label: String, startedAt: Long,
        observedIds: Set<String>, journal: EncryptedAgentModelLoopJournal = EncryptedAgentModelLoopJournal(app)): AgentLocalBrowserDispatch? {
        load(LocalModelLoopContinuation.scope(identity).loop)?.let {
            return it.takeIf { saved -> saved.identity == identity && saved.managedOwner != null && owned(saved) }
        }
        val scope = LocalModelLoopContinuation.scope(identity)
        // Never broaden the immutable catalog of an already-started member loop, even before its first inference.
        if (journal.hasRecords(scope) || journal.hasOperation(scope, LocalModelLoopContinuationStore.OPERATION)) return null
        val owner = AgentManagedBrowserOwners(app).capture(identity) ?: return null
        if (owner.groupId.isNotBlank()) {
            val access = CollaborationEvidenceLedger(app).binding(identity.sourceMessageId, identity.conversationId, identity.turnId)
                ?: return null
            if (CollaborationResearchWorkspace(app).publicationCheckpoint(access)?.optJSONObject("receipt")?.optString("status") == "rejected")
                return null
        }
        return register(AgentLocalBrowserDispatch(identity, "", "", label, startedAt, observedIds, managedOwner = owner))
    }

    fun managedState(dispatch: AgentLocalBrowserDispatch): AgentManagedBrowserState? = dispatch.managedOwner?.let {
        AgentManagedBrowserOwners(app).state(it, dispatch.identity)
    }

    fun registerIfOwned(identity: AgentLocalDispatchIdentity, label: String, startedAt: Long,
        observedIds: Set<String>): AgentLocalBrowserDispatch? {
        val workspace = EncryptedAgentWorkspaceStore(app).find(identity.turnId) ?: return null
        val saved = SharedPreferencesAgentSessionStore(app, "task:${workspace.workspaceId}").load()
        val binding = saved?.let { AgentLocalBrowserDispatchPolicy.planBinding(it, identity.actionId) } ?: return null
        val dispatch = AgentLocalBrowserDispatch(identity, workspace.workspaceId, workspace.sessionId, label,
            startedAt, observedIds, planBinding = binding)
        if (!AgentLocalBrowserDispatchPolicy.owns(dispatch, workspace, saved, false)) return null
        return register(dispatch)
    }

    fun owned(dispatch: AgentLocalBrowserDispatch, pending: Boolean = false): Boolean {
        val latest = load(dispatch.key) ?: return false
        if (latest.terminal || latest.copy(state = dispatch.state) != dispatch) return false
        if (latest.managedOwner != null) return managedState(latest) in
            setOf(AgentManagedBrowserState.READY, AgentManagedBrowserState.PAUSED)
        val workspace = EncryptedAgentWorkspaceStore(app).find(dispatch.runWorkspaceId)
        return AgentTranscriptStore(app).conversation(dispatch.identity.conversationId) != null &&
            AgentLocalBrowserDispatchPolicy.owns(latest, workspace,
                SharedPreferencesAgentSessionStore(app, "task:${dispatch.runWorkspaceId}").load(), pending)
    }

    fun checkpoint(dispatch: AgentLocalBrowserDispatch) {
        if (dispatch.managedOwner != null) return
        AgentTaskRuntime.supervisor(app).checkpoint(dispatch.runWorkspaceId, AgentLocalBrowserDispatchPolicy.CHECKPOINT,
            stateJson = JSONObject().put("dispatch", dispatch.key).put("action", dispatch.identity.actionId).toString())
    }

    /** Only a previous-process in-flight dispatch with its saved anchor may regain its pending reply binding. */
    fun restorePendingBinding(dispatch: AgentLocalBrowserDispatch): Boolean {
        if (dispatch.managedOwner != null) return owned(dispatch, pending = true)
        val workspace = EncryptedAgentWorkspaceStore(app).find(dispatch.runWorkspaceId) ?: return false
        val sessions = SharedPreferencesAgentSessionStore(app, "task:${dispatch.runWorkspaceId}")
        val session = sessions.load() ?: return false
        if (AgentLocalBrowserDispatchPolicy.owns(dispatch, workspace, session, true)) return true
        if (session.processInstanceId == AgentProcessIdentity.instanceId ||
            !AgentLocalBrowserDispatchPolicy.owns(dispatch, workspace, session, false)) return false
        val anchor = workspace.checkpoints.firstOrNull { it.id == AgentLocalBrowserDispatchPolicy.CHECKPOINT }
            ?.let { runCatching { JSONObject(it.stateJson) }.getOrNull() } ?: return false
        if (anchor.optString("dispatch") != dispatch.key || anchor.optString("action") != dispatch.identity.actionId) return false
        val plan = checkNotNull(session.currentPlan)
        val action = plan.actions.singleOrNull { it.id == dispatch.identity.actionId } ?: return false
        val id = dispatch.identity
        val result = AgentActionResult(id.actionId, true, "Waiting for ${dispatch.targetLabel} response", mapOf(
            "awaiting_response" to "true", "source_message_id" to id.sourceMessageId.toString(),
            "contact_id" to id.contactId, "target" to dispatch.targetLabel, "resource_id" to id.contactId,
            "resource_location" to "phone", "failure_domain" to "phone:local-model",
            "resource_started_at" to dispatch.startedAtMillis.toString(),
            "remaining_fallback_ids" to action.parameters["routing_fallback_ids"].orEmpty(),
            "deferred_retry_ids" to action.parameters["routing_deferred_retry_ids"].orEmpty(),
            "retried_resource_ids" to action.parameters["routing_retried_resource_ids"].orEmpty(),
            "manual_target_locked" to action.parameters["manual_target_locked"].orEmpty()))
        if (!sessions.restoreIfUnchanged(session, session.copy(phase = AgentPhase.WAITING_RESPONSE, lastActionResult = result,
            currentPlan = plan.markAction(id.actionId, AgentActionStatus.WAITING_RESPONSE, result),
            processInstanceId = AgentProcessIdentity.instanceId, updatedAtMillis = System.currentTimeMillis()))) return false
        return owned(dispatch, pending = true)
    }

    fun bind(record: AgentBrowserUserRequest): AgentBrowserUserRequest {
        if (!record.modelLoopId.startsWith("local-dispatch-")) return record
        val dispatch = load(record.modelLoopId) ?: return record
        if (!owned(dispatch)) return record
        val bound = record.copy(localDispatchId = dispatch.key, runWorkspaceId = dispatch.runWorkspaceId,
            runSessionId = dispatch.runSessionId, managedOwnerRunId = dispatch.managedOwner?.ownerRunId.orEmpty())
        return if (AgentLocalBrowserDispatchPolicy.matches(dispatch, bound)) bound else record
    }

    fun load(key: String): AgentLocalBrowserDispatch? = synchronized(lock) {
        val file = file(key)
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return@synchronized null
        val encrypted = file.openRead().use { it.readBytes() }
        val bytes = try { AgentStorageCipher.decryptBinary(encrypted, aad(key)) } finally { encrypted.fill(0) }
        try {
            val json = JSONObject(bytes.toString(Charsets.UTF_8))
            check(json.getInt("version") == 1)
            val id = AgentLocalDispatchIdentity(json.getLong("source"), json.getString("contact"),
                json.getString("conversation"), json.getString("turn"), json.getString("task"), json.getString("action"))
            AgentLocalBrowserDispatch(id, json.getString("run_workspace"), json.getString("run_session"),
                json.getString("target"), json.getLong("started"), json.getJSONArray("observed").let { array ->
                    (0 until array.length()).mapTo(linkedSetOf()) { array.getString(it) }
                }, planBinding = json.getString("plan_binding"), state = json.getString("state"),
                managedOwner = if (json.has("managed_owner")) AgentManagedBrowserOwner.fromJson(json.getJSONObject("managed_owner")) else null).also {
                check(it.key == key && it.state in STATES && if (it.managedOwner == null)
                    it.runWorkspaceId.isNotBlank() && it.runSessionId.isNotBlank() else
                    it.runWorkspaceId.isBlank() && it.runSessionId.isBlank() && it.planBinding.isBlank())
            }
        } finally { bytes.fill(0) }
    }

    fun register(dispatch: AgentLocalBrowserDispatch): AgentLocalBrowserDispatch = synchronized(lock) {
        val previous = load(dispatch.key)
        if (previous != null) {
            check(previous.copy(state = dispatch.state) == dispatch) { "local_browser_dispatch_binding_changed" }
            previous
        } else dispatch.also(::save)
    }

    fun transition(dispatch: AgentLocalBrowserDispatch, state: String): AgentLocalBrowserDispatch = synchronized(lock) {
        require(state in STATES)
        val latest = checkNotNull(load(dispatch.key)) { "local_browser_dispatch_missing" }
        check(latest.copy(state = dispatch.state) == dispatch) { "local_browser_dispatch_binding_changed" }
        if (latest.terminal) latest else latest.copy(state = state).also(::save)
    }

    private fun save(dispatch: AgentLocalBrowserDispatch) {
        val id = dispatch.identity
        val json = JSONObject().put("version", 1).put("source", id.sourceMessageId).put("contact", id.contactId)
            .put("conversation", id.conversationId).put("turn", id.turnId).put("task", id.taskId).put("action", id.actionId)
            .put("run_workspace", dispatch.runWorkspaceId).put("run_session", dispatch.runSessionId)
            .put("target", dispatch.targetLabel).put("started", dispatch.startedAtMillis)
            .put("plan_binding", dispatch.planBinding)
            .put("observed", JSONArray(dispatch.observedContextIds.toList())).put("state", dispatch.state)
        dispatch.managedOwner?.let { json.put("managed_owner", it.toJson()) }
        val bytes = json.toString().toByteArray()
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, aad(dispatch.key)) } finally { bytes.fill(0) }
        val file = file(dispatch.key)
        val output = file.startWrite()
        try { output.write(encrypted); file.finishWrite(output) }
        catch (error: Throwable) { file.failWrite(output); throw error }
        finally { encrypted.fill(0) }
    }

    private fun file(key: String): AtomicFile {
        require(key.matches(Regex("local-dispatch-[a-f0-9]{64}")))
        check(directory.isDirectory || directory.mkdirs())
        return AtomicFile(File(directory, "$key.enc"))
    }
    private fun aad(key: String) = "local-browser-dispatch:v1:$key".toByteArray()
    private companion object { val lock = Any(); val STATES = setOf("pending", "waiting", "delivered", "cancelled") }
}
