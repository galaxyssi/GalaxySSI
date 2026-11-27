package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.json.JSONArray
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class ConversationGoalDeviceTest {
    private val ctx get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (ConversationGoalStore, ConversationGoal) -> Unit) {
        val store = ConversationGoalStore(ctx)
        val g = ConversationGoal(UUID.randomUUID().toString(), "撰写两段示例", GoalRoute("local-llm", "fixture", ""))
        try { store.put(g); block(store, g) } finally { store.remove(g.chat) }
    }
    private val first = """{"state":"continue","result":"第一段草稿","next":"完成第二段"}"""
    private val last = """{"state":"done","result":"两段完整成稿","next":""}"""
    private val verified = """{"state":"verified","result":"","next":""}"""

    @Test fun cloudWireContinuesFromCheckpointWithoutToolsOrExternalNetwork() = fixture { store, g ->
        MockWebServer().use { server ->
            server.start()
            for (reply in listOf(first, last, verified)) server.enqueue(MockResponse().setHeader("Content-Type", "application/json")
                .setBody(JSONObject().put("choices", JSONArray().put(JSONObject().put("message",
                    JSONObject().put("role", "assistant").put("content", reply)))).toString()))
            val contact = JSONObject().put("id", "synthetic-goal").put("name", "Synthetic")
                .put("cloud_provider", "custom").put("cloud_api_style", "openai").put("cloud_model", "test-only")
                .put("cloud_api_key", "synthetic").put("cloud_endpoint", server.url("/fixture").toString())
            store.put(g.copy(route = GoalRoute("synthetic-goal", "test-only", ConversationGoalRunner.fingerprint(contact))))
            ConversationGoalWorker.execute(ctx, g.chat, g.id, 1, store, { false }, { true }, { claim ->
                runBlocking { ConversationGoalRunner.step(ctx, claim, AgentNativeToolCancellationToken.NONE) { _, _, _ -> contact } }
            }) {}
            assertEquals(GoalPhase.DONE, store.get(g.chat)!!.phase)
            assertEquals(3, server.requestCount)
            val requests = List(3) { JSONObject(server.takeRequest(3, TimeUnit.SECONDS)!!.body.readUtf8()) }
            assertTrue(requests.none { it.has("tools") || it.has("tool_choice") })
            assertFalse(requests.first().toString().contains("第一段草稿"))
            assertTrue(requests.last().toString().contains("第一段草稿"))
        }
    }

    @Test fun runsMultipleRoundsWithSavedWorkAndIdempotentDeliveryKeys() = fixture { store, g ->
        val delivered = mutableMapOf<Int, String>()
        var calls = 0
        repeat(2) {
            ConversationGoalWorker.execute(ctx, g.chat, g.id, 1, store, { false }, { true }, { claim ->
                calls++
                if (claim.review) verified else if (calls == 1) first else {
                    assertEquals(listOf("第一段草稿"), claim.checkpoints); assertEquals("完成第二段", claim.next)
                    last
                }
            }) { delivered[it.revision] = it.checkpoints.last() }
        }
        assertEquals(3, calls)
        assertEquals(3, delivered.size)
        assertEquals(GoalPhase.DONE, ConversationGoalStore(ctx).get(g.chat)!!.phase)
    }

    @Test fun pauseFencesLateAnswerAndResumeUsesExistingCheckpoint() = fixture { store, g ->
        ConversationGoalWorker.execute(ctx, g.chat, g.id, 1, store, { false }, { true }, { claim ->
            if (claim.rounds == 1) first else {
                store.put(claim.copy(phase = GoalPhase.PAUSED, generation = 2, inFlight = false))
                last
            }
        }) {}
        val paused = store.get(g.chat)!!
        assertEquals(GoalPhase.PAUSED, paused.phase); assertEquals(listOf("第一段草稿"), paused.checkpoints)
        val resumed = paused.copy(phase = GoalPhase.RUNNING, generation = 3, note = "补充")
        store.put(resumed)
        ConversationGoalWorker.execute(ctx, g.chat, g.id, 3, store, { false }, { true }, {
            assertEquals("补充", it.note)
            if (it.review) verified else { assertEquals(paused.checkpoints, it.checkpoints); last }
        }) {}
        assertEquals(GoalPhase.DONE, store.get(g.chat)!!.phase)
    }

    @Test fun interruptedRequestDoesNotReplayAndStaleWorkCannotTouchReplacement() = fixture { store, g ->
        store.put(g.copy(inFlight = true, rounds = 1))
        ConversationGoalWorker.execute(ctx, g.chat, g.id, 1, store, { false }, { true }, { error("unexpected inference") }) {}
        assertEquals(GoalPhase.BLOCKED, store.get(g.chat)!!.phase)
        assertEquals(ctx.getString(R.string.goal_interrupted), store.get(g.chat)!!.issue)
        val replacement = g.copy(id = UUID.randomUUID().toString())
        store.put(replacement)
        ConversationGoalWorker.execute(ctx, g.chat, g.id, 1, store, { false }, { true }, { error("unexpected") }) {}
        assertEquals(replacement, store.get(g.chat))
    }

    @Test fun realWorkManagerRefusesOrphanInsteadOfReadingAnotherConversation() = fixture { store, g ->
        val wm = WorkManager.getInstance(ctx)
        ConversationGoalRunner.schedule(ctx, g)
        val until = SystemClock.elapsedRealtime() + 60_000
        while (store.get(g.chat)?.phase == GoalPhase.RUNNING && SystemClock.elapsedRealtime() < until)
            SystemClock.sleep(250)
        assertEquals(GoalPhase.BLOCKED, store.get(g.chat)!!.phase)
        assertEquals(0, store.get(g.chat)!!.rounds)
        assertTrue(wm.getWorkInfosForUniqueWork(ConversationGoalRunner.name(g)).get(5, TimeUnit.SECONDS).isNotEmpty())
    }
}
