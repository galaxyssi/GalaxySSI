package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Read only the identities owned by an existing synthetic-suite checkpoint. */
@RunWith(AndroidJUnit4::class)
class BusinessScenarioDiagnosticTest {
    @Test fun inspectCheckpoint() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("business_inspect") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-S9480"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = requireNotNull(args.getString("business_run"))
        val case = requireNotNull(args.getString("business_case"))
        require(run.matches(Regex("[A-Za-z0-9_-]{1,64}")) && case.matches(Regex("B[0-9]{3}")))
        val directory = File(context.getExternalFilesDir(null), "business-eval/$run")
        val report = JSONObject(File(directory, "$case.json").readText())
        val conversation = report.getString("conversation")
        val key = report.getString("window_key")
        require(key == "business-$run-$case")
        val turns = report.getJSONArray("turns")
        val ids = (0 until turns.length()).map { turns.getJSONObject(it).optString("turn_id") }.toSet()
        val workspaces = EncryptedAgentWorkspaceStore(context).list().filter {
            it.conversationId == conversation && it.taskId in ids
        }
        val teams = EncryptedAgentTeamExecutionStore(context).snapshots().filter {
            it.conversationId == conversation && it.taskId in ids
        }
        val output = JSONObject().put("conversation", conversation).put("captured_at", System.currentTimeMillis())
            .put("workspaces", JSONArray(workspaces.map {
                JSONObject().put("id", it.workspaceId).put("status", it.status.name)
                    .put("plan", it.currentPlanSnapshot).put("result", it.resultJson).put("error", it.errorMessage)
                    .put("events", JSONArray(it.eventJournal.map { e ->
                        JSONObject().put("kind", e.kind).put("message", e.message).put("payload", e.payloadJson)
                    }))
            })).put("teams", JSONArray(teams.map {
                JSONObject().put("id", it.supervisorRunId).put("state", it.state.name)
                    .put("goal", it.goal).put("output", it.finalOutput).put("members", JSONArray(it.members.map { m ->
                        JSONObject().put("agent", m.agentId).put("role", m.role).put("status", m.status.name)
                            .put("output", m.output).put("error", m.errorMessage)
                    }))
            })).put("pending_responses", JSONArray(AgentConnectorResponseStore.pending(context).filter {
                it.conversationId == conversation && it.turnId in ids
            }.map {
                JSONObject().put("source", it.sourceMessageId).put("turn", it.turnId)
                    .put("content", it.content).put("success", it.success)
            })).put("transcript", JSONArray(AgentTranscriptStore(context, key).list(conversation).filter {
                it.turnId in ids
            }.map {
                JSONObject().put("turn", it.turnId).put("role", it.role.name).put("text", it.text)
                    .put("dedupe", it.dedupeKey).put("task", it.taskId)
            }))
        val ledger = EncryptedAgentManagedResponseLedger(context)
        output.put("managed_pending", JSONArray(teams.flatMap { ledger.pendingForSupervisor(it.supervisorRunId) }.map {
            JSONObject().put("owner", it.ownerRunId).put("state", it.state.name).put("source", it.sourceMessageId)
                .put("contact", it.contactId).put("conversation", it.conversationId).put("turn", it.turnId)
                .put("task", it.taskId).put("response", it.response?.content)
        })).put("managed_completed", JSONArray(ledger.completedUnapplied().filter {
            it.conversationId == conversation
        }.map { JSONObject().put("owner", it.ownerRunId).put("source", it.sourceMessageId).put("response", it.response?.content) }))
        val pendingBodies = JSONArray()
        val inbox = GalaxySSILinkDeliveryStore.inbox(context)
        var cursor = ""
        do {
            val page = inbox.pending(cursor)
            page.forEach {
                val payload = JSONObject(it.payload)
                if (payload.optString("conversation_id") == conversation) pendingBodies.put(payload)
            }
            cursor = page.lastOrNull()?.recordKey.orEmpty()
        } while (cursor.isNotEmpty())
        output.put("transport_pending", pendingBodies)
        val sources = teams.flatMap { ledger.pendingForSupervisor(it.supervisorRunId) }
        output.put("identities", JSONArray(sources.map {
            val identity = AgentTaskIdentityStore.find(context, it.contactId, it.sourceMessageId)
            val probe = AgentConnectorResponse(it.sourceMessageId, it.contactId, "probe", it.conversationId, it.turnId, it.taskId)
            JSONObject().put("source", it.sourceMessageId).put("registered_task", identity?.taskId)
                .put("registered_turn", identity?.turnId).put("received", AgentConnectorResponseStore.wasRecorded(context, probe))
                .put("terminal", AgentTerminalDeliveryStore.isTerminal(context, it.sourceMessageId))
                .put("superseded", AgentPendingDeliveryStore.isSuperseded(context, it.sourceMessageId, it.conversationId, it.turnId))
                .put("current_execution", AgentConnectorResponseStore.isCurrentExecution(context, probe))
                .put("pending_delivery", AgentPendingDeliveryStore.find(context, it.sourceMessageId, it.contactId)?.toString())
        }))
        args.getString("business_remote_message_id")?.let { message ->
            require(message.matches(Regex("[a-f0-9-]{36}")))
            val contact = sources.firstOrNull()?.contactId?.substringBefore(':').orEmpty()
            GalaxySSILinkProtocol.serverLink(context, contact)?.let { link ->
                output.put("transport_receipt", inbox.storedReceipt(GalaxySSILinkDeliveryStore.peerScope(link.routes), message)?.toString())
            }
        }
        File(directory, "$case-diagnostic.json").writeText(output.toString(2))
        println("BUSINESS_DIAGNOSTIC workspaces=${workspaces.size} teams=${teams.size}")
    }
}
