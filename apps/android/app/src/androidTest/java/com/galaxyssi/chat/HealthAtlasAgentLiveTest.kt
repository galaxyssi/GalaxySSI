package com.galaxyssi.chat

import android.app.KeyguardManager
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in public teaching request through the real one-use Atlas handoff and Agent Loop. */
class HealthAtlasAgentLiveTest {
    @Test fun realModelReceivesTeachingInputsAndContinuesInTheSameConversation() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_atlas_agent") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val atlas = HealthBodyAtlas.load(context)
        val prompt = HealthAtlasAgentContext.prompt(context, atlas, atlas["heart"], HealthAtlasSimulation(100, 70, .5f))
        val intent = HealthAtlasAgentHandoff.prepare(context, "Atlas public teaching acceptance", prompt)
        val conversation = requireNotNull(intent.getStringExtra("galaxyssi_agent_conversation_id"))
        val transcript = AgentTranscriptStore(context)
        val report = JSONObject().put("conversation", conversation).put("prompt", prompt)
        val rounds = JSONArray(); report.put("rounds", rounds)
        val file = File(context.getExternalFilesDir(null), "body-atlas-agent-live.json")
        var completed = false
        try {
            ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                fun awaitReply(seen: Set<String>): AgentTranscriptEntry {
                    val start = SystemClock.elapsedRealtime()
                    var reply: AgentTranscriptEntry? = null
                    while (reply == null && SystemClock.elapsedRealtime() - start < 240_000) {
                        reply = transcript.page(conversation, pageSize = 100).entries.lastOrNull {
                            it.id !in seen && it.role == AgentTranscriptRole.ASSISTANT && !AgentTranscriptRenderPolicy.isLiveStream(it)
                        }
                        if (reply == null) SystemClock.sleep(500)
                    }
                    val record = JSONObject().put("elapsed_ms", SystemClock.elapsedRealtime() - start)
                        .put("reply", reply?.text).put("turn", reply?.turnId)
                    rounds.put(record); file.writeText(report.toString(2))
                    val answer = requireNotNull(reply) { "No public Atlas response within four minutes" }
                    val doneBy = SystemClock.elapsedRealtime() + 15_000
                    var phase = SharedPreferencesAgentSessionStore(context, "task:${answer.turnId}").load()?.phase
                    while (phase != AgentPhase.COMPLETED && SystemClock.elapsedRealtime() < doneBy) {
                        SystemClock.sleep(100)
                        phase = SharedPreferencesAgentSessionStore(context, "task:${answer.turnId}").load()?.phase
                    }
                    record.put("phase", phase?.name); file.writeText(report.toString(2))
                    assertEquals(AgentPhase.COMPLETED, phase)
                    assertTrue(answer.text.length > 30)
                    return answer
                }
                val first = awaitReply(emptySet())
                val entries = transcript.page(conversation, pageSize = 100).entries
                assertEquals(1, entries.count { it.role == AgentTranscriptRole.USER && it.text == prompt })
                assertTrue(first.text.contains("7"))
                scenario.onActivity { activity ->
                    assertEquals(conversation, activity.agentTranscriptStore.activeConversation().id)
                    activity.agentGoalInput.setText("Using the same teaching inputs as above, change only stroke volume to 80 mL. " +
                        "State the retained heart rate and the new cardiac output in L/min. Do not use personal health records.")
                    activity.agentSubmitButton.performClick()
                }
                val second = awaitReply(entries.map { it.id }.toSet())
                assertTrue("Follow-up lost retained heart rate", second.text.contains("100"))
                assertTrue("Follow-up did not calculate the changed output", second.text.contains("8"))
                scenario.onActivity { assertEquals(conversation, it.agentTranscriptStore.activeConversation().id) }
                completed = true
            }
        } catch (failure: Throwable) {
            report.put("failure", failure.message); throw failure
        } finally {
            report.put("completed", completed); file.writeText(report.toString(2))
            if (!completed) AgentTaskRuntime.supervisor(context).activeWorkspaces().filter { it.conversationId == conversation }.forEach {
                AgentCloudDispatchRegistry.cancel(SharedPreferencesAgentSessionStore(context, "task:${it.workspaceId}").load()?.lastActionResult)
                AgentTaskRuntime.supervisor(context).cancelWorkspace(it.workspaceId, "Public Atlas acceptance deadline or assertion failure")
            }
        }
    }
}
