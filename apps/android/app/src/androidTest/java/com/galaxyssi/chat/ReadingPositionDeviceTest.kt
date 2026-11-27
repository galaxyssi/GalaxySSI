package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class ReadingPositionDeviceTest {
    @Test fun firstStreamBodyLeavesTheReaderInPlaceAndTheArrowFollowsToLatest() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val transcripts = AgentTranscriptStore(ctx)
        val old = transcripts.activeConversation().id
        val chat = transcripts.createConversation("Viewport fixture").id
        val turn = UUID.randomUUID().toString()
        try {
            repeat(24) { i ->
                transcripts.append(AgentTranscriptRole.USER, "Fixture $i\nReading position\nOnly synthetic text.",
                    conversationId = chat, turnId = if (i == 23) turn else UUID.randomUUID().toString())
            }
            ActivityScenario.launch(MainActivity::class.java).use { screen ->
                fun await(hint: String, test: (MainActivity) -> Boolean) {
                    val end = SystemClock.elapsedRealtime() + 20_000
                    do {
                        var ok = false; screen.onActivity { ok = test(it) }
                        if (ok) return
                        SystemClock.sleep(60)
                    } while (SystemClock.elapsedRealtime() < end)
                    fail(hint)
                }
                screen.onActivity { it.showAgentHomeFromChat() }
                await("history must be laid out") { !it.initialAgentHydrationPending && it.agentRenderedConversationId == chat &&
                    it.agentTranscriptAdapter.itemCount >= 10 && it.agentOutputList.height > 0 }
                screen.onActivity {
                    it.agentTranscriptAutoFollow = false; it.conversationWindow.cancelPendingScroll()
                    it.agentOutputLayout.scrollToPositionWithOffset(2, -11)
                }
                await("set the reading position") { it.captureAgentTranscriptScrollAnchor()?.topOffset == -11 }
                lateinit var anchor: AgentTranscriptScrollAnchor
                lateinit var stream: AgentTranscriptEntry
                screen.onActivity {
                    anchor = it.captureAgentTranscriptScrollAnchor()!!
                    assertEquals(View.GONE, it.findViewById<View>(R.id.agentReadingLatest).visibility)
                    stream = AgentTranscriptEntry("agent-stream-fixture", AgentTranscriptRole.ASSISTANT, "First visible body",
                        System.currentTimeMillis(), conversationId = chat, turnId = turn)
                    it.renderAgentTranscript(it.renderedAgentTranscriptSourceEntries + stream)
                }
                await("only signal, do not scroll") { it.findViewById<View>(R.id.agentReadingLatest).isShown &&
                    it.captureAgentTranscriptScrollAnchor() == anchor && !it.agentOutputList.isLayoutRequested }
                screen.onActivity {
                    it.renderAgentTranscript(it.renderedAgentTranscriptSourceEntries.filterNot { e -> e.id == stream.id } +
                        stream.copy(text = "First visible body and more"))
                }
                await("stream changes must preserve the same offset") { !it.agentOutputList.isLayoutRequested &&
                    it.captureAgentTranscriptScrollAnchor() == anchor }
                screen.onActivity { it.findViewById<View>(R.id.agentReadingLatest).performClick() }
                await("arrow must actually reach the bottom") { !it.findViewById<View>(R.id.agentReadingLatest).isShown &&
                    it.agentTranscriptAutoFollow && !it.agentOutputList.canScrollVertically(1) }
            }
        } finally {
            transcripts.switchConversation(old)
            transcripts.deleteConversation(chat)
        }
    }
}
