package com.galaxyssi.chat

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Base64
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.AgentReplySpeechButton
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
import java.io.ByteArrayOutputStream
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class AgentReplySpeechScrollDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Test fun mediaReplyKeepsItsViewportThroughTapsPlaybackAndCompletion() = checkViewport(media = true, merged = false)
    @Test fun mergedReplyKeepsItsViewportWithoutRebuildingMedia() = checkViewport(media = true, merged = true)
    @Test fun longTextFocusDoesNotScrollBackToTheParagraphViewTop() = checkViewport(media = false, merged = false)

    @Test fun cachedRowsRefreshSpeechOnAttachWithoutRebindingTheirContent() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val entry = reply(false, false)
                val previous = activity.renderedAgentTranscriptSourceEntries
                activity.renderedAgentTranscriptSourceEntries = listOf(entry)
                try {
                    val adapter = AgentTranscriptRecyclerAdapter(activity)
                    adapter.replaceAll(listOf(entry))
                    val holder = adapter.onCreateViewHolder(activity.agentOutputList, 0)
                    adapter.onBindViewHolder(holder, 0)
                    val row = holder.container.getChildAt(0)
                    val paragraph = descendants(row).filterIsInstance<ParagraphSelectingTextView>().first()
                    val button = descendants(row).filterIsInstance<AgentReplySpeechButton>().single()
                    VoiceReplyPlayback.publish(VoiceReplyPlaybackState("cached", VoiceReplySelection(entry.conversationId, entry.id), "playing"))
                    assertFalse(button.isPlayingSpeech)
                    adapter.onViewAttachedToWindow(holder)
                    assertTrue(button.isPlayingSpeech)
                    assertSame(row, holder.container.getChildAt(0))
                    assertSame(paragraph, descendants(row).filterIsInstance<ParagraphSelectingTextView>().first())
                    VoiceReplyPlayback.publish(VoiceReplyPlaybackState())
                    adapter.onViewAttachedToWindow(holder)
                    assertFalse(button.isPlayingSpeech)
                    adapter.onViewRecycled(holder)
                } finally {
                    VoiceReplyPlayback.publish(VoiceReplyPlaybackState())
                    activity.renderedAgentTranscriptSourceEntries = previous
                }
            }
        }
    }

    @Test fun historicalFootersAppearAndDisappearWithoutReplacingTheReply() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val previous = activity.renderedAgentTranscriptSourceEntries
                try {
                    for (merged in listOf(false, true)) {
                        val older = reply(false, merged)
                        val latest = older.copy(id = "latest-${older.id}", turnId = "latest-${older.turnId}")
                        activity.renderedAgentTranscriptSourceEntries = listOf(older, latest)
                        val row = activity.agentTranscriptRow(older)
                        val paragraph = descendants(row).filterIsInstance<ParagraphSelectingTextView>().first()
                        assertTrue(descendants(row).filterIsInstance<AgentReplySpeechButton>().isEmpty())
                        VoiceReplyPlayback.publish(VoiceReplyPlaybackState("historical", VoiceReplySelection(older.conversationId, older.id), "playing"))
                        activity.refreshAgentReplySpeechViews(row)
                        assertTrue(descendants(row).filterIsInstance<AgentReplySpeechButton>().single().isPlayingSpeech)
                        VoiceReplyPlayback.publish(VoiceReplyPlaybackState())
                        activity.refreshAgentReplySpeechViews(row)
                        assertTrue(descendants(row).filterIsInstance<AgentReplySpeechButton>().isEmpty())
                        assertSame(paragraph, descendants(row).filterIsInstance<ParagraphSelectingTextView>().first())
                    }
                } finally {
                    VoiceReplyPlayback.publish(VoiceReplyPlaybackState())
                    activity.renderedAgentTranscriptSourceEntries = previous
                }
            }
        }
    }

    private fun checkViewport(media: Boolean, merged: Boolean) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var activity: MainActivity
            scenario.onActivity { activity = it }
            val hydratedBy = SystemClock.elapsedRealtime() + 30_000
            while (activity.initialAgentHydrationPending && SystemClock.elapsedRealtime() < hydratedBy) SystemClock.sleep(50)
            assertFalse(activity.initialAgentHydrationPending)
            val entry = reply(media, merged)
            val oldList = activity.agentOutputList
            val oldLayout = activity.agentOutputLayout
            val oldAdapter = activity.agentTranscriptAdapter
            val oldEntries = activity.renderedAgentTranscriptSourceEntries
            val oldRenderedConversation = activity.agentRenderedConversationId
            lateinit var list: RecyclerView
            lateinit var adapter: AgentTranscriptRecyclerAdapter
            lateinit var manager: AgentTranscriptLayoutManager
            var changedRows = 0
            var createdRows = 0
            instrumentation.runOnMainSync {
                activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                manager = AgentTranscriptLayoutManager(activity)
                adapter = object : AgentTranscriptRecyclerAdapter(activity) {
                    override fun createRow(entry: AgentTranscriptEntry): View { createdRows++; return super.createRow(entry) }
                }
                list = RecyclerView(activity).apply { layoutManager = manager; this.adapter = adapter; itemAnimator = null }
                activity.agentOutputList = list
                activity.agentOutputLayout = manager
                activity.agentTranscriptAdapter = adapter
                activity.renderedAgentTranscriptSourceEntries = listOf(entry)
                activity.agentRenderedConversationId = entry.conversationId
                VoiceReplyPlayback.watch(activity)
                activity.attachAgentReplySpeechStopGesture()
                adapter.replaceAll(listOf(entry))
                activity.addContentView(list, ViewGroup.LayoutParams(-1, -1))
            }
            try {
                var row: View? = null
                var paragraph: ParagraphSelectingTextView? = null
                var web: WebView? = null
                var ready = false
                val readyBy = SystemClock.elapsedRealtime() + 15_000
                while (SystemClock.elapsedRealtime() < readyBy) {
                    instrumentation.runOnMainSync {
                        row = manager.findViewByPosition(0)
                        val children = row?.let(::descendants).orEmpty()
                        paragraph = children.filterIsInstance<ParagraphSelectingTextView>().firstOrNull { it.text.contains(MARKER) }
                        web = children.filterIsInstance<WebView>().firstOrNull()
                        ready = paragraph?.layout != null && activity.hasWindowFocus() &&
                            (!media || web?.progress == 100 && web!!.height > 0 && children.filterIsInstance<android.widget.ImageView>().any { it.drawable != null })
                    }
                    if (ready) break
                    SystemClock.sleep(100)
                }
                assertTrue("Media and paragraph fixture must finish layout", ready)
                val target = requireNotNull(paragraph)
                val originalRow = requireNotNull(row)
                if (media) assertNotNull(web)
                val originalWeb = web
                instrumentation.runOnMainSync {
                    val textOrigin = location(target)[1]
                    val rowOrigin = location(originalRow)[1]
                    val offset = target.text.indexOf(MARKER)
                    val line = target.layout.getLineForOffset(offset)
                    val lineY = target.totalPaddingTop + (target.layout.getLineTop(line) + target.layout.getLineBottom(line)) / 2
                    manager.scrollToPositionWithOffset(0, list.height / 2 - (textOrigin - rowOrigin + lineY))
                    target.setTextClassifier(android.view.textclassifier.TextClassifier.NO_OP)
                    target.setOnParagraphDoubleTapListener {
                        VoiceReplyPlayback.publish(VoiceReplyPlaybackState("scroll-fixture", VoiceReplySelection(entry.conversationId, entry.id), "loading"))
                    }
                }
                SystemClock.sleep(500)
                val originalY = location(target)[1]
                val originalTop = originalRow.top
                val originalCreated = createdRows
                instrumentation.runOnMainSync {
                    adapter.registerAdapterDataObserver(object : RecyclerView.AdapterDataObserver() {
                        override fun onItemRangeChanged(start: Int, count: Int, payload: Any?) { changedRows++ }
                    })
                }
                fun stable() {
                    SystemClock.sleep(180)
                    instrumentation.runOnMainSync {
                        assertSame(originalRow, manager.findViewByPosition(0))
                        assertTrue("Paragraph viewport moved", kotlin.math.abs(originalY - location(target)[1]) <= 1)
                        assertEquals(originalTop, originalRow.top)
                        assertSame(target, descendants(originalRow).filterIsInstance<ParagraphSelectingTextView>().first { it.text.contains(MARKER) })
                        if (media) assertSame(originalWeb, descendants(originalRow).filterIsInstance<WebView>().single())
                        assertEquals("Speech must not issue adapter content changes", 0, changedRows)
                        assertEquals(originalCreated, createdRows)
                    }
                }
                var point = textPoint(target)
                tap(point.first, point.second)
                stable()
                point = textPoint(target)
                tap(point.first, point.second); SystemClock.sleep(70); tap(point.first, point.second)
                stable()
                assertTrue(VoiceReplyPlayback.state.playing)
                instrumentation.runOnMainSync {
                    VoiceReplyPlayback.publish(VoiceReplyPlayback.state.copy(status = "playing"))
                    assertTrue(descendants(originalRow).filterIsInstance<AgentReplySpeechButton>().single().isPlayingSpeech)
                }
                stable()
                point = textPoint(target)
                tap(point.first, point.second)
                stable()
                val blankX = location(target)[0] + target.width - 8f
                tap(blankX, point.second)
                SystemClock.sleep(350)
                stable()
                assertFalse(VoiceReplyPlayback.state.playing)
                instrumentation.runOnMainSync {
                    VoiceReplyPlayback.publish(VoiceReplyPlaybackState("scroll-fixture", VoiceReplySelection(entry.conversationId, entry.id), "playing"))
                }
                stable()
                instrumentation.runOnMainSync { VoiceReplyPlayback.publish(VoiceReplyPlaybackState()) }
                stable()
                assertFalse(VoiceReplyPlayback.state.playing)
            } finally {
                instrumentation.runOnMainSync {
                    VoiceReplyPlayback.publish(VoiceReplyPlaybackState())
                    (list.parent as? ViewGroup)?.removeView(list)
                    activity.agentOutputList = oldList
                    activity.agentOutputLayout = oldLayout
                    activity.agentTranscriptAdapter = oldAdapter
                    activity.renderedAgentTranscriptSourceEntries = oldEntries
                    activity.agentRenderedConversationId = oldRenderedConversation
                }
            }
        }
    }

    private fun reply(media: Boolean, merged: Boolean): AgentTranscriptEntry {
        val blocks = mutableListOf(AgentRichBlock("before", AgentRichBlockType.TEXT, text = "前文说明。\n".repeat(25)))
        if (media) {
            val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff168f78.toInt()) }
            val encoded = ByteArrayOutputStream().use { bytes -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes); Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP) }
            bitmap.recycle()
            blocks += AgentRichBlock("image", AgentRichBlockType.IMAGE, dataB64 = encoded, mimeType = "image/png")
            blocks += AgentRichBlock("animation", AgentRichBlockType.HTML, text = "<html><body><canvas width='100' height='60'></canvas><script>requestAnimationFrame(()=>{});</script></body></html>")
        }
        blocks += AgentRichBlock("after", AgentRichBlockType.TEXT, text = "上一段说明。\n".repeat(35) + "\n$MARKER\n\n" + "后文说明。\n".repeat(35))
        val id = UUID.randomUUID().toString()
        return AgentTranscriptEntry("final-$id", AgentTranscriptRole.ASSISTANT, "Scroll fixture", 1L,
            conversationId = "scroll-$id", turnId = id, taskId = id, richOutputJson = AgentRichContentCodec.encode(blocks),
            sourceConversationId = if (merged) "merged-fixture" else "")
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun location(view: View): IntArray = IntArray(2).also { result ->
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) view.getLocationOnScreen(result)
        else instrumentation.runOnMainSync { view.getLocationOnScreen(result) }
    }
    private fun textPoint(view: ParagraphSelectingTextView): Pair<Float, Float> {
        var point = 0f to 0f
        instrumentation.runOnMainSync {
            val position = view.text.indexOf(MARKER) + 2
            val line = view.layout.getLineForOffset(position)
            val origin = location(view)
            point = origin[0] + view.totalPaddingLeft + view.layout.getPrimaryHorizontal(position) to
                origin[1] + view.totalPaddingTop + (view.layout.getLineTop(line) + view.layout.getLineBottom(line)) / 2f
        }
        return point
    }
    private fun tap(x: Float, y: Float) {
        val down = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0).apply { source = android.view.InputDevice.SOURCE_TOUCHSCREEN }
            try { assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true)) } finally { event.recycle() }
            if (action == MotionEvent.ACTION_DOWN) SystemClock.sleep(40)
        }
    }
    private companion object { const val MARKER = "第二段从这里朗读。" }
}
