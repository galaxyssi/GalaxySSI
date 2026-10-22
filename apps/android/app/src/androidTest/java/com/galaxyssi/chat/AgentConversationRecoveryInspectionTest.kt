package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in, bounded metadata inspection. Never submits or resumes a user's task. */
@RunWith(AndroidJUnit4::class)
class AgentConversationRecoveryInspectionTest {
    @Test fun inspectRequestedConversations() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("inspect_conversation_recovery") == "true")
        val ids = args.getString("conversation_ids").orEmpty().split(',').filter(String::isNotBlank).toSet()
        val query = args.getString("conversation_title_contains").orEmpty()
        require(ids.isNotEmpty() || query.length >= 4)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val transcript = AgentTranscriptStore(context)
        val conversations = transcript.conversationPage(AgentConversationStatus.ACTIVE, pageSize = 100)
            .items.filter { it.id in ids || (query.isNotBlank() && it.title.contains(query)) }
        val unread = AgentReplyUnreadStore.snapshot(context)
        val report = JSONArray(conversations.map { conversation ->
            val page = transcript.page(conversation.id, pageSize = 100)
            val tokens = unread[conversation.id].orEmpty()
            val turns = page.entries.filter { it.role == AgentTranscriptRole.USER }.map { it.turnId }.distinct()
            JSONObject().put("id", conversation.id).put("title", conversation.title)
                .put("model", conversation.selectedModelOrAgent).put("unread", JSONArray(tokens))
                .put("has_more", page.hasMore).put("entries", JSONArray(page.entries.map { entry ->
                    JSONObject().put("id", entry.id).put("turn", entry.turnId).put("task", entry.taskId)
                        .put("role", entry.role.name).put("dedupe", entry.dedupeKey)
                        .put("timestamp", entry.timestampMillis).put("characters", entry.text.length)
                        .put("unread", AgentReplyUnreadPolicy.token(entry) in tokens)
                })).put("turns", JSONArray(turns.map { turn ->
                    val workspace = EncryptedAgentWorkspaceStore(context).find(turn)
                    val snapshot = SharedPreferencesAgentSessionStore(context, "task:$turn").load()
                    val loop = snapshot?.executionLoopSnapshot
                    val plan = snapshot?.currentPlan
                    JSONObject().put("turn", turn).put("phase", snapshot?.phase?.name)
                        .put("workspace_status", workspace?.status?.name).put("workspace_revision", workspace?.revision)
                        .put("loop", loop?.let { JSONObject(AgentExecutionLoopJsonCodec.encode(it)) })
                        .put("result", snapshot?.lastActionResult?.message?.take(1000))
                        .put("result_metadata", JSONObject(snapshot?.lastActionResult?.metadata.orEmpty()))
                        .put("connectors", JSONArray((plan?.actionHistory.orEmpty() + plan?.actions.orEmpty())
                            .filter { it.kind == AgentActionKind.CALL_CONNECTOR }.map { action ->
                                JSONObject().put("id", action.id).put("target", action.target)
                                    .put("status", action.status.name).put("result", action.result.take(400))
                                    .put("parameters", JSONObject(action.parameters.filterKeys { key ->
                                        key in setOf("connector_id", "manual_target_locked", "manual_model_id",
                                            "auto_reroute_on_failure", "routing_fallback_ids", "supervised_iteration")
                                    }))
                            }))
                }))
        })
        File(context.filesDir, "conversation-recovery-inspection.json").writeText(report.toString(2))
    }
}
