package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Loopback model responses exercise the real stream, encrypted journal and publication validator. */
@RunWith(AndroidJUnit4::class)
class CollaborationPublicationRecoveryDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val valid = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Fixture publication, not verified science").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray().put(JSONObject().put("id", "fixture").put("kind", "proposal")
            .put("title", "Fixture proposal").put("body", JSONObject().put("content", "Complete fixture content")))).toString()
    private val invalid = valid.replace("\"kind\":\"proposal\"", "\"kind\":\"unknown\"")

    private inner class Fixture(val id: String = "publication-${UUID.randomUUID()}") : java.io.Closeable {
        val access = CollaborationWorkspaceAccess(id, "run", "turn", 1, "node", "reviewer")
        val workspace = CollaborationResearchWorkspace(context)
        val ledger = CollaborationEvidenceLedger(context)
        val evidence = CollaborationCloudEvidence(ledger, access)
        init {
            CollaborationGroupStore(context).update(id) { it.copy(members = listOf(
                CollaborationMember("reviewer", "Reviewer", "fixture", "Fixture")), coordinatorId = "reviewer") }
            ledger.bind(AgentTeamDispatchIds.sourceMessageId(id), access)
            workspace.enrollPublication(access, CollaborationResearchStage.VERIFY)
        }
        fun contact(server: MockWebServer) = JSONObject().put("id", id).put("cloud_provider", "custom")
            .put("cloud_model", "fixture").put("cloud_api_key", "fixture-only-key")
            .put("cloud_endpoint", server.url("/v1/chat/completions").toString())
        suspend fun stream(server: MockWebServer, onTool: (CloudToolEvent) -> Unit = {}): List<ModelStreamEvent> {
            val events = mutableListOf<ModelStreamEvent>()
            withTimeout(90_000) {
                CloudConversationStreamEngine.streamConversation(context, contact(server), listOf(
                    ChatMessage(0L, "Publish the dedicated fixture", true, Contact(id, "Fixture", ""))),
                    UUID.randomUUID().toString(), collaborationEvidence = evidence, onToolEvent = onTool).collect { events += it }
            }
            return events
        }
        override fun close() { CollaborationGroupStore(context).remove(id) }
    }
    private fun reply(text: String) = response(JSONObject().put("content", text), "stop")
    private fun response(delta: JSONObject, finish: String) = MockResponse().setHeader("Content-Type", "text/event-stream")
        .setBody("data: " + JSONObject().put("choices", JSONArray().put(JSONObject().put("index", 0)
            .put("delta", delta).put("finish_reason", finish))) + "\n\ndata: [DONE]\n\n")
    private fun assertFinal(events: List<ModelStreamEvent>) {
        assertFalse(events.toString(), events.any { it is ModelStreamEvent.Failed })
        assertEquals(listOf(valid), events.filterIsInstance<ModelStreamEvent.TextDelta>().map { it.text })
        assertEquals(1, events.count { it is ModelStreamEvent.Completed })
    }

    @Test fun rejectedDraftIsNotDeliveredAndIsCorrectedWithoutRepeatingTools(): Unit = runBlocking {
        Fixture().use { fixture -> MockWebServer().use { server ->
            server.start(); server.enqueue(reply(invalid)); server.enqueue(reply(" \n$valid\n"))
            val progress = mutableListOf<CloudToolEvent>()
            assertFinal(fixture.stream(server) { progress += it })
            assertEquals(2, server.requestCount)
            server.takeRequest(1, TimeUnit.SECONDS)
            val correction = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
            assertTrue(correction.getJSONArray("messages").toString().contains("Unknown workspace object kind"))
            val tools = correction.getJSONArray("tools")
            assertEquals(1, tools.length())
            assertEquals(CollaborationCloudRecall.NAME, tools.getJSONObject(0).getJSONObject("function").getString("name"))
            assertTrue(progress.any { it.tool == "collaboration_publication" && it.stage == "repairing" })
            assertTrue(progress.none { it.stage == "running" })
            assertEquals(2, fixture.workspace.publicationCheckpoint(fixture.access)!!.getLong("sequence"))
            assertEquals(1, fixture.workspace.browse(fixture.access).revisions.size)
            assertEquals("recorded", fixture.workspace.publish(fixture.access, valid).getString("status"))
            assertFinal(fixture.stream(server))
            assertEquals("A durable publication must not call the model again", 2, server.requestCount)
        } }
    }

    @Test fun cancellationPreservesDraftAndResumeStartsWithReadOnlyRepair(): Unit = runBlocking {
        Fixture().use { fixture -> MockWebServer().use { server ->
            server.start(); server.enqueue(reply(invalid))
            try {
                fixture.stream(server) { if (it.tool == "collaboration_publication") throw CancellationException("Fixture pause") }
                fail("Expected cancellation")
            } catch (_: CancellationException) { }
            assertEquals("rejected", fixture.workspace.publicationCheckpoint(fixture.access)!!.getJSONObject("receipt").getString("status"))
            server.enqueue(reply(valid))
            assertFinal(fixture.stream(server))
            assertEquals(2, server.requestCount)
            server.takeRequest(1, TimeUnit.SECONDS)
            val resumed = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
            assertTrue(resumed.getJSONArray("messages").toString().contains("Unknown workspace object kind"))
            assertEquals(1, resumed.getJSONArray("tools").length())
        } }
    }

    @Test fun evidenceRoundStillUsesCitationChecksBeforePublication(): Unit = runBlocking {
        Fixture().use { fixture -> MockWebServer().use { server ->
            server.start()
            val recall = JSONObject().put("index", 0).put("id", "read-workspace").put("type", "function")
                .put("function", JSONObject().put("name", CollaborationCloudRecall.NAME)
                    .put("arguments", JSONObject().put("mode", "workspace").toString()))
            server.enqueue(response(JSONObject().put("tool_calls", JSONArray().put(recall)), "tool_calls"))
            server.enqueue(reply(invalid))
            val secondRecall = JSONObject(recall.toString()).put("id", "read-workspace-again")
            server.enqueue(response(JSONObject().put("tool_calls", JSONArray().put(secondRecall)), "tool_calls"))
            server.enqueue(reply(invalid)); server.enqueue(reply(valid))
            val tools = mutableListOf<CloudToolEvent>()
            assertFinal(fixture.stream(server) { tools += it })
            assertEquals(5, server.requestCount)
            repeat(4) { server.takeRequest(1, TimeUnit.SECONDS) }
            val lastRequest = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
            val messages = lastRequest.getJSONArray("messages")
            val observedCalls = mutableListOf<String>()
            val observedResults = mutableListOf<String>()
            repeat(messages.length()) { index ->
                val message = messages.getJSONObject(index)
                message.optJSONArray("tool_calls")?.let { batch ->
                    repeat(batch.length()) { observedCalls += batch.getJSONObject(it).getString("id") }
                }
                if (message.optString("role") == "tool") observedResults += message.getString("tool_call_id")
            }
            assertEquals(listOf("read-workspace", "read-workspace-again"), observedCalls)
            assertEquals(observedCalls, observedResults)
            assertTrue(tools.any { it.tool == "research" && it.stage == "verifying" })
            assertTrue(tools.any { it.tool == "collaboration_publication" && it.stage == "repairing" })
            assertEquals(1, tools.count { it.tool == CollaborationCloudRecall.NAME && it.stage == "completed" })
            assertEquals(1, fixture.ledger.browse(fixture.access).first.size)
        } }
    }

    @Test fun unadvertisedToolCannotExecuteDuringRepair(): Unit = runBlocking {
        Fixture().use { fixture -> MockWebServer().use { server ->
            server.start(); server.enqueue(reply(invalid))
            val forbidden = JSONObject().put("index", 0).put("id", "forbidden-search").put("type", "function")
                .put("function", JSONObject().put("name", "web_fetch").put("arguments",
                    JSONObject().put("url", server.url("/must-not-be-fetched").toString()).toString()))
            server.enqueue(response(JSONObject().put("tool_calls", JSONArray().put(forbidden)), "tool_calls"))
            server.enqueue(reply(valid))
            val tools = mutableListOf<CloudToolEvent>()
            assertFinal(fixture.stream(server) { tools += it })
            assertEquals(3, server.requestCount)
            repeat(3) { assertEquals("/v1/chat/completions", requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).path) }
            assertTrue(tools.none { it.tool == "web_fetch" })
            assertTrue(fixture.ledger.browse(fixture.access).first.isEmpty())
        } }
    }

    @Test fun separateProcessResumesRejectedPublication(): Unit = runBlocking {
        val phase = InstrumentationRegistry.getArguments().getString("publicationPhase").orEmpty()
        assumeTrue(phase in setOf("seed", "recover"))
        val fixture = Fixture("publication-process-fixture")
        val prefs = context.getSharedPreferences("publication-process-fixture", android.content.Context.MODE_PRIVATE)
        if (phase == "seed") {
            assertNull(fixture.workspace.publicationCheckpoint(fixture.access))
            assertEquals("rejected", fixture.workspace.submitPublication(fixture.access, invalid).getString("status"))
            prefs.edit().putInt("pid", android.os.Process.myPid()).commit()
        } else try {
            assertNotEquals(prefs.getInt("pid", -1), android.os.Process.myPid())
            MockWebServer().use { server ->
                server.start(); server.enqueue(reply(valid))
                assertFinal(fixture.stream(server))
                val request = JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8())
                assertEquals(1, request.getJSONArray("tools").length())
                assertTrue(request.getJSONArray("messages").toString().contains("Unknown workspace object kind"))
                assertEquals(2, fixture.workspace.publicationCheckpoint(fixture.access)!!.getLong("sequence"))
                assertFinal(fixture.stream(server))
                assertEquals(1, server.requestCount)
            }
        } finally { fixture.close(); prefs.edit().clear().commit() }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("publication_phase", phase); putInt("process_id", android.os.Process.myPid())
        })
    }

    @Test fun cleanupInterruptedLocalFixture() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("cleanupInterruptedPublication") == "true")
        val groups = CollaborationGroupStore(context)
        val ids = AgentEncryptedDatabase(context, "galaxyssi_collaboration_groups_v1").keys("publication-")
            .filter { it.matches(Regex("publication-[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")) }
            .filter { id ->
                val group = groups.load(id) ?: return@filter false
                val access = CollaborationWorkspaceAccess(id, "run", "turn", 1, "node", "reviewer")
                val expected = CollaborationMember("reviewer", "Reviewer", "fixture", "Fixture")
                if (group.members != listOf(expected) || group.coordinatorId != "reviewer" || group.conversationId != id)
                    return@filter false
                val workspace = CollaborationResearchWorkspace(context)
                val checkpoint = workspace.publicationCheckpoint(access) ?: return@filter false
                CollaborationEvidenceLedger(context).binding(AgentTeamDispatchIds.sourceMessageId(id), id, "turn") == access &&
                    checkpoint.getString("raw") == invalid && checkpoint.getJSONObject("receipt").getString("status") == "rejected" &&
                    workspace.browse(access).revisions.isEmpty()
            }
        require(ids.size == 1) { "Expected exactly one interrupted local fixture; no records were removed" }
        val id = ids.single()
        groups.remove(id)
        CollaborationEvidenceLedger.remove(context, id)
        assertNull(groups.load(id))
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("removed_local_publication_fixture", id)
        })
    }
}
