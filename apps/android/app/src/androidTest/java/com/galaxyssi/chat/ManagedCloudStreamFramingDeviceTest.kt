package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Loopback HTTP only. Real stream framing and scoped recall; no provider credentials or live requests. */
@RunWith(AndroidJUnit4::class)
class ManagedCloudStreamFramingDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val preface = "I'll start by inspecting the recorded host evidence directly."
    private val finalJson = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Fixture original read; claim validity remains untested.")
        .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
        .put("workspace", JSONArray()).toString()

    private inner class Fixture : java.io.Closeable {
        val id = "stream-framing-${UUID.randomUUID()}"
        val goal = "EXACT_LOCAL_FIXTURE_ORIGINAL: preserve this clause."
        private val groups = CollaborationGroupStore(context)
        val access = CollaborationWorkspaceAccess(id, "run", "turn", 1, "node", "reviewer")
        private val ledger = CollaborationEvidenceLedger(context)
        val evidence = CollaborationCloudEvidence(ledger, access)

        init {
            try {
                groups.update(id) { it.copy(members = listOf(CollaborationMember("reviewer", "Reviewer", "fixture", "Fixture")),
                    coordinatorId = "reviewer") }
                ledger.bind(AgentTeamDispatchIds.sourceMessageId(id), access)
                val store = CollaborationGoalContractStore(context)
                val descriptor = store.publish(access, goal, "[]")
                assertEquals(descriptor.toString(), "ok", descriptor.optString("status"))
                assertEquals("ok", store.bind(access, descriptor.getString("snapshot_id")).getString("status"))
            } catch (failure: Throwable) {
                groups.remove(id)
                throw failure
            }
        }

        fun contact(server: MockWebServer) = JSONObject().put("id", id).put("cloud_provider", "custom")
            .put("cloud_model", "fixture-model").put("cloud_api_key", "fixture-only-key")
            .put("cloud_endpoint", server.url("/v1/chat/completions").toString())

        fun turns() = listOf(ChatMessage(0L, "Read the original fixture and return the requested JSON.", true,
            Contact(id, "Local framing fixture", "")))

        override fun close() { groups.remove(id) }
    }

    private fun frame(delta: JSONObject, finish: String? = null, usage: Boolean = false): String {
        val choice = JSONObject().put("index", 0).put("delta", delta)
        finish?.let { choice.put("finish_reason", it) }
        val payload = JSONObject().put("choices", JSONArray().put(choice))
        if (usage) payload.put("usage", JSONObject().put("prompt_tokens", 1).put("completion_tokens", 1).put("total_tokens", 2))
        return "data: $payload\n\n"
    }

    private fun textFrame(text: String, finish: String? = null, usage: Boolean = false) =
        frame(JSONObject().put("content", text), finish, usage)

    private fun response(vararg frames: String) = MockResponse().setHeader("Content-Type", "text/event-stream")
        .setBody(frames.joinToString("") + "data: [DONE]\n\n")

    private fun toolFrame(): String {
        val tool = JSONObject().put("index", 0).put("id", "read-original").put("type", "function")
            .put("function", JSONObject().put("name", CollaborationCloudRecall.NAME)
                .put("arguments", JSONObject().put("mode", "goal_contract").put("cursor", "").toString()))
        return frame(JSONObject().put("tool_calls", JSONArray().put(tool)), "tool_calls")
    }

    private fun assertFinal(events: List<ModelStreamEvent>) {
        assertFalse(events.toString(), events.any { it is ModelStreamEvent.Failed })
        val deltas = events.filterIsInstance<ModelStreamEvent.TextDelta>()
        assertEquals(1, deltas.size)
        assertEquals(finalJson, deltas.single().text)
        assertNotNull(CollaborationResearchArtifact.decode(deltas.single().text))
        assertEquals(1, events.count { it is ModelStreamEvent.Completed })
        assertTrue(events.last() is ModelStreamEvent.Completed)
        assertFalse(events.any { it is ModelStreamEvent.CitationPreview })
    }

    @Test fun managedToolPrefaceNeverPrecedesTheFinalArtifact(): Unit = runBlocking {
        Fixture().use { fixture ->
            MockWebServer().use { server ->
                server.start()
                server.enqueue(response(textFrame(preface), toolFrame()))
                val middle = finalJson.length / 2
                server.enqueue(response(textFrame(finalJson.substring(0, middle)), textFrame(finalJson.substring(middle), "stop")))
                val events = mutableListOf<ModelStreamEvent>()
                val tools = mutableListOf<CloudToolEvent>()
                withTimeout(20_000) {
                    CloudConversationStreamEngine.streamConversation(context, fixture.contact(server), fixture.turns(), fixture.id,
                        citationPreviewEnabled = true, collaborationEvidence = fixture.evidence, onToolEvent = {
                            tools += it
                            if (it.tool == CollaborationCloudRecall.NAME && it.stage == "running")
                                assertTrue("Tool preface leaked before execution", events.none { event -> event is ModelStreamEvent.TextDelta })
                        }).collect { events += it }
                }
                assertFinal(events)
                assertTrue(events.any { it is ModelStreamEvent.ToolCallDelta })
                assertTrue(tools.any { it.tool == CollaborationCloudRecall.NAME && it.stage == "completed" })
                assertEquals(2, server.requestCount)
                val first = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
                val second = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
                assertTrue(first.getJSONArray("tools").toString().contains(CollaborationCloudRecall.NAME))
                val messages = second.getJSONArray("messages")
                val toolOutputs = (0 until messages.length()).map { messages.getJSONObject(it) }
                    .filter { it.optString("role") == "tool" }.joinToString("\n") { it.optString("content") }
                assertTrue("The actual scoped original was not delivered to the second round", toolOutputs.contains(fixture.goal))
                assertTrue(toolOutputs.contains("galaxyssi_evidence_receipt"))
            }
        }
    }

    @Test fun managedNoToolFinalIsDeliveredOnceWithToolsEnabledOrDisabled(): Unit = runBlocking {
        for (allowTools in listOf(true, false)) {
            Fixture().use { fixture ->
                MockWebServer().use { server ->
                    server.start()
                    server.enqueue(response(textFrame(finalJson.substring(0, 10)), textFrame(finalJson.substring(10), "stop")))
                    val events = mutableListOf<ModelStreamEvent>()
                    withTimeout(20_000) {
                        CloudConversationStreamEngine.streamConversation(context, fixture.contact(server), fixture.turns(), fixture.id,
                            allowExternalTools = allowTools, collaborationEvidence = fixture.evidence).collect { events += it }
                    }
                    assertFinal(events)
                    assertEquals(1, server.requestCount)
                    val request = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
                    assertEquals(allowTools, request.has("tools"))
                }
            }
        }
    }

    @Test fun ordinaryChatStreamsButManagedTextStaysBufferedUntilCancellation(): Unit = runBlocking {
        for (managed in listOf(false, true)) {
            Fixture().use { fixture ->
                MockWebServer().use { server ->
                    server.start()
                    val prefix = textFrame(preface, usage = true)
                    // A queued throttled response also throttles request-body reads. Install it
                    // only after dispatch so the prefix arrives before the cancellation deadline.
                    server.dispatcher = object : Dispatcher() {
                        override fun dispatch(request: RecordedRequest) =
                            response(prefix, textFrame(finalJson, "stop"))
                                .throttleBody(prefix.toByteArray(Charsets.UTF_8).size.toLong(), 3, TimeUnit.SECONDS)
                    }
                    val events = CopyOnWriteArrayList<ModelStreamEvent>()
                    val prefixConsumed = CompletableDeferred<Unit>()
                    val worker = launch {
                        CloudConversationStreamEngine.streamConversation(context, fixture.contact(server), fixture.turns(), fixture.id,
                            collaborationEvidence = fixture.evidence.takeIf { managed }).collect {
                            events += it
                            if (it is ModelStreamEvent.Usage) prefixConsumed.complete(Unit)
                        }
                    }
                    try {
                        // Usage follows the text in this frame; the final frame is still held by the server.
                        withTimeout(5_000) { prefixConsumed.await() }
                        assertEquals(if (managed) "" else preface,
                            events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
                        assertFalse(events.any { it is ModelStreamEvent.Completed })
                    } finally {
                        withTimeout(5_000) { worker.cancelAndJoin() }
                    }
                    assertTrue(worker.isCancelled)
                    assertFalse(events.any { it is ModelStreamEvent.Completed })
                    if (managed) assertTrue(events.none { it is ModelStreamEvent.TextDelta })
                    assertEquals(1, server.requestCount)
                }
            }
        }
    }

    @Test fun interruptedManagedRoundPublishesNeitherPrefaceNorPartialArtifact(): Unit = runBlocking {
        Fixture().use { fixture ->
            MockWebServer().use { server ->
                server.start()
                server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream")
                    .setBody(textFrame(preface)))
                val events = mutableListOf<ModelStreamEvent>()
                withTimeout(20_000) {
                    CloudConversationStreamEngine.streamConversation(context, fixture.contact(server), fixture.turns(), fixture.id,
                        collaborationEvidence = fixture.evidence).collect { events += it }
                }
                assertTrue(events.none { it is ModelStreamEvent.TextDelta || it is ModelStreamEvent.Completed })
                val failure = events.filterIsInstance<ModelStreamEvent.Failed>().single()
                assertEquals("STREAM_INTERRUPTED", failure.error.code)
                assertFalse(failure.error.partialResponse)
                assertEquals(1, server.requestCount)
            }
        }
    }
}
