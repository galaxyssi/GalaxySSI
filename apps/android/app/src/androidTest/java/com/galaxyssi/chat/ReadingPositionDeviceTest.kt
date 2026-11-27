package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class ReadingPositionDeviceTest {
    @get:org.junit.Rule val noPermissions = ViewportNoPermissionPromptRule()
    @Test fun delayedMediaGrowthAboveVisibleParagraphDoesNotDisplaceItsText() {
        ActivityScenario.launch(MainActivity::class.java).use { screen ->
            lateinit var list: androidx.recyclerview.widget.RecyclerView
            lateinit var media: View
            lateinit var text: com.galaxyssi.chat.ui.ParagraphSelectingTextView
            var holding = false
            screen.onActivity { a ->
                list = androidx.recyclerview.widget.RecyclerView(a).apply {
                    layoutManager = androidx.recyclerview.widget.LinearLayoutManager(a)
                    itemAnimator = null
                    adapter = object : androidx.recyclerview.widget.RecyclerView.Adapter<androidx.recyclerview.widget.RecyclerView.ViewHolder>() {
                        override fun getItemCount() = 1
                        override fun onBindViewHolder(holder: androidx.recyclerview.widget.RecyclerView.ViewHolder, position: Int) = Unit
                        override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): androidx.recyclerview.widget.RecyclerView.ViewHolder {
                            val row = android.widget.LinearLayout(a).apply {
                                orientation = android.widget.LinearLayout.VERTICAL
                                media = View(a); addView(media, -1, 360)
                                text = com.galaxyssi.chat.ui.ParagraphSelectingTextView(a).apply { this.text = "Reading marker" }
                                addView(text, -1, 240)
                                addView(View(a), -1, 2400)
                            }
                            return object : androidx.recyclerview.widget.RecyclerView.ViewHolder(row) {}
                        }
                    }
                }
                a.addContentView(list, android.view.ViewGroup.LayoutParams(-1, 640))
                ReadingParagraphAnchor(list) { holding }.install()
            }
            val inst = InstrumentationRegistry.getInstrumentation()
            inst.waitForIdleSync()
            fun y() = IntArray(2).also { text.getLocationInWindow(it) }[1]
            var before = 0
            screen.onActivity { list.scrollBy(0, 300); holding = true; list.invalidate() }
            inst.waitForIdleSync()
            screen.onActivity {
                assertTrue(text.isShown); before = y()
                media.layoutParams = media.layoutParams.apply { height += 110 }
            }
            inst.waitForIdleSync()
            screen.onActivity { assertEquals(before, y()) }
        }
    }

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
            val launch = android.content.Intent(ctx, MainActivity::class.java)
                .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", chat)
            ActivityScenario.launch<MainActivity>(launch).use { screen ->
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
