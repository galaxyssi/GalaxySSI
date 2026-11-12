package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Opt-in inspection only: no task dispatch, state edits, or transcript writes. */
@RunWith(AndroidJUnit4::class)
class ConversationScheduleDiagnosticsTest {
    @Test fun fingerprintRequestedMessages() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("schedule_message_fingerprint") == "true")
        val ids = args.getString("conversation_ids").orEmpty().split(',').filter(String::isNotBlank)
        require(ids.isNotEmpty() && ids.size <= 10)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val transcript = AgentTranscriptStore(context)
        val result = JSONArray(ids.map { id ->
            var before: Long? = null
            var count = 0
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            do {
                val page = transcript.page(id, before, 50)
                for (entry in page.entries.asReversed()) {
                    val fields = listOf(entry.id, entry.role.name, entry.text, entry.timestampMillis.toString(),
                        entry.dedupeKey, entry.conversationId, entry.turnId, entry.taskId,
                        entry.richOutputJson, entry.collaborationJson)
                    fields.forEach { field ->
                        val bytes = field.toByteArray(Charsets.UTF_8)
                        digest.update(java.nio.ByteBuffer.allocate(4).putInt(bytes.size).array())
                        digest.update(bytes)
                        bytes.fill(0)
                    }
                    count++
                }
                before = page.nextBeforeSequence
            } while (page.hasMore && before != null)
            JSONObject().put("conversation", id).put("entries", count)
                .put("sha256", digest.digest().joinToString("") { "%02x".format(it) })
        })
        File(context.filesDir, "schedule-message-fingerprint.json").writeText(result.toString(2))
    }

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
        val transcript = AgentTranscriptStore(context)
        report.put("origins", JSONArray(tasks.map { task ->
            val entries = transcript.page(task.action.conversationId, pageSize = 200).entries
            val receipts = entries.filter { it.dedupeKey.startsWith("schedule-") &&
                AgentRichContentCodec.decode(it.richOutputJson).any { block ->
                    block.actions.any { action -> action.verb == "edit_scheduled_task" && action.value == task.taskId }
                } }
            JSONObject().put("task", task.taskId).put("created", task.createdAtMillis)
                .put("revision", task.revision).put("label", task.action.scheduleText)
                .put("trigger", task.trigger.toString()).put("receipts", JSONArray(receipts.map { entry ->
                    JSONObject().put("id", entry.id).put("dedupe", entry.dedupeKey).put("timestamp", entry.timestampMillis)
                        .put("user", entries.firstOrNull { it.role == AgentTranscriptRole.USER && it.turnId == entry.turnId }?.text?.take(500))
                }))
        }))
        File(context.filesDir, "schedule-inspection.json").writeText(report.toString(2))
        println("SCHEDULE_DIAGNOSTIC saved to private schedule-inspection.json")
    }
}
