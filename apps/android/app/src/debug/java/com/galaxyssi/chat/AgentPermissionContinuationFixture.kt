package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Synthetic permission state; only a dedicated cache file is written, never a real device permission. */
internal object AgentPermissionContinuationFixture {
    fun run(context: Context): JSONObject {
        val id = "permission-continuation-${UUID.randomUUID()}"
        val started = System.currentTimeMillis()
        val sessions = SharedPreferencesAgentSessionStore(context, id)
        val database = "$id.db"
        val ledger = AgentRunEventStore(context, database)
        val file = File(context.cacheDir, "$id.txt")
        val checks = mutableListOf<String>()
        var granted = false
        var calls = 0
        val permission = "android.permission.READ_CALENDAR"
        val guarded = object : ContextWrapper(context) {
            override fun getApplicationContext() = this
            override fun checkSelfPermission(value: String) = if (value == permission) {
                if (granted) PackageManager.PERMISSION_GRANTED else PackageManager.PERMISSION_DENIED
            } else super.checkSelfPermission(value)
        }
        val settings = object : AgentSafetySettingsStore {
            private var value = AgentSafetySettings(memoryCapture = false, screenObservationAllowed = false)
            override fun load() = value
            override fun save(settings: AgentSafetySettings) { value = settings }
        }
        val rows = mutableMapOf<String, AgentTaskRecord>()
        val tasks = object : AgentTaskStore {
            override fun upsert(record: AgentTaskRecord) { rows[record.taskId] = record }
            override fun recent(limit: Int) = rows.values.take(limit)
            override fun forSession(sessionId: String, limit: Int) = rows.values.filter { it.sessionId == sessionId }.take(limit)
            override fun find(taskId: String) = rows[taskId]
            override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
            override fun delete(taskIds: Set<String>) { taskIds.forEach(rows::remove) }
            override fun clear() { rows.clear() }
        }
        val tool = "fixture.permission.file"
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(AgentNativeToolDescriptor(
            tool, "1.0.0", "Permission fixture", "Writes one dedicated test file", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            requiredPermissions = listOf(AgentNativePermissionRequirement(permission, "Synthetic fixture"))),
            AgentNativeToolExecutor {
                calls++
                file.writeText("alpha=7\nbeta=5\n")
                AgentNativeToolExecutionResult.success(mapOf("state_verified" to (file.readText() == "alpha=7\nbeta=5\n")))
            }))
        val screen = ScreenContext("Permission fixture", pageTitle = "Dedicated test file only")
        fun runtime() = MobileNativeAgent(guarded, sessionStore = sessions, taskStore = tasks,
            safetySettingsStore = settings, memoryStore = InMemoryAgentMemoryStore(), nativeToolRegistryProvider = { registry },
            connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }).also { runtime ->
                runtime.bindExecutionLoopEventSink(AgentExecutionLoopEventSink { event ->
                    val projection = AgentExecutionLoopTimelinePolicy.project(event,
                        permissionWait = AgentRuntimePermissionContinuation.waiting(runtime.snapshot()) != null)
                    ledger.appendNext(AgentRunControlEvent(conversationId = id, messageId = id, taskId = id,
                        runId = id, agentId = "fixture", deviceId = "fixture", type = projection.controlEventType,
                        sequence = 0L, payload = projection.payload))
                })
            }
        fun fresh(): MobileNativeAgent {
            sessions.clear()
            ledger.removeRuns(setOf(id))
            ledger.appendNext(AgentRunControlEvent(conversationId = id, messageId = id, taskId = id,
                runId = id, agentId = "fixture", deviceId = "fixture", type = AgentRunControlEventType.RUN_CREATED,
                sequence = 0L))
            granted = false
            return runtime().also {
                it.sessionId = id
                it.currentGoal = "Write a dedicated synthetic permission test file"
                it.currentScreen = screen
                val action = AgentAction("action-${UUID.randomUUID()}", AgentActionKind.CALL_NATIVE_TOOL,
                    tool, AgentRisk.LOW, AgentActionStatus.PROPOSED, it.currentGoal,
                    mapOf("tool_id" to tool, "input_json" to "{}", INTERNAL_CONVERSATION_ID to id, INTERNAL_TURN_ID to id))
                it.currentPlan = AgentPlan(it.currentGoal, screen, emptyList(), listOf(action))
                it.activeConversationContext = AgentConversationContext(id, "", emptyList(), true)
                it.activeConversationTurnId = id
                it.phase = AgentPhase.PLANNING
                it.executionLoop.start(id, AgentExecutionLoopBudget())
                check(it.waitForNativePermissions(action))
                it.reconcileExecutionLoop(it.snapshot())
            }
        }
        fun verify(name: String, value: Boolean) { check(value) { name }; checks += name }
        try {
            val first = fresh()
            val pending = requireNotNull(AgentRuntimePermissionContinuation.parse(first.lastActionResult))
            val originalPlan = first.currentPlan!!
            verify("blocked before dispatch", first.phase == AgentPhase.BLOCKED && calls == 0 && !file.exists())
            verify("ledger records permission wait instead of failure", ledger.snapshot(id)?.state == AgentRunControlState.WAITING_FOR_USER)
            verify("permission wait offers pause and cancel", AgentExecutionLoopTimelinePolicy.actionsForState(first.snapshot()) ==
                listOf(AgentExecutionLoopTimelineAction.PAUSE, AgentExecutionLoopTimelineAction.CANCEL))
            first.continueAfterAndroidPermission(pending)
            verify("denied callback does not execute", calls == 0 && first.phase == AgentPhase.BLOCKED)
            first.pauseCurrentTask()
            verify("pause applies to runtime and loop", first.phase == AgentPhase.PAUSED &&
                first.executionLoop.snapshot?.phase == AgentExecutionLoopPhase.PAUSED)
            verify("paused event persists without terminal ledger rejection", ledger.snapshot(id)?.state == AgentRunControlState.PAUSED)
            val restored = runtime()
            verify("pause survives reload with exact original action", restored.phase == AgentPhase.PAUSED &&
                restored.currentPlan?.planId == originalPlan.planId && restored.currentPlan?.actions?.single()?.id == pending.actionId)
            granted = true
            restored.continueAfterAndroidPermission(pending)
            verify("late grant cannot resume paused work", calls == 0 && restored.phase == AgentPhase.PAUSED && !file.exists())
            restored.resumeCurrentTask()
            verify("explicit resume executes original file action once", calls == 1 && file.readText() == "alpha=7\nbeta=5\n" &&
                restored.currentPlan?.actions?.single()?.id == pending.actionId && restored.phase == AgentPhase.COMPLETED)
            restored.continueAfterAndroidPermission(pending)
            verify("duplicate grant cannot repeat file effect", calls == 1)

            val denied = fresh()
            denied.pauseCurrentTask()
            denied.resumeCurrentTask()
            verify("resume while denied rechecks without execution", denied.phase == AgentPhase.BLOCKED && calls == 1 &&
                AgentRuntimePermissionContinuation.parse(denied.lastActionResult) != null)
            val deniedPending = requireNotNull(AgentRuntimePermissionContinuation.parse(denied.lastActionResult))
            denied.cancelCurrentTask()
            verify("blocked cancellation projects terminal state", denied.phase == AgentPhase.CANCELLED &&
                denied.executionLoop.snapshot?.phase == AgentExecutionLoopPhase.CANCELLED &&
                ledger.snapshot(id)?.state == AgentRunControlState.CANCELLED)
            granted = true
            val cancelled = runtime()
            cancelled.continueAfterAndroidPermission(deniedPending)
            verify("cancelled work stays cancelled after reload and grant", cancelled.phase == AgentPhase.CANCELLED && calls == 1)
            return JSONObject().put("scope", id).put("started_at_ms", started)
                .put("completed_at_ms", System.currentTimeMillis()).put("passed", true).put("checks", JSONArray(checks))
                .put("test_file_write_count", calls).put("model_calls", 0).put("system_permission_changes", 0)
                .put("cleanup_verified", true)
        } finally {
            sessions.clear()
            if (file.exists()) check(file.delete())
            ledger.close()
            check(context.deleteDatabase(database))
            check(sessions.load() == null && !file.exists()) { "Fixture cleanup failed" }
        }
    }
}
