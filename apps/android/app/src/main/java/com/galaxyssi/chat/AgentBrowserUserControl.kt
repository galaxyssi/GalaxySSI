package com.galaxyssi.chat

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import java.util.UUID
import org.json.JSONObject

internal class AgentBrowserControlFailure(val code: String, val details: AgentNativeJsonObject = emptyMap()) :
    IllegalStateException(code)

internal class AgentBrowserUserControl(
    context: Context,
    private val execute: (AgentRuntimeExecutionRequest) -> AgentRuntimeExecutionResponse =
        AgentOnDeviceRuntimeManager(context.applicationContext)::execute,
    private val enqueue: (AgentBrowserUserRequest) -> Unit = { record ->
        AgentLongTaskRecoveryScheduler.enqueueBrowserEvent(context.applicationContext, record)?.result?.get()
        Unit
    }
) {
    private val app = context.applicationContext
    private val store = AgentBrowserUserRequestStore(app)
    private val runtimeEvents = AgentBrowserRuntimeEvents.forContext(app)
    private val sessionEvents = AgentBrowserSessionEvents.forContext(app)

    fun request(invocation: AgentNativeToolInvocation): AgentNativeToolExecutionResult {
        if (invocation.context.attributes["task_id"].isNullOrBlank() || invocation.context.turnId.isBlank() ||
            invocation.context.sessionId.isBlank() || invocation.context.conversationId.isBlank() ||
            invocation.context.attributes["workspace_id"].isNullOrBlank()) {
            return AgentNativeToolExecutionResult.failure("browser_task_binding_required",
                "Bind user control to the original task, turn, conversation, session and workspace before requesting it.",
                details = mapOf("executed" to false, "goal_terminal" to false))
        }
        val scope = AgentInteractiveBrowserTools.scope(invocation.context)
        val browser = invocation.input["session_id"] as? String
        val page = invocation.input["page_id"] as? String
        if (browser.isNullOrBlank() || page.isNullOrBlank()) return AgentNativeToolExecutionResult.failure(
            "browser_live_handle_required", "Observe the browser and provide its live session_id and page_id.",
            details = mapOf("executed" to false, "goal_terminal" to false))
        val key = AgentBrowserUserRequest.key(scope, browser)
        return try {
            AgentWorkspaceScope.withLock("browser-handoff:$key") {
                invocation.checkpoint()
                val previous = store.load(key)
                if (previous != null && !previous.settled && (!previous.sameOwner(invocation.context) ||
                    previous.modelLoopId != invocation.context.attributes["model_loop_id"].orEmpty() ||
                    previous.actionPlanBinding != invocation.context.attributes["action_plan_binding"].orEmpty())) {
                    throw AgentBrowserControlFailure("browser_user_request_owned", mapOf("executed" to false))
                }
                var record = previous?.takeIf { !it.settled } ?: AgentBrowserUserRequest(key,
                    UUID.randomUUID().toString(), scope, invocation.context.sessionId, invocation.context.conversationId,
                    invocation.context.turnId, invocation.context.callerId,
                    invocation.context.attributes["workspace_id"].orEmpty(), browser, page,
                    taskId = invocation.context.attributes["task_id"].orEmpty(),
                    modelLoopId = invocation.context.attributes["model_loop_id"].orEmpty(),
                    hostProcessId = AgentProcessIdentity.instanceId,
                    actionPlanId = invocation.context.attributes["action_plan_id"].orEmpty(),
                    actionPlanRevision = invocation.context.attributes["action_plan_revision"]?.toIntOrNull() ?: -1,
                    actionId = invocation.context.attributes["action_id"].orEmpty(),
                    actionPlanBinding = invocation.context.attributes["action_plan_binding"].orEmpty(),
                    collaborationSourceMessageId = invocation.context.collaborationSourceMessageId)
                    .let { candidate -> AgentLocalBrowserDispatchStore(app).bind(candidate) }
                    .let { candidate -> if (candidate.callerId == LocalModelLoopContinuation.CALLER) candidate else AgentBrowserRunRecoveryPolicy.bind(candidate,
                        AgentTaskRuntime.supervisor(app).activeWorkspaces()) { workspace ->
                        SharedPreferencesAgentSessionStore(app, "task:$workspace").load()
                    } }
                    .also {
                        if ((it.actionPlanBinding.isNotBlank() || it.callerId == LocalModelLoopContinuation.CALLER) &&
                            it.runWorkspaceId.isBlank() && it.managedOwnerRunId.isBlank())
                            throw AgentBrowserControlFailure("browser_run_binding_required", mapOf("executed" to false))
                        store.save(it, replaceSettled = true)
                    }
                var state = try { host(record, mapOf("operation" to "human_control_state") +
                    if (record.handoffId.isBlank()) emptyMap() else mapOf("handoff_id" to record.handoffId), invocation.cancellationToken) {
                        instance -> if (instance.isNotBlank()) record = record.copy(runtimeInstanceId = instance)
                    } }
                    catch (error: AgentBrowserControlFailure) {
                        if (error.code != "browser_user_handoff_invalid" || record.handoffId.isNotEmpty()) throw error
                        null
                    }
                if (state == null || state.optString("control_owner") == "agent" && record.handoffId.isEmpty()) {
                    state = host(record, mapOf("operation" to "human_control_begin", "page_id" to record.pageId), invocation.cancellationToken) {
                        instance -> if (instance.isNotBlank()) record = record.copy(runtimeInstanceId = instance)
                    }
                }
                if (record.handoffId.isNotEmpty() && record.handoffId != state.getString("handoff_id")) {
                    throw AgentBrowserControlFailure("browser_user_request_stale", mapOf("executed" to false))
                }
                record = record.copy(handoffId = state.getString("handoff_id"),
                    state = if (state.optString("control_owner") == "agent") "returned" else "active")
                store.save(record)
                if (record.state == "active") {
                    runtimeEvents.watch(record)
                    sessionEvents.watch(record)
                    if (store.load(record.key) == record) present(record)
                }
                else scheduleRunWake(record)
                AgentNativeToolExecutionResult.success(state.toNativeObject() +
                    mapOf("durable_resume_available" to (record.runWorkspaceId.isNotBlank() || record.managedOwnerRunId.isNotBlank()),
                        "host_wait_key" to record.key, "host_wait_generation" to record.generation),
                    "Browser user-control state observed")
            }
        } catch (error: AgentBrowserControlFailure) {
            AgentNativeToolExecutionResult.failure(error.code, "Inspect the current browser handoff before retrying.",
                details = error.details + mapOf("goal_terminal" to false))
        }
    }

    fun current(key: String, generation: String) = store.current(key, generation)

    fun snapshot(record: AgentBrowserUserRequest, width: Int, height: Int): JSONObject =
        operate(record, mapOf("operation" to "snapshot", "page_id" to record.pageId, "width" to width, "height" to height))

    fun operate(record: AgentBrowserUserRequest, action: AgentNativeJsonObject): JSONObject {
        requireCurrent(record)
        return host(record, mapOf("operation" to "human_control_execute", "handoff_id" to record.handoffId, "action" to action))
    }

    fun finish(record: AgentBrowserUserRequest): JSONObject {
        requireCurrent(record)
        val state = host(record, mapOf("operation" to "human_control_finish", "handoff_id" to record.handoffId))
        check(state.optString("control_owner") == "agent")
        val returned = record.copy(state = "returned")
        store.save(returned)
        runtimeEvents.unwatch(record)
        sessionEvents.unwatch(record)
        scheduleRunWake(returned)
        app.getSystemService(NotificationManager::class.java).cancel(record.key, NOTIFICATION_ID)
        return state
    }

    /** Host cleanup only: never convert a stopped task into a returned-control success event. */
    internal fun releaseStopped(record: AgentBrowserUserRequest) {
        val current = store.current(record.key, record.generation)
        val dispatch = AgentLocalBrowserDispatchStore(app).load(current.localDispatchId)
            ?: throw AgentBrowserControlFailure("browser_run_binding_required")
        require(AgentLocalBrowserDispatchPolicy.matches(dispatch, current) &&
            dispatch.managedOwner != null && current.settled &&
            (current.interruptionCode == "browser_owner_stopped" ||
                AgentTeamDurableControl(app).get(dispatch.managedOwner.supervisorRunId) == AgentTeamUserControl.STOP))
        if (current.state == "returned" || current.handoffId.isBlank()) return
        try {
            val state = host(current, mapOf("operation" to "human_control_finish", "handoff_id" to current.handoffId))
            if (state.optString("control_owner") != "agent") throw AgentBrowserControlFailure(
                "browser_control_release_unconfirmed", mapOf("outcome_unknown" to true))
        }
        catch (error: AgentBrowserControlFailure) {
            if (error.code !in setOf("browser_user_handoff_invalid", "session_lost", "session_closed", "session_not_found", "browser_closed",
                    "browser_runtime_replaced")) throw error
        }
    }

    private fun scheduleRunWake(record: AgentBrowserUserRequest) {
        if (record.pendingRunWake) runCatching {
            enqueue(record)
        }.onFailure { android.util.Log.w("GalaxySSIBrowserRecovery", "Browser return enqueue deferred", it) }
        // A failed enqueue leaves the encrypted pending return for startup reconciliation.
    }

    internal fun reconcileReturned(record: AgentBrowserUserRequest) {
        if (store.current(record.key, record.generation) == record) scheduleRunWake(record)
    }

    private fun requireCurrent(record: AgentBrowserUserRequest) {
        val current = store.current(record.key, record.generation)
        if (current.handoffId != record.handoffId || current.state != "active" || current != record) {
            throw AgentBrowserControlFailure("browser_user_request_stale", mapOf("executed" to false))
        }
    }

    private fun host(record: AgentBrowserUserRequest, input: AgentNativeJsonObject,
        cancellation: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
        observedRuntime: (String) -> Unit = {}): JSONObject {
        val observedInput = if (input["operation"] in setOf("human_control_state", "human_control_begin"))
            input + mapOf("event_sink" to AgentBrowserSessionEventCodec.prepare(app, record)) else input
        val request = hostRequest(record, observedInput, AgentBrowserHostAuthority.token(app, record.scope),
            AgentInteractiveBrowserTools.stageHelpers(app), cancellation)
        val response = execute(request)
        if (response.exitCode == 127) throw AgentBrowserControlFailure("browser_runtime_missing", mapOf("executed" to false))
        val envelope = runCatching { JSONObject(response.stdout.trim()) }.getOrNull()
            ?: throw AgentBrowserControlFailure("browser_result_unobserved", mapOf("outcome_unknown" to true))
        if (!envelope.optBoolean("ok")) {
            val error = envelope.optJSONObject("error")
            val code = error?.optString("code").orEmpty().ifBlank { "browser_operation_failed" }
            store.interruptObserved(record, code, input)?.let { interrupted ->
                runtimeEvents.unwatch(record)
                sessionEvents.unwatch(record)
                scheduleRunWake(interrupted)
                app.getSystemService(NotificationManager::class.java).cancel(record.key, NOTIFICATION_ID)
            }
            throw AgentBrowserControlFailure(code,
                error?.optJSONObject("details").toNativeObject())
        }
        if (record.runtimeInstanceId.isNotBlank() && response.runtimeInstanceId.isNotBlank() &&
            record.runtimeInstanceId != response.runtimeInstanceId) {
            store.interruptRuntime(record, AgentRuntimeInstanceEvent(record.runtimeInstanceId,
                AgentRuntimeInstanceEvent.Kind.REPLACED))?.let { interrupted ->
                runtimeEvents.unwatch(record)
                sessionEvents.unwatch(record)
                scheduleRunWake(interrupted)
            }
            throw AgentBrowserControlFailure("browser_runtime_replaced", mapOf("outcome_unknown" to true))
        }
        observedRuntime(response.runtimeInstanceId)
        return envelope.getJSONObject("result")
    }

    private fun present(record: AgentBrowserUserRequest) {
        val intent = Intent(app, AgentBrowserUserControlActivity::class.java)
            .setData(Uri.parse("galaxyssi-internal://browser-control/${record.key}/${record.generation}"))
            .putExtra(EXTRA_KEY, record.key).putExtra(EXTRA_GENERATION, record.generation)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val manager = app.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, app.getString(R.string.browser_user_control_title),
            NotificationManager.IMPORTANCE_DEFAULT))
        val pending = PendingIntent.getActivity(app, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(app, CHANNEL).setSmallIcon(R.drawable.ic_process_network)
            .setContentTitle(app.getString(R.string.browser_user_control_title))
            .setContentText(app.getString(R.string.browser_user_control_waiting)).setContentIntent(pending)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setAutoCancel(false).build()
        runCatching { manager.notify(record.key, NOTIFICATION_ID, notification) }
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        if (process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE) {
            runCatching { app.startActivity(intent) }
        }
    }

    companion object {
        const val EXTRA_KEY = "browser_request_key"
        const val EXTRA_GENERATION = "browser_request_generation"
        private const val CHANNEL = "browser_user_control"
        private const val NOTIFICATION_ID = 1

        internal fun hostRequest(record: AgentBrowserUserRequest, input: AgentNativeJsonObject, capability: String,
            helpers: List<AgentRuntimeHostInput> = emptyList(),
            cancellation: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE): AgentRuntimeExecutionRequest {
            require(record.scope.matches(Regex("[a-f0-9]{64}")))
            return AgentRuntimeExecutionRequest(language = AgentRuntimeLanguage.SHELL,
                source = "command -v galaxyssi-browser >/dev/null 2>&1 || exit 127\n" +
                    "exec galaxyssi-browser .galaxyssi-inputs/browser/browser-session-cli.cjs host ${shellSingleQuote(record.scope)}",
                arguments = emptyList(), timeoutMillis = 60_000, networkEnabled = true, artifactPaths = emptyList(),
                // A model waiting in its task workspace must not hold the user's control channel lock.
                workspaceId = AgentWorkspaceScope.id("browser-control:${record.scope}"), requestId = UUID.randomUUID().toString(),
                secretEnvironment = AgentInteractiveBrowserTools.secretEnvironment(input + mapOf("session_id" to record.browserSessionId), capability),
                hostInputFiles = helpers, cancellationToken = cancellation,
                resourceLimits = AgentRuntimeResourceLimits(wallClockMillis = 60_000, cpuMillis = 60_000, maxOutputBytes = 4L * 1024 * 1024),
                workspaceMutationExpected = false, discoverBuildArtifacts = false)
        }
    }
}
