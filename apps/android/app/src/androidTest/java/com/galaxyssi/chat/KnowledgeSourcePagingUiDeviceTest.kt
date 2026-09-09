package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in production-page test. Only the named temporary records are removed. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePagingUiDeviceTest {
    @Test fun normalPageShows50Then5AndReturnsWithoutAccumulatingViews() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("knowledgeSourcesUi") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val prefix = "test-source-ui-${UUID.randomUUID()}"
        val ids = (0 until 55).map { "$prefix-$it" }
        val sourcePrefix = "test-source-ui://$prefix/"
        val label = "\u5206\u9875\u77e5\u8bc6-${prefix.takeLast(8)}-"
        val db = AgentKnowledgeDatabase.shared(context, KnowledgeSemanticRuntime.DATABASE, KnowledgeSemanticRuntime.LEGACY)
        val store = SQLiteAgentKnowledgeStore(context, KnowledgeSemanticRuntime.DATABASE, KnowledgeSemanticRuntime.LEGACY) { _, _ -> }
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        try {
            await {
                var ready = false
                instrumentation.runOnMainSync { ready = activity.findViewById<View>(R.id.startupConnectingView).visibility == View.GONE }
                ready
            }
            ids.forEachIndexed { index, id -> store.upsert(AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE,
                "$label$index", "\u77e5\u8bc6\u5206\u9875\u771f\u673a\u6d4b\u8bd5 $index", source = "$sourcePrefix$index",
                updatedAtMillis = Long.MAX_VALUE - index)) }
            instrumentation.runOnMainSync { activity.showAgentKnowledgePage() }
            await { labels(activity, label) == 50 && button(activity, R.string.knowledge_sources_next) != null }
            instrumentation.runOnMainSync { assertTrue(requireNotNull(button(activity, R.string.knowledge_sources_next)).performClick()) }
            await { labels(activity, label) == 5 && button(activity, R.string.knowledge_sources_previous) != null }
            instrumentation.waitForIdleSync()
            val drawn = java.util.concurrent.CountDownLatch(1)
            instrumentation.runOnMainSync {
                activity.featureContent.postOnAnimation { activity.featureContent.postOnAnimation { drawn.countDown() } }
            }
            assertTrue("Source page must draw before capture", drawn.await(10, java.util.concurrent.TimeUnit.SECONDS))
            val destination = File(context.getExternalFilesDir(null), "embedding-test/knowledge-sources-page-two.png")
            destination.parentFile?.mkdirs()
            requireNotNull(instrumentation.uiAutomation.takeScreenshot()).let { bitmap ->
                destination.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                bitmap.recycle()
            }
            instrumentation.runOnMainSync { assertTrue(requireNotNull(button(activity, R.string.knowledge_sources_previous)).performClick()) }
            await { labels(activity, label) == 50 && button(activity, R.string.knowledge_sources_previous) == null }
            println("KNOWLEDGE_SOURCE_UI first_page=50 second_page=5 return_page=50")
        } finally {
            db.transaction { sql -> ids.forEach { id ->
                val key = db.key("id", id)
                db.readSourceMetadata(sql, key)?.let { summary ->
                    check(summary.source.startsWith(sourcePrefix))
                    sql.delete("knowledge_items", "item_key=?", arrayOf(key))
                }
            } }
            KnowledgeSemanticRuntime.production(context).requestIndex()
            instrumentation.runOnMainSync { activity.showAgentKnowledgePage() }
        }
    }
    private fun labels(activity: MainActivity, prefix: String): Int {
        var count = 0
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            count = views(activity.featureContent).filterIsInstance<TextView>().count { it.text.startsWith(prefix) }
        }
        return count
    }
    private fun button(activity: MainActivity, resource: Int): View? {
        var result: View? = null
        val locate = { result = views(activity.featureContent)
            .firstOrNull { it.contentDescription?.toString() == activity.getString(resource) && it.isClickable } }
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) locate()
        else InstrumentationRegistry.getInstrumentation().runOnMainSync { locate() }
        return result
    }
    private fun views(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) repeat(view.childCount) { yieldAll(views(view.getChildAt(it))) }
    }
    private fun await(condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 90_000
        while (!condition()) { check(SystemClock.elapsedRealtime() < deadline) { "Knowledge pagination UI did not settle" }; SystemClock.sleep(100) }
    }
}
