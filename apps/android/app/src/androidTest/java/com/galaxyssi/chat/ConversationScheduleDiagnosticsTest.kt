package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in inspection only: no task dispatch, state edits, or transcript writes. */
@RunWith(AndroidJUnit4::class)
class ConversationScheduleDiagnosticsTest {
    @Test fun inspectSavedSchedules() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("schedule_diagnostics") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AgentProactiveTaskStore(context)
        val tasks = ConversationScheduledTasks.tasks(context)
        val waiting = EncryptedAgentWorkspaceStore(context).list().filter {
            it.status in setOf(AgentWorkspaceStatus.WAITING_RESPONSE, AgentWorkspaceStatus.WAITING_CONFIRMATION)
        }
        val report = JSONObject().put("now", System.currentTimeMillis())
            .put("schedules", JSONArray(tasks.map { task -> JSONObject()
                .put("id", task.taskId).put("name", task.name).put("enabled", task.enabled)
                .put("conversation", task.action.conversationId).put("kind", task.action.kind.name)
                .put("next", task.nextRunAtMillis).put("last", task.lastRunAtMillis)
                .put("run_count", task.runCount).put("selection", AgentModelSelectionSettings.selection(context,
                    task.action.conversationId).toString())
                .put("runs", JSONArray(store.runs(task.taskId, 5).map { run -> JSONObject()
                    .put("id", run.runId).put("status", run.status.name).put("due", run.scheduledForMillis)
                    .put("started", run.startedAtMillis).put("completed", run.completedAtMillis)
                    .put("team", run.teamRunId).put("attempt", run.attempt)
                    .put("error", run.errorCode).put("summary", run.resultSummary.take(500)) })) }))
            .put("waiting_workspaces", JSONArray(waiting.map { workspace -> JSONObject()
                .put("id", workspace.workspaceId).put("task", workspace.taskId)
                .put("conversation", workspace.conversationId).put("status", workspace.status.name)
                .put("updated", workspace.updatedAtMillis)
                .put("task_phase", SQLiteAgentTaskStore(context).find(workspace.taskId)?.phase?.name.orEmpty()) }))
        println("SCHEDULE_DIAGNOSTIC $report")
    }
}
