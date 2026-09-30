package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Read-only diagnostic of an explicitly selected synthetic run; never changes its verdict. */
class BusinessReplyAuditDeviceTest {
    @Test fun inspectRecordedReplyIdentity() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("business_identity_audit") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-S9480"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = requireNotNull(args.getString("business_run"))
        val case = requireNotNull(args.getString("business_cases"))
        require(run.matches(Regex("[A-Za-z0-9_-]{1,64}")))
        require(case.matches(Regex("[AB][0-9]{3}")))
        val directory = File(context.getExternalFilesDir(null), "business-eval/$run")
        val report = JSONObject(File(directory, "$case.json").readText())
        val catalog = JSONObject(File(directory, "catalog.json").readText())
        require(report.getString("catalog_sha256") == catalog.getString("catalog_sha256"))
        require(report.getString("window_key") == "business-$run-$case")
        val index = requireNotNull(args.getString("business_capture_turn")).toInt()
        val turn = report.getJSONArray("turns").getJSONObject(index)
        require(turn.getString("state") == "completed")
        val reference = AgentTranscriptEntry(
            id = turn.getString("initial_entry_id"), role = AgentTranscriptRole.ASSISTANT,
            text = turn.getString("reply"), timestampMillis = 0L,
            conversationId = report.getString("conversation"), turnId = turn.getString("turn_id"),
            taskId = turn.getString("task_id"), richOutputJson = turn.optString("rich_output"))
        val entries = AgentTranscriptStore(context, report.getString("window_key"))
            .list(reference.conversationId).filter { it.turnId == reference.turnId }
        val workspace = EncryptedAgentWorkspaceStore(context).find(reference.turnId)
        fun describe(entry: AgentTranscriptEntry): JSONObject = JSONObject()
            .put("id", entry.id).put("role", entry.role.name).put("task_id", entry.taskId)
            .put("turn_id", entry.turnId).put("conversation_id", entry.conversationId)
            .put("text", entry.text).put("dedupe_key", entry.dedupeKey)
            .put("timestamp", entry.timestampMillis)
            .put("terminal_reply", AgentTaskTerminalReplyPolicy.isTerminalReply(entry))
            .put("delivery_failure_source", AgentDeliveryFailurePolicy.sourceMessageId(entry))
            .put("policy_delivered", workspace?.let { ConversationHubAgentStatusPolicy.hasDeliveredReply(it, entry) })
            .put("live_stream", AgentTranscriptRenderPolicy.isLiveStream(entry))
            .put("blocks", JSONArray(AgentRichContentCodec.decode(entry.richOutputJson).map { block ->
                JSONObject().put("id", block.id).put("type", block.type.name)
                    .put("title", block.title).put("text", block.text).put("mime", block.mimeType)
                    .put("uri", block.uri).put("metadata", JSONObject(block.metadata))
                    .put("local_file_present", AgentDesktopArtifactStore.localFile(context, block) != null)
            }))
        val audit = JSONObject().put("case_id", case).put("turn_index", index)
            .put("app_version", BuildConfig.VERSION_NAME)
            .put("workspace", workspace?.let { JSONObject().put("workspace_id", it.workspaceId)
                .put("task_id", it.taskId).put("conversation_id", it.conversationId)
                .put("status", it.status.name).put("cancelled", it.cancellationRequested)
                .put("created_at", it.createdAtMillis).put("remote_run_id", it.remoteRunId)
                .put("result", JSONObject(it.resultJson))
                .put("events", JSONArray(it.eventJournal.map { event ->
                    JSONObject().put("kind", event.kind).put("timestamp", event.timestampMillis)
                        .put("sequence", event.sequence)
                })) })
            .put("reference", describe(reference))
            .put("candidates", JSONArray(entries.filter { it.role == AgentTranscriptRole.ASSISTANT }.map(::describe)))
            .put("matched", resolveBusinessReply(entries, reference, workspace)?.id.orEmpty())
        val output = File(directory, "identity-audit-$index-${System.currentTimeMillis()}.json")
        output.writeText(audit.toString(2))
        println("BUSINESS_IDENTITY_AUDIT ${output.absolutePath}")
    }
}
