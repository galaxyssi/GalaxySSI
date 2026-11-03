package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class AttentionNewsSearchUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun main(action: () -> Unit) = instrumentation.runOnMainSync(action)
    private fun waitFor(condition: () -> Boolean) {
        val until = SystemClock.uptimeMillis() + 30_000
        while (SystemClock.uptimeMillis() < until) { if (condition()) return; SystemClock.sleep(80) }
        assertTrue("UI condition timed out", condition())
    }
    private fun nodes(node: AccessibilityNodeInfo?): Sequence<AccessibilityNodeInfo> = sequence {
        if (node == null) return@sequence
        yield(node)
        for (index in 0 until node.childCount) yieldAll(nodes(node.getChild(index)))
    }
    private fun clickMenu(label: String) {
        waitFor {
            var node = nodes(instrumentation.uiAutomation.rootInActiveWindow).firstOrNull {
                it.text?.toString() == label || it.contentDescription?.toString() == label
            }
            while (node != null && !node.isClickable) node = node.parent
            node?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
        }
    }
    private fun screenshot(name: String) {
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        File(instrumentation.targetContext.filesDir, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    @Test fun searchMenuOpensResultsAndCancelPreservesOriginalReaderAnchor() {
        ActivityScenario.launch(ProactiveAttentionActivity::class.java).use { scenario ->
            lateinit var activity: ProactiveAttentionActivity
            lateinit var list: RecyclerView
            scenario.onActivity { host -> activity = host; list = host.window.decorView.findViewWithTag("attention-reader-list") }
            waitFor { var ready = false; main { ready = (list.adapter?.itemCount ?: 0) > 0 }; ready }
            main { (list.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(minOf(12, list.adapter!!.itemCount - 1), -20) }
            instrumentation.waitForIdleSync(); SystemClock.sleep(600)
            var key = ""
            var offset = 0
            main {
                key = list.getChildAt(0).tag.toString(); offset = list.getChildAt(0).top
                activity.window.decorView.findViewWithTag<View>("attention-feed-menu").performClick()
            }
            screenshot("news-search-menu-device.png")
            val monitor = instrumentation.addMonitor(AttentionNewsSearchActivity::class.java.name, null, false)
            var search: Activity? = null
            try {
                clickMenu(activity.getString(R.string.attention_search_title))
                search = instrumentation.waitForMonitorWithTimeout(monitor, 5000)
                assertNotNull(search)
                val root = search!!.window.decorView
                main {
                    root.findViewWithTag<EditText>("attention-search-input").apply {
                        setText("苹果"); onEditorAction(EditorInfo.IME_ACTION_SEARCH)
                    }
                }
                waitFor {
                    var ready = false
                    main { ready = root.findViewWithTag<TextView>("attention-search-count").text.isNotBlank() }
                    ready
                }
                main {
                    assertEquals(activity.getString(R.string.attention_search_all), root.findViewWithTag<TextView>("attention-search-scope").text.toString())
                    assertTrue(root.findViewWithTag<RecyclerView>("attention-search-results").adapter!!.itemCount <= 30)
                }
                screenshot("news-search-results-device.png")
                main {
                    val input = root.findViewWithTag<EditText>("attention-search-input")
                    input.setText("迅速替换的旧查询"); input.setText("不存在的新闻搜索词987654321")
                    input.onEditorAction(EditorInfo.IME_ACTION_SEARCH)
                }
                waitFor {
                    var ready = false
                    main { ready = root.findViewWithTag<TextView>("attention-search-count").text.toString() ==
                        activity.getString(R.string.attention_search_count, 0) }
                    ready
                }
                main { root.findViewWithTag<View>("attention-search-cancel").performClick() }
                waitFor { var ready = false; main { ready = activity.hasWindowFocus() }; ready }
                instrumentation.waitForIdleSync()
                main { assertEquals(key, list.getChildAt(0).tag.toString()); assertEquals(offset, list.getChildAt(0).top) }
            } finally { search?.let { main { it.finish() } }; instrumentation.removeMonitor(monitor) }
        }
    }

    @Test fun recreationRestoresQueryAndResultScrollPosition() {
        ActivityScenario.launch(AttentionNewsSearchActivity::class.java).use { scenario ->
            lateinit var activity: AttentionNewsSearchActivity
            scenario.onActivity {
                activity = it
                it.window.decorView.findViewWithTag<EditText>("attention-search-input").apply {
                    setText("苹果"); onEditorAction(EditorInfo.IME_ACTION_SEARCH)
                }
            }
            waitFor { var ready = false; main {
                ready = activity.window.decorView.findViewWithTag<TextView>("attention-search-count").text.isNotBlank()
            }; ready }
            var anchor = ""
            var offset = 0
            main {
                val list = activity.window.decorView.findViewWithTag<RecyclerView>("attention-search-results")
                if (list.adapter!!.itemCount > 4) (list.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(3, -12)
            }
            instrumentation.waitForIdleSync(); SystemClock.sleep(300)
            main {
                val list = activity.window.decorView.findViewWithTag<RecyclerView>("attention-search-results")
                anchor = list.getChildAt(0)?.tag.toString(); offset = list.getChildAt(0)?.top ?: 0
            }
            scenario.recreate()
            scenario.onActivity { activity = it }
            waitFor { var ready = false; main {
                ready = activity.window.decorView.findViewWithTag<TextView>("attention-search-count").text.isNotBlank()
            }; ready }
            instrumentation.waitForIdleSync(); SystemClock.sleep(300)
            main {
                assertEquals("苹果", activity.window.decorView.findViewWithTag<EditText>("attention-search-input").text.toString())
                val list = activity.window.decorView.findViewWithTag<RecyclerView>("attention-search-results")
                assertEquals(anchor, list.getChildAt(0)?.tag.toString()); assertEquals(offset, list.getChildAt(0)?.top ?: 0)
            }
        }
    }
}
