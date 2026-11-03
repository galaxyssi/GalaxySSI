package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Dedicated local records only: no model, hardware command or user task is executed. */
internal object AgentOperationRuntimeDeviceFixture {
    fun run(context: Context): JSONObject {
        val suffix = UUID.randomUUID().toString()
        val conversation = "operation-projection-$suffix"
        val turn = "projection-turn-$suffix"
        val runtime = "projection-runtime-$suffix"
        val key = "task:$turn"
        val database = "debug-operation-projection-$suffix.db"
        val ledger = AgentRunEventStore(context, database)
        val sessions = SharedPreferencesAgentSessionStore(context, key)
        val checks = mutableListOf<String>()
        try {
            val store = AgentDeviceOperationStore(ledger) { requested ->
                check(requested == turn)
                SharedPreferencesAgentSessionStore(context, key).load()
            }
            val goal = "Read and verify a dedicated synthetic document"
            store.recordPlan(conversation, goal, null, sourceTurnId = turn, sourceSessionId = runtime)
            val checkpoint = requireNotNull(ledger.latestEvent(AgentDeviceOperationCheckpoint.runId(conversation)))
            check(checkpoint.payload["status"] == "prepared")
            check(checkpoint.payload["source_session_id"] == runtime)
            check(store.get(conversation)?.status == "unknown")
            checks += "plan_is_not_execution_completion"
            val action = AgentAction("synthetic-complete", AgentActionKind.DRAFT_PLAN, "task-complete", AgentRisk.LOW,
                AgentActionStatus.COMPLETED, "Synthetic result", mapOf(INTERNAL_CONVERSATION_ID to conversation, INTERNAL_TURN_ID to turn))
            val plan = AgentPlan(goal, ScreenContext("Test", pageTitle = "Test"), emptyList(), listOf(action))
            fun state(phase: AgentPhase, loop: AgentExecutionLoopPhase): AgentSessionSnapshot {
                val now = System.currentTimeMillis()
                return AgentSessionSnapshot(runtime, phase, goal, plan.screen, plan, emptyList(),
                    AgentActionResult(action.id, true, "Synthetic observation"), executionLoopSnapshot = AgentExecutionLoopSnapshot(
                        turn, loop, AgentExecutionLoopBudget(), AgentExecutionLoopUsage(),
                        lastProgressAtMillis = now, startedAtMillis = now, updatedAtMillis = now),
                    processInstanceId = AgentProcessIdentity.instanceId, updatedAtMillis = now)
            }
            for ((phase, loop) in listOf(AgentPhase.EXECUTING to AgentExecutionLoopPhase.ACT,
                AgentPhase.WAITING_RESPONSE to AgentExecutionLoopPhase.WAITING_RESPONSE,
                AgentPhase.PAUSED to AgentExecutionLoopPhase.PAUSED, AgentPhase.COMPLETED to AgentExecutionLoopPhase.COMPLETED)) {
                sessions.save(state(phase, loop))
                check(store.get(conversation)?.status == phase.name.lowercase())
                checks += "reopen_${phase.name.lowercase()}"
            }
            val proposed = plan.copy(actions = listOf(action.copy(status = AgentActionStatus.PROPOSED)))
            val permission = AgentRuntimePermissionContinuation(runtime, conversation, turn, plan.planId, plan.revision,
                action.id, listOf("android.permission.READ_CALENDAR"))
            sessions.save(state(AgentPhase.BLOCKED, AgentExecutionLoopPhase.BLOCKED).copy(
                currentPlan = proposed, lastActionResult = permission.result(false)))
            check(store.get(conversation)?.status == "waiting_permission")
            checks += "reopen_permission_wait_without_dispatch"
            sessions.save(state(AgentPhase.CANCELLED, AgentExecutionLoopPhase.CANCELLED).copy(currentGoal = "", currentPlan = null))
            check(store.get(conversation)?.status == "cancelled")
            checks += "cancelled_after_plan_clear"
            sessions.save(state(AgentPhase.COMPLETED, AgentExecutionLoopPhase.COMPLETED).copy(sessionId = "other-runtime"))
            check(store.get(conversation)?.status == "unknown")
            checks += "foreign_runtime_rejected"
            check(ledger.latestEvent(checkpoint.runId)?.sequence == checkpoint.sequence)
            checks += "projection_does_not_append_events"
            return JSONObject().put("passed", true).put("cases", JSONArray(checks))
        } finally {
            sessions.clear()
            ledger.close()
            check(context.deleteDatabase(database)) { "Projection fixture cleanup failed" }
        }
    }
}
