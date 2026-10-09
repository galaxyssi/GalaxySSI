package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

/** Explicit execution endpoint. Read-only recall never reaches this handler. */
internal object AndroidCollaborationSavedToolTest {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val process = UUID.randomUUID().toString()
    private val slots = Semaphore(2)
    private val cancellations = ConcurrentHashMap<String, AgentNativeToolCancellationSource>()

    fun receive(context: Context, payload: JSONObject, desktop: String) {
        if (!CollaborationSavedToolTest.valid(payload, System.currentTimeMillis()) ||
            !AndroidCollaborationRemoteRecall.paired(context, payload, desktop) ||
            !AgentTaskIdentityStore.matchesRegistered(context, payload)) return
        val app = context.applicationContext
        val request = JSONObject(payload.toString())
        scope.launch {
            try {
                val access = AndroidCollaborationRemoteRecall.access(app, request, desktop)
                val response = if (access == null) CollaborationRemoteRecallProtocol.unavailable() else {
                    val journal = CollaborationResearchWorkspace(app).savedToolTests(access, process)
                    val input = request.getJSONObject("arguments")
                    val id = input.getString("execution_id")
                    when (input.getString("mode")) {
                        "start" -> {
                            val admitted = journal.start(input)
                            if (admitted.launch) execute(app, request, desktop, access, journal, input)
                            journal.describe(admitted.record)
                        }
                        "cancel" -> {
                            val record = journal.cancel(id)
                            cancellations[journal.key(id)]?.cancel()
                            journal.describe(record)
                        }
                        else -> journal.describe(journal.read(id))
                    }
                }
                val safe = if (access != null && AndroidCollaborationRemoteRecall.access(app, request, desktop) != access)
                    CollaborationRemoteRecallProtocol.unavailable() else response
                reply(app, request, desktop, safe)
            } catch (error: Exception) {
                Log.w("GalaxySSIToolTest", "Saved test request rejected: ${error.javaClass.simpleName}")
                runCatching { reply(app, request, desktop, JSONObject().put("success", false).put("status", "rejected")
                    .put("error", error.message ?: "Saved test request could not be admitted")
                    .put("do_not_reexecute", true)) }
            }
        }
    }

    private fun execute(app: Context, request: JSONObject, desktop: String, access: CollaborationWorkspaceAccess,
                        journal: CollaborationSavedToolTest, input: JSONObject) {
        val id = input.getString("execution_id")
        val key = journal.key(id)
        val cancellation = AgentNativeToolCancellationSource()
        check(cancellations.putIfAbsent(key, cancellation) == null)
        scope.launch {
            try {
                slots.withPermit {
                    if (AndroidCollaborationRemoteRecall.access(app, request, desktop) != access) {
                        journal.cancel(id)
                        return@withPermit
                    }
                    if (!journal.running(id)) return@withPermit
                    val watcher = scope.launch {
                        while (isActive) {
                            val authorized = runCatching { AndroidCollaborationRemoteRecall.access(app, request, desktop) == access &&
                                journal.read(id)?.optString("state") == "running" }.getOrDefault(false)
                            if (!authorized) {
                                cancellation.cancel()
                                break
                            }
                            delay(2_000)
                        }
                    }
                    try {
                        val observation = requireNotNull(AgentRemoteOutcomeCodec.observation(request))
                        journal.finish(id, invokeNative(app, access, observation.sourceMessageId, key, input, cancellation.token))
                    } finally { watcher.cancel() }
                }
            } catch (error: Exception) {
                Log.w("GalaxySSIToolTest", "Saved tool execution interrupted: ${error.javaClass.simpleName}")
                runCatching { journal.finish(id, JSONObject().put("native_status", "interrupted")
                    .put("passed", JSONObject.NULL).put("reason", error.message ?: "Execution interrupted")
                    .put("do_not_reexecute", true)) }
            } finally { cancellations.remove(key, cancellation) }
        }
    }

    internal fun invokeNative(app: Context, access: CollaborationWorkspaceAccess, source: Long, key: String,
                              input: JSONObject, cancellation: AgentNativeToolCancellationToken): JSONObject {
        CollaborationSavedToolTest.validate(input)
        require(CollaborationEvidenceLedger(app).binding(source, access.groupId, access.turnId) == access) { "Native execution binding changed" }
        val registry = AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(app),
            auditStore = EncryptedAgentNativeToolAuditStore(app), observationRecorder = CollaborationNativeEvidence(app))
            .registerAll(AgentOnDeviceRuntimeTools.definitions(app))
        val invocation = AgentNativeToolInvocationContext(
            invocationId = "saved-test-${AgentNativeJsonCodec.sha256(key)}", sessionId = access.runId,
            conversationId = access.groupId, turnId = access.turnId, collaborationSourceMessageId = source,
            callerId = "galaxyssi.collaboration.saved_test", idempotencyKey = key,
            attributes = mapOf("workspace_id" to AgentNativeJsonCodec.sha256(key))
        )
        val result = registry.invoke(AgentOnDeviceRuntimeTools.EXECUTE, CollaborationSavedToolTest.nativeInput(input),
            invocation, AgentNativeToolInvocationHooks(cancellationToken = cancellation))
        val full = JSONObject(result.toJson())
        // Full output stays in the evidence ledger; status replies remain small and recoverable.
        val receipt = full.getJSONObject("output").optJSONObject(CollaborationExecutableTool.RECEIPT)
        return JSONObject().put("native_status", result.status.wireValue).put("passed", receipt?.opt("passed") ?: JSONObject.NULL)
            .put("error", full.optJSONObject("error")?.let { error -> JSONObject()
                .put("code", error.optString("code")).put("message", error.optString("message").take(500))
                .put("details_in_original_evidence", true).apply {
                    error.optJSONObject("details")?.optJSONObject(CollaborationRecordValidation.DETAIL)?.let {
                        put(CollaborationRecordValidation.DETAIL, it)
                    }
                } } ?: JSONObject.NULL)
            .put("native_receipt", full.getJSONObject("receipt"))
            .put("galaxyssi_evidence_receipt", full.optJSONObject("galaxyssi_evidence_receipt") ?: JSONObject.NULL)
            .put("galaxyssi_evidence_recording", full.optJSONObject("galaxyssi_evidence_recording") ?: JSONObject.NULL)
            .put("read_original", "Use collaboration_recall mode=evidence with the exact receipt before reviewing, repairing or comparing.")
    }

    private fun reply(app: Context, request: JSONObject, desktop: String, result: JSONObject) {
        if (!CollaborationSavedToolTest.valid(request, System.currentTimeMillis()) ||
            !AndroidCollaborationRemoteRecall.paired(app, request, desktop)) return
        val response = CollaborationRemoteEvidenceProtocol.scope(request)
            .put("type", CollaborationSavedToolTest.RESPONSE).put("contract", CollaborationSavedToolTest.CONTRACT)
            .put("request_id", request.getString("request_id")).put("phase", request.getString("phase")).put("result", result)
        GalaxySSIMqttClient.publishJsonForTransport(response,
            GalaxySSIMqttClient.outgoingTopicFor(request.getString("contact_id")), request.getString("contact_id"))
    }
}
