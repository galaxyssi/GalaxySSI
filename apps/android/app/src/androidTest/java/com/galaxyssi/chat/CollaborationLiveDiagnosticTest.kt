package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicitly scoped, read-only diagnostics. Never resumes or mutates a research run. */
@RunWith(AndroidJUnit4::class)
class CollaborationLiveDiagnosticTest {
    @Test fun inspectSelectedGroup() {
        val group = InstrumentationRegistry.getArguments().getString("collaboration_diagnostic_group").orEmpty()
        assumeTrue(group.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        requireNotNull(CollaborationGroupStore(context).load(group))
        val db = AgentEncryptedDatabase(context, "galaxyssi_collaboration_workspace_v1")
        val prefix = "group:${AgentNativeJsonCodec.sha256(group)}:submission:"
        val publications = JSONArray()
        db.keys(prefix).filter { it.endsWith(":latest") }.forEach { key ->
            val latest = JSONObject(JSONObject(db.readString(key, "")).getString("payload"))
            val contractKey = key.removeSuffix("latest") + "contract"
            val contract = JSONObject(JSONObject(db.readString(contractKey, "")).getString("payload"))
            publications.put(JSONObject().put("contract", contract).put("checkpoint", latest))
        }
        val runs = AgentEncryptedDatabase(context, "galaxyssi_agent_teams_v1")
        val records = runs.keys("run:").flatMap { key ->
            val values = JSONArray(runs.readString(key, "[]"))
            (0 until values.length()).map(values::getJSONObject)
        }.filter { it.getJSONObject("request").optString("conversation_id") == group }
        val report = JSONObject().put("group", group).put("at", System.currentTimeMillis())
            .put("publications", publications).put("runs", JSONArray(records))
        val recovery = JSONArray()
        EncryptedAgentTeamExecutionStore(context).snapshots().filter { it.conversationId == group }.forEach { team ->
            val workspace = EncryptedAgentWorkspaceStore(context).find(team.taskId)
            val session = SharedPreferencesAgentSessionStore(context, "task:${team.taskId}").load()
            recovery.put(JSONObject().put("run", team.supervisorRunId).put("state", team.state)
                .put("goal_disposition", team.goalDisposition).put("next_goal_attempt", team.nextGoalAttemptAtMillis)
                .put("control", AgentTeamDurableControl(context).get(team.supervisorRunId))
                .put("parent_can_resume", AgentTeamParentDeliveryRecovery(context).canResume(team))
                .put("workspace_status", workspace?.status).put("cancelled", workspace?.cancellationRequested)
                .put("workspace_error", workspace?.errorMessage).put("session_phase", session?.phase)
                .put("session_message", session?.lastActionResult?.message)
                .put("control_audit", JSONArray(session?.auditTrail?.filter { it.event in setOf(
                    AgentAuditEvent.TASK_PAUSED, AgentAuditEvent.TASK_RESUMED, AgentAuditEvent.TASK_CANCELLED) }
                    ?.map { JSONObject().put("event", it.event).put("detail", it.detail) }.orEmpty()))
                .put("session_metadata", JSONObject(session?.lastActionResult?.metadata.orEmpty())))
        }
        report.put("recovery", recovery)
        val file = File(context.cacheDir, "collaboration-selected-diagnostic.json")
        file.writeText(report.toString(2))
        println("COLLABORATION_DIAGNOSTIC ${file.name} publications=${publications.length()} runs=${records.size}")
    }
}
