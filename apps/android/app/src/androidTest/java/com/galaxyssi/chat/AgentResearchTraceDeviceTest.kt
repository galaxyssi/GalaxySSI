package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentResearchTraceDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun encryptedReceiptsAreScopedIdempotentAndDeletedWithConversation() {
        val key = "trace-test-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation("Search receipt verification", privateMode = true)
        val trace = AgentResearchTrace(listOf("query"), listOf(AgentResearchTrace.Source("https://example.org/source", "Source")))
        try {
            AgentResearchTraceStore.merge(context, conversation.id, "turn-a", trace)
            AgentResearchTraceStore.merge(context, conversation.id, "turn-a", trace)
            assertEquals(trace, AgentResearchTraceStore.read(context, conversation.id, "turn-a"))
            assertFalse(AgentResearchTraceStore.read(context, conversation.id, "turn-b").visible)
            assertFalse(AgentResearchTraceStore.read(context, "another-conversation", "turn-a").visible)
        } finally { store.deleteConversation(conversation.id) }
        assertFalse(AgentResearchTraceStore.read(context, conversation.id, "turn-a").visible)
        AgentResearchTraceStore.merge(context, conversation.id, "turn-a", trace)
        assertFalse("Late event must not recreate deleted search history",
            AgentResearchTraceStore.read(context, conversation.id, "turn-a").visible)
    }

    @Test fun transcriptDisclosureStartsCollapsedExpandsAndRestores() {
        val key = "trace-ui-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation("Search details UI test", privateMode = true)
        val turn = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val queries = listOf("\u73e0\u6d77\u4eca\u5929\u5929\u6c14", "\u73e0\u6d77\u5929\u6c14\u5b98\u65b9\u9884\u62a5")
        val sources = listOf(
            AgentResearchTrace.Source("https://www.cma.gov.cn/", "\u4e2d\u56fd\u6c14\u8c61\u5c40"),
            AgentResearchTrace.Source("https://weather.cma.cn/", "\u4e2d\u592e\u6c14\u8c61\u53f0"))
        store.append(AgentTranscriptRole.USER, queries.first(), timestampMillis = now,
            conversationId = conversation.id, turnId = turn, taskId = turn)
        store.append(AgentTranscriptRole.PROCESS, "\u6b63\u5728\u6838\u5bf9\u5929\u6c14\u6765\u6e90", timestampMillis = now + 1,
            conversationId = conversation.id, turnId = turn, taskId = turn)
        store.append(AgentTranscriptRole.ASSISTANT, "\u8fd9\u662f\u641c\u7d22\u8be6\u60c5 UI \u6d4b\u8bd5\uff0c\u4e0d\u662f\u5b9e\u65f6\u5929\u6c14\u62a5\u544a\u3002", timestampMillis = now + 8000,
            conversationId = conversation.id, turnId = turn, taskId = turn)
        AgentResearchTraceStore.merge(context, conversation.id, turn, AgentResearchTrace(queries, sources))
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var activity: MainActivity? = null
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            activity = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Test window did not launch")
            val main = activity
            val title = context.getString(R.string.research_trace_summary, 2, 2)
            await { texts(main.window.decorView).any { it.text.toString() == title && it.isShown } }
            instrumentation.runOnMainSync {
                assertFalse(texts(main.window.decorView).any { it.text.toString().contains(sources.first().title) })
                val label = texts(main.window.decorView).first { it.text.toString() == title }
                assertTrue((label.parent as View).performClick())
            }
            await { texts(main.window.decorView).any { it.text.toString() == "1. ${sources.first().title}" && it.isShown } }
            instrumentation.runOnMainSync {
                val label = texts(main.window.decorView).first { it.text.toString() == title }
                val block = (label.parent as View).parent as View
                assertTrue(block.width > 0)
                val bitmap = Bitmap.createBitmap(block.width, block.height, Bitmap.Config.ARGB_8888)
                block.draw(android.graphics.Canvas(bitmap))
                val file = File(context.getExternalFilesDir("reports"), "research-trace-ui.png")
                file.parentFile?.mkdirs()
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
                assertTrue((label.parent as View).performClick())
                assertFalse(texts(main.window.decorView).any { it.text.toString() == "1. ${sources.first().title}" })
                // Rebuilding the transcript must preserve the collapsed state and the stored counts.
                main.clearAgentTranscriptRows()
                main.refreshAgentTranscriptWindow(conversation.id)
            }
            await { texts(main.window.decorView).any { it.text.toString() == title && it.isShown } }
            assertEquals(2, AgentResearchTraceStore.read(context, conversation.id, turn).sources.size)
        } finally {
            activity?.let { main -> instrumentation.runOnMainSync { main.finishAndRemoveTask() } }
            instrumentation.removeMonitor(monitor)
            store.deleteConversation(conversation.id)
        }
    }

    private fun texts(view: View): List<TextView> = buildList {
        if (view is TextView) add(view)
        if (view is ViewGroup) for (i in 0 until view.childCount) addAll(texts(view.getChildAt(i)))
    }
    private fun await(test: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < end) {
            var ready = false
            instrumentation.runOnMainSync { ready = test() }
            if (ready) return
            SystemClock.sleep(200)
        }
        error("Timed out waiting for search disclosure")
    }
}
