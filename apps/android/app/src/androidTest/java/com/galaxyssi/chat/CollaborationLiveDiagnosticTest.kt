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
                .put("task", team.taskId).put("session_updated", session?.updatedAtMillis)
                .put("session_goal", session?.currentGoal).put("session_plan", session?.currentPlan?.planId)
                .put("goal_disposition", team.goalDisposition).put("next_goal_attempt", team.nextGoalAttemptAtMillis)
                .put("control", AgentTeamDurableControl(context).get(team.supervisorRunId))
                .put("parent_matches", session?.lastActionResult?.metadata?.get("team_run_id") == team.supervisorRunId)
                .put("workspace_status", workspace?.status).put("cancelled", workspace?.cancellationRequested)
                .put("workspace_error", workspace?.errorMessage).put("session_phase", session?.phase)
                .put("session_message", session?.lastActionResult?.message)
                .put("control_audit", JSONArray(session?.auditTrail?.filter { it.event in setOf(
                    AgentAuditEvent.TASK_PAUSED, AgentAuditEvent.TASK_RESUMED, AgentAuditEvent.TASK_CANCELLED) }
                    ?.map { JSONObject().put("event", it.event).put("detail", it.detail) }.orEmpty()))
                .put("session_metadata", JSONObject(session?.lastActionResult?.metadata.orEmpty())))
        }
        report.put("recovery", recovery)
        val workspaces = EncryptedAgentWorkspaceStore(context).list().filter { it.conversationId == group }
        report.put("workspaces", JSONArray(workspaces.map { workspace ->
            val saved = SharedPreferencesAgentSessionStore(context, "task:${workspace.workspaceId}").load()
            JSONObject().put("workspace", workspace.workspaceId).put("task", workspace.taskId)
                .put("status", workspace.status).put("phase", saved?.phase).put("updated", saved?.updatedAtMillis)
                .put("result", JSONObject(workspace.resultJson))
                .put("plan", workspace.currentPlanSnapshot)
                .put("checkpoints", JSONArray(workspace.checkpoints.map {
                    JSONObject().put("id", it.id).put("state", it.stateJson).put("plan", it.planSnapshot)
                }))
                .put("metadata", JSONObject(saved?.lastActionResult?.metadata.orEmpty()))
                .put("events", JSONArray(workspace.eventJournal.takeLast(10).map {
                    JSONObject().put("kind", it.kind).put("message", it.message).put("at", it.timestampMillis)
                }))
        }))
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val deliveries = ledger.pendingRecoveryDeliveries().filter { it.conversationId == group }
        report.put("pending_deliveries", JSONArray(deliveries.map { delivery ->
            val identity = AgentTaskIdentityStore.find(context, delivery.contactId, delivery.sourceMessageId)
            val contact = AppStore.contactById(context, delivery.contactId)
            JSONObject().put("source", delivery.sourceMessageId).put("contact", delivery.contactId)
                .put("task", delivery.taskId).put("turn", delivery.turnId)
                .put("registered_task", identity?.taskId).put("registered_turn", identity?.turnId)
                .put("route", identity?.clientRouteId).put("agent", contact?.optString("agent_id"))
        }))
        report.put("completed_unapplied", JSONArray(ledger.completedUnapplied().filter { it.conversationId == group }.map {
            JSONObject().put("source", it.sourceMessageId).put("task", it.taskId).put("turn", it.turnId)
                .put("owner", it.ownerRunId).put("completed", it.completedAtMillis)
                .put("evidence_pending", AndroidCollaborationRemoteEvidence.pending(context, group, it.sourceMessageId))
                .put("evidence_jobs", JSONArray(CollaborationRemoteEvidenceStore(context).states(group, it.sourceMessageId).map { job ->
                    JSONObject(job.toString()).apply {
                        val entries = optJSONArray("index_entries")
                        put("index_count", entries?.length() ?: 0)
                        remove("index_entries")
                    }
                }))
        }))
        val file = File(context.cacheDir, "collaboration-selected-diagnostic.json")
        file.writeText(report.toString(2))
        println("COLLABORATION_DIAGNOSTIC ${file.name} publications=${publications.length()} runs=${records.size}")
    }
}
