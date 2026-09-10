package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AgentMemoryBrowseUiDeviceTest {
    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    @Test fun rendererKeepsOnlyOnePageAndTwoCursorsWithLocalizedNavigation() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val deadline = SystemClock.uptimeMillis() + 10_000
            var ready = false
            while (!ready && SystemClock.uptimeMillis() < deadline) {
                scenario.onActivity { activity ->
                    ready = activity.findViewById<View>(R.id.startupConnectingView).visibility == View.GONE &&
                        activity.window.decorView.hasWindowFocus()
                }
                if (!ready) SystemClock.sleep(50)
            }
            assertTrue("Startup overlay must finish before checking the visible page", ready)
            val entries = (0 until 25).map { AgentMemoryBrowseEntry(deletionMemory(it).copy(value = "\u5206\u9875\u663e\u793a\u6d4b\u8bd5-$it")) }
            val request = AgentMemoryBrowseRequest()
            val cursor = AgentMemoryBrowseCursor(0, 0, 25, "synthetic", "revision", "scope")
            val content = AgentMemoryPageContent(AgentMemoryBrowsePage(entries, AgentMemoryBrowseCounts(100_000_001, 12, 8), cursor, cursor), false, request)
            scenario.onActivity { activity ->
                activity.showFeaturePage(activity.getString(R.string.agent_memory_title))
                activity.renderAgentMemoryPage(content, emptySet())
                val nodes = descendants(activity.featureContent)
                assertEquals(25, nodes.filterIsInstance<TextView>().count { it.text.startsWith("\u5206\u9875\u663e\u793a\u6d4b\u8bd5-") })
                val controls = nodes.filterIsInstance<ImageButton>().map { it.contentDescription?.toString() }
                assertTrue(controls.contains(activity.getString(R.string.agent_memory_page_previous)))
                assertTrue(controls.contains(activity.getString(R.string.agent_memory_page_next)))
                assertTrue(nodes.filterIsInstance<TextView>().any { it.text.contains("100000001") })
                // Replacing a page must not accumulate its views or decrypted content.
                activity.featureContent.removeAllViews()
                activity.renderAgentMemoryPage(content.copy(page = content.page.copy(entries = entries.take(2), next = null)), emptySet())
                assertEquals(2, descendants(activity.featureContent).filterIsInstance<TextView>()
                    .count { it.text.startsWith("\u5206\u9875\u663e\u793a\u6d4b\u8bd5-") })
            }
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val drawn = CountDownLatch(1)
            scenario.onActivity { activity ->
                activity.featureContent.postOnAnimation { activity.featureContent.postOnAnimation { drawn.countDown() } }
            }
            assertTrue("The page must reach the display before capture", drawn.await(5, TimeUnit.SECONDS))
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                val first = descendants(activity.featureContent).filterIsInstance<TextView>()
                    .first { it.text.startsWith("\u5206\u9875\u663e\u793a\u6d4b\u8bd5-0") }
                assertTrue(first.isShown && first.getGlobalVisibleRect(Rect()))
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try {
                    val file = File(instrumentation.targetContext.externalCacheDir ?: instrumentation.targetContext.cacheDir, "memory-browse-ui.png")
                    file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    Log.i("GalaxySSIMemoryBrowse", "syntheticUiScreenshot=${file.absolutePath}")
                } finally { bitmap.recycle() }
            }
        }
    }
}
