package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.os.Looper
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.galaxyssi.chat.voice.agent.InMemoryVoiceAgentRunRepository
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunRepository
import com.galaxyssi.chat.voice.agent.VoiceAgentRunSnapshot
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(AndroidJUnit4::class)
class AgentProcessRowDeviceTest {
    @Test fun finalReplyIsDeliveredBeforeBackgroundVoiceHistoryLookup() {
        assumeTrue(VoiceFeatureFlags.isAgentVoiceRunBridgeEnabled(
            InstrumentationRegistry.getInstrumentation().targetContext))
        val delivered = AtomicBoolean(false)
        val offMain = AtomicBoolean(false)
        val deliveredFirst = AtomicBoolean(false)
        val searched = CountDownLatch(1)
        val owner = "reply-test-${UUID.randomUUID()}"
        val source = System.currentTimeMillis()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var original: VoiceAgentRunBridge? = null
            try {
                scenario.onActivity { activity ->
                    original = activity.voiceAgentRunBridge
                    activity.voiceAgentRunBridge = VoiceAgentRunBridge(object : VoiceAgentRunRepository by InMemoryVoiceAgentRunRepository() {
                        override fun findByTaskId(taskId: String): VoiceAgentRunSnapshot? {
                            offMain.set(Looper.myLooper() != Looper.getMainLooper())
                            deliveredFirst.set(delivered.get())
                            searched.countDown()
                            return null
                        }
                    })
                    AgentManagedConnectorResponseRegistry.register(source, owner, owner, owner, owner, owner) {
                        delivered.set(true)
                        true
                    }
                    assertTrue(activity.publishAgentConnectorResponse(JSONObject()
                        .put("type", "text").put("source_message_id", source)
                        .put("contact_id", owner).put("conversation_id", owner)
                        .put("turn_id", owner).put("task_id", owner),
                        ChatMessage(source, "Test reply", false, Contact(owner, "Test", ""))))
                }
                assertTrue(searched.await(5L, TimeUnit.SECONDS))
                assertTrue("Voice history lookup blocked the UI thread", offMain.get())
                assertTrue("Voice history lookup delayed final response delivery", deliveredFirst.get())
            } finally {
                AgentManagedConnectorResponseRegistry.unregisterOwner(owner)
                scenario.onActivity { activity ->
                    original?.let { activity.voiceAgentRunBridge = it }
                    activity.completedConnectorTaskIds.remove(owner)
                }
            }
        }
    }

    @Test fun bindingAndRebindingProgressRowsNeverReadsVoiceHistory() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val original = activity.voiceAgentRunBridge
                val repository = object : VoiceAgentRunRepository by InMemoryVoiceAgentRunRepository() {
                    override fun findByTaskId(taskId: String): VoiceAgentRunSnapshot? =
                        error("Transcript binding performed a voice history lookup")
                }
                activity.voiceAgentRunBridge = VoiceAgentRunBridge(repository)
                val task = "process-row-${UUID.randomUUID()}"
                try {
                    val entry = AgentTranscriptEntry("entry", AgentTranscriptRole.PROCESS, "Working",
                        System.currentTimeMillis(), conversationId = "conversation", turnId = "turn", taskId = task)
                    activity.rememberAgentExecutionPresentation(task, presentation())
                    repeat(20) { assertNotNull(activity.agentProcessTranscriptRow(entry)) }
                } finally {
                    activity.agentExecutionPresentations.remove(task)
                    activity.voiceAgentRunBridge = original
                }
            }
        }
    }

    @Test fun voiceCancellationUsesExactPresentationAndSurvivesStatusRefresh() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val task = "process-row-${UUID.randomUUID()}"
                val reference = AgentVoiceRunReference("run", "conversation", "turn", task)
                val entry = AgentTranscriptEntry("entry", AgentTranscriptRole.PROCESS, "Working",
                    System.currentTimeMillis(), conversationId = "conversation", turnId = "turn", taskId = task)
                val cancel = activity.getString(R.string.agent_execution_cancel_description)
                try {
                    activity.rememberAgentExecutionPresentation(task, presentation().copy(voiceRun = reference))
                    assertTrue(hasDescription(activity.agentProcessTranscriptRow(entry), cancel))
                    activity.rememberAgentExecutionPresentation(task, presentation())
                    assertEquals(reference, activity.agentExecutionPresentations[task]?.voiceRun)
                    assertTrue(hasDescription(activity.agentProcessTranscriptRow(entry), cancel))
                    assertFalse(hasDescription(activity.agentProcessTranscriptRow(entry.copy(turnId = "other")), cancel))
                    assertFalse(hasDescription(activity.agentProcessTranscriptRow(entry.copy(conversationId = "other")), cancel))
                    activity.rememberAgentExecutionPresentation(task, presentation().copy(
                        phase = AgentPhase.COMPLETED, cancellable = false, completedAtMillis = System.currentTimeMillis()))
                    assertFalse(hasDescription(activity.agentProcessTranscriptRow(entry), cancel))
                } finally {
                    activity.agentExecutionPresentations.remove(task)
                }
            }
        }
    }

    private fun presentation() = AgentExecutionPresentation(
        executorId = "test", executorLabel = "Test", locationKind = AgentExecutionLocationKind.DESKTOP,
        locationLabelHint = "Test", currentStep = "Working", phase = AgentPhase.EXECUTING,
        cancellable = true, startedAtMillis = System.currentTimeMillis())

    private fun hasDescription(view: View, description: String): Boolean =
        view.contentDescription == description || view is ViewGroup &&
            (0 until view.childCount).any { hasDescription(view.getChildAt(it), description) }
}
