package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted progress storage and local adapter, with explicitly scripted model decisions. */
@RunWith(AndroidJUnit4::class)
class AgentLocalModelProgressDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun identity(conversation: String) = AgentLocalDispatchIdentity(
        ChatHistoryStore.reserveMessageId(context), "local-llm", conversation,
        "public-turn-${UUID.randomUUID()}", "public-native-${UUID.randomUUID()}", "public-action")
    private fun event(id: AgentLocalDispatchIdentity, sequence: Long, type: AgentModelToolLoopEventType,
                      details: AgentNativeJsonObject = emptyMap()) = AgentModelToolLoopEvent(
        sequence, type, System.currentTimeMillis(), id.taskId, id.turnId, id.taskId, "a".repeat(64), 1,
        toolCallId = "public-call", details = details + mapOf("tool_id" to "public.operation", "model_loop_id" to "public-loop"))

    @Test fun progressUpdatesOneEncryptedProcessRowAndNeverTheForegroundConversationOrAnswer() {
        val store = AgentTranscriptStore(context)
        val conversation = store.createAgentConversation("Public local progress ${UUID.randomUUID()}").id
        val foreign = store.createAgentConversation("Public other progress ${UUID.randomUUID()}").id
        val id = identity(conversation)
        val cancellation = AgentNativeToolCancellationSource()
        val sink = AgentLocalModelProgress.sink(context, id, false, cancellation.token, emptyList())
        try {
            sink.onEvent(event(id, 1, AgentModelToolLoopEventType.TOOL_STARTED))
            sink.onEvent(event(id, 2, AgentModelToolLoopEventType.TOOL_PROGRESS,
                mapOf("message" to "Public download password=public-test-secret", "percent" to 37,
                    "arguments" to mapOf("private" to "not-for-ui"), "assistant_text" to "not-a-final-answer")))
            val progressing = AgentTranscriptStore(context).list(conversation)
            assertEquals(1, progressing.size)
            assertEquals(AgentTranscriptRole.PROCESS, progressing.single().role)
            assertEquals(id.turnId, progressing.single().turnId)
            assertTrue(progressing.single().text.contains("37%"))
            assertFalse(progressing.single().text.contains("public-test-secret"))
            assertFalse(progressing.single().text.contains("not-for-ui"))
            assertTrue(AgentTranscriptStore(context).list(foreign).isEmpty())
            sink.onEvent(event(id, 3, AgentModelToolLoopEventType.TOOL_FINISHED, mapOf("status" to "failed", "error_code" to "dependency_missing")))
            val failed = AgentTranscriptStore(context).list(conversation).single()
            assertTrue(failed.text.contains("dependency_missing"))
            sink.onEvent(event(id, 2, AgentModelToolLoopEventType.TOOL_PROGRESS, mapOf("percent" to 99)))
            assertEquals(failed, AgentTranscriptStore(context).list(conversation).single())
            cancellation.cancel()
            sink.onEvent(event(id, 4, AgentModelToolLoopEventType.TOOL_FINISHED, mapOf("status" to "succeeded")))
            assertEquals(failed, AgentTranscriptStore(context).list(conversation).single())
        } finally { store.deleteConversation(conversation); store.deleteConversation(foreign) }
    }

    @Test fun activityOnlyTouchesTheExactNonterminalTurnWorkspaceAndCreatesNoTimerHeartbeat() {
        val transcripts = AgentTranscriptStore(context)
        val conversation = transcripts.createAgentConversation("Public local liveness ${UUID.randomUUID()}").id
        val id = identity(conversation)
        val store = EncryptedAgentWorkspaceStore(context)
        try {
            store.upsert(AgentWorkspace(id.turnId, id.turnId, "$conversation-foreign", id.turnId,
                status = AgentWorkspaceStatus.WAITING_RESPONSE))
            val sink = AgentLocalModelProgress.sink(context, id, false, AgentNativeToolCancellationToken.NONE, emptyList())
            sink.onEvent(event(id, 1, AgentModelToolLoopEventType.MODEL_REQUESTED))
            assertTrue(requireNotNull(store.find(id.turnId)).eventJournal.isEmpty())
            assertTrue(store.delete(id.turnId))
            store.upsert(AgentWorkspace(id.turnId, id.turnId, conversation, id.turnId,
                status = AgentWorkspaceStatus.WAITING_RESPONSE))
            sink.onEvent(event(id, 2, AgentModelToolLoopEventType.MODEL_REQUESTED))
            val heartbeat = requireNotNull(store.find(id.turnId))
            assertEquals(AgentTaskEventKinds.HEARTBEAT, heartbeat.eventJournal.last().kind)
            sink.onEvent(event(id, 3, AgentModelToolLoopEventType.TOOL_PROGRESS, mapOf("percent" to 10)))
            val progress = requireNotNull(store.find(id.turnId))
            assertEquals(AgentTaskEventKinds.PROGRESS, progress.eventJournal.last().kind)
            assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, progress.status)
            val cancelled = store.upsert(progress.copy(status = AgentWorkspaceStatus.CANCELLED), progress.revision)
            sink.onEvent(event(id, 4, AgentModelToolLoopEventType.MODEL_REQUESTED))
            assertEquals(cancelled, store.find(id.turnId))
        } finally { store.delete(id.turnId); transcripts.deleteConversation(conversation) }
    }

    @Test fun localAdapterPersistsFailureRepairAndVerificationProgressBeforeReturningTheFinalAnswer() = runBlocking {
        val transcripts = AgentTranscriptStore(context)
        val conversation = transcripts.createAgentConversation("Public local loop ${UUID.randomUUID()}").id
        val id = identity(conversation)
        val calls = mutableListOf<String>()
        var repaired = false
        var rounds = 0
        val tool = AgentNativeToolDefinition(AgentNativeToolDescriptor("public.operation", "1.0.0", "Public operation",
            "Public repair fixture", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(mapOf("operation" to AgentNativeJsonSchema.string()), setOf("operation")),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW), AgentNativeToolExecutor {
            it.reportProgress(stage = "public_work", message = "Public progress", percent = 50)
            val operation = it.input.getValue("operation").toString()
            calls += operation
            when (operation) {
                "build" -> if (!repaired) AgentNativeToolExecutionResult.failure("public_dependency_missing", "Public fixture dependency is missing")
                    else AgentNativeToolExecutionResult.success(mapOf("verified" to true))
                "repair" -> { repaired = true; AgentNativeToolExecutionResult.success(mapOf("installed" to true)) }
                else -> error("Unexpected public operation")
            }
        })
        val registry = AgentNativeToolRegistry().register(tool)
        val catalog = registry.availableCatalog()
        val local = LocalModelWebToolSession(context, "public-scripted-local-model", false, inference = { _, prompt ->
            val operation = when (++rounds) {
                1 -> "build"
                2 -> {
                    assertTrue(prompt.contains("public_dependency_missing"))
                    assertTrue(transcripts.list(conversation).any { it.text.contains("public_dependency_missing") })
                    "repair"
                }
                3 -> { assertTrue(prompt.contains("installed")); "build" }
                else -> { assertTrue(prompt.contains("verified")); null }
            }
            val text = if (operation != null) {
                AgentNativeJsonCodec.stringify(mapOf("answer" to "公开测试：观察后继续执行。", "tool_calls" to listOf(
                    mapOf("id" to "public-$rounds", "name" to "public.operation", "arguments" to mapOf("operation" to operation)))))
            } else {
                assertTrue(transcripts.list(conversation).all { it.role == AgentTranscriptRole.PROCESS })
                AgentNativeJsonCodec.stringify(mapOf("answer" to "公开测试：修复并验证完成。", "tool_calls" to emptyList<Any>()))
            }
            LocalModelInferenceResult(text = text, profileId = "public-scripted-local-model", backend = "scripted-device-fixture",
                smeAvailable = false, elapsedMillis = 1L, promptTokens = 20L, generatedTokens = 5L)
        })
        try {
            val outcome = AgentModelToolLoop(local.adapter(catalog.descriptors), registry,
                disclosedToolManifestJson = catalog.manifest.json, disclosedToolManifestSha256 = catalog.manifest.sha256)
                .run(AgentModelToolLoopRequest.forUserMessage(id.taskId, conversation, id.turnId, id.taskId,
                    "public-workspace", "公开测试：遇到失败后处理并验证。",
                    budget = AgentModelToolLoopBudget(maxRetriesPerCall = 0, enforceCountLimits = false),
                    eventSink = AgentLocalModelProgress.sink(context, id, false, AgentNativeToolCancellationToken.NONE, catalog.descriptors))
                    .copy(loopId = "public-progress-loop"))
            assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
            assertEquals(4, rounds)
            assertEquals(listOf("build", "repair", "build"), calls)
            assertTrue(outcome.assistantText.contains("验证完成"))
            val entries = AgentTranscriptStore(context).list(conversation)
            assertEquals(3, entries.count { it.dedupeKey.contains(":tool:") })
            assertTrue(entries.any { it.text.contains("public_dependency_missing") })
            assertTrue(entries.all { it.role == AgentTranscriptRole.PROCESS })
            assertFalse(entries.any { it.text == outcome.assistantText })
        } finally { transcripts.deleteConversation(conversation) }
    }

    @Test fun managedMemberProgressRequiresHostBindingAndNeverLeaksIntoOrdinaryTranscript() {
        val transcripts = AgentTranscriptStore(context)
        val conversation = transcripts.createAgentConversation("Public managed local progress ${UUID.randomUUID()}").id
        val groups = CollaborationGroupStore(context)
        val bindings = AgentEncryptedDatabase(context, "collaboration_progress_bindings")
        val sources = mutableListOf<Long>()
        try {
            groups.update(conversation) { it.copy(members = emptyList()) }
            val task = "public-team-task-${UUID.randomUUID()}"
            val turn = "public-team-turn-${UUID.randomUUID()}"
            repeat(2) { index ->
                val member = AgentTeamMember(agentId = "local-llm", deliveryMode = AgentDeliveryMode.OBSERVE,
                    instanceId = "public-member-$index", role = "Specialist",
                    context = mapOf("collaboration_group_id" to conversation, "collaboration_name" to "Public member $index"))
                val request = AgentRunRequest(conversation, turn, task, parentRunId = "public-parent-$conversation", goal = "公开进度测试。")
                CollaborationProgressStore.register(context, AgentTeamMemberExecutionContext(member, request,
                    AgentSubagentContextHandoff("", emptyList(), 0, 100, false), 1, AgentSubagentProvenance()))
                val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}")
                sources += source
                val id = AgentLocalDispatchIdentity(source, "local-llm", conversation, turn, task, "public-member-action-$index")
                AgentLocalModelProgress.sink(context, id, true, AgentNativeToolCancellationToken.NONE, emptyList())
                    .onEvent(event(id, 1, AgentModelToolLoopEventType.TOOL_PROGRESS, mapOf("message" to "Public member $index")))
                val wrong = id.copy(taskId = "wrong-task")
                AgentLocalModelProgress.sink(context, wrong, true, AgentNativeToolCancellationToken.NONE, emptyList())
                    .onEvent(event(wrong, 1, AgentModelToolLoopEventType.TOOL_PROGRESS, mapOf("message" to "Must not appear")))
            }
            val entries = transcripts.list(conversation)
            assertEquals(2, entries.size)
            assertTrue(entries.all { CollaborationTranscriptMetadata.decode(it.collaborationJson)?.activity == true })
            assertEquals(2, entries.map { requireNotNull(CollaborationTranscriptMetadata.decode(it.collaborationJson)).executionMemberId }.toSet().size)
            assertFalse(entries.any { it.text.contains("Must not appear") || it.collaborationJson.isBlank() })
        } finally {
            sources.forEach { bindings.remove(it.toString()) }
            groups.remove(conversation)
            transcripts.deleteConversation(conversation)
        }
    }
}
