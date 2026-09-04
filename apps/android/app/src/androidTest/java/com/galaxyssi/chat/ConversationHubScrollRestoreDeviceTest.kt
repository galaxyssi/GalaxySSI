package com.galaxyssi.chat

import android.app.Dialog
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConversationHubScrollRestoreDeviceTest {
    @Test
    fun restoresMiddlePositionAfterOpeningAgentConversationWithOneThousandRows() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val requiredConversations = InstrumentationRegistry.getArguments()
            .getString(MIN_CONVERSATIONS_ARGUMENT)
            ?.toIntOrNull()
            ?.coerceAtLeast(1)
            ?: 1_000
        var activity: MainActivity? = null
        var dialog: Dialog? = null
        try {
            val launchedActivity = launchActivity(instrumentation)
            activity = launchedActivity
            val activeCount = launchedActivity.agentTranscriptStore.conversationCount(AgentConversationStatus.ACTIVE)
            assertTrue(
                "Expected at least $requiredConversations active conversations, found $activeCount",
                activeCount >= requiredConversations
            )

            instrumentation.runOnMainSync { launchedActivity.showAgentSessionsPage() }
            val activeDialog = waitForDialog(instrumentation, launchedActivity)
            dialog = activeDialog
            val recycler = waitForConversationList(instrumentation, activeDialog)
            val adapter = recycler.adapter as? ConversationHubListAdapter
            assertNotNull("Conversation hub adapter is missing", adapter)
            val conversationAdapter = requireNotNull(adapter)

            loadAgentRows(
                instrumentation = instrumentation,
                recycler = recycler,
                adapter = conversationAdapter,
                requiredCount = requiredConversations
            )
            val agentPositions = conversationAdapter.currentList.indices.filter { position ->
                val row = conversationAdapter.currentList[position]
                row is ConversationHubRow.Conversation && row.item.kind == ConversationHubItemKind.AGENT
            }
            assertTrue(agentPositions.size >= requiredConversations)
            val targetPosition = agentPositions[requiredConversations / 2]
            val layout = recycler.layoutManager as LinearLayoutManager
            instrumentation.runOnMainSync {
                layout.scrollToPositionWithOffset(targetPosition, ANCHOR_OFFSET_PX)
            }
            instrumentation.waitForIdleSync()
            SystemClock.sleep(350L)

            val before = readAnchor(instrumentation, recycler, conversationAdapter)
            assertTrue("The exercised position must be in the middle of the list", before.position > 100)
            val clickedStableId = clickVisibleAgentRow(
                instrumentation,
                recycler,
                conversationAdapter
            )
            waitUntil("Conversation hub did not hide after opening $clickedStableId") {
                !activeDialog.isShowing
            }

            instrumentation.runOnMainSync { launchedActivity.showAgentSessionsPage() }
            waitUntil("Conversation hub did not return") { activeDialog.isShowing }
            assertSame("Returning recreated the conversation hub", activeDialog, launchedActivity.agentSessionsDialog)
            assertSame("Returning recreated the conversation adapter", conversationAdapter, recycler.adapter)

            val restored = waitForAnchor(
                instrumentation = instrumentation,
                recycler = recycler,
                adapter = conversationAdapter,
                stableRowId = before.stableRowId
            )
            assertEquals(before.stableRowId, restored.stableRowId)
            assertTrue(
                "Scroll offset changed from ${before.topOffset}px to ${restored.topOffset}px",
                abs(before.topOffset - restored.topOffset) <= OFFSET_TOLERANCE_PX
            )

            val screenshot = writeScreenshot(instrumentation, launchedActivity)
            val report = JSONObject()
                .put("active_conversation_count", activeCount)
                .put("loaded_agent_rows", agentPositions.size)
                .put("anchor_position_before", before.position)
                .put("anchor_position_after", restored.position)
                .put("anchor_stable_id", before.stableRowId)
                .put("top_offset_before_px", before.topOffset)
                .put("top_offset_after_px", restored.topOffset)
                .put("opened_row_stable_id", clickedStableId)
                .put("dialog_reused", true)
                .put("adapter_reused", true)
                .put("screenshot", screenshot.name)
            File(requireNotNull(launchedActivity.getExternalFilesDir(null)), REPORT_FILE)
                .writeText(report.toString(2), Charsets.UTF_8)
        } finally {
            instrumentation.runOnMainSync {
                dialog?.dismiss()
                activity?.finish()
            }
        }
    }

    private fun launchActivity(instrumentation: android.app.Instrumentation): MainActivity {
        val intent = Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return instrumentation.startActivitySync(intent) as? MainActivity
            ?: throw AssertionError("MainActivity did not launch")
    }

    private fun waitForDialog(
        instrumentation: android.app.Instrumentation,
        activity: MainActivity
    ): Dialog {
        var result: Dialog? = null
        waitUntil("Conversation hub did not open") {
            instrumentation.runOnMainSync { result = activity.agentSessionsDialog }
            result?.isShowing == true
        }
        return requireNotNull(result)
    }

    private fun waitForConversationList(
        instrumentation: android.app.Instrumentation,
        dialog: Dialog
    ): RecyclerView {
        var result: RecyclerView? = null
        waitUntil("Conversation list was not rendered") {
            instrumentation.runOnMainSync {
                result = dialog.window?.decorView?.let(::findRecyclerView)
            }
            result?.adapter is ConversationHubListAdapter
        }
        return requireNotNull(result)
    }

    private fun loadAgentRows(
        instrumentation: android.app.Instrumentation,
        recycler: RecyclerView,
        adapter: ConversationHubListAdapter,
        requiredCount: Int
    ) {
        val deadline = SystemClock.elapsedRealtime() + LOAD_TIMEOUT_MILLIS
        var loadedCount = 0
        while (SystemClock.elapsedRealtime() < deadline) {
            loadedCount = agentRowCount(adapter)
            if (loadedCount >= requiredCount) return
            instrumentation.runOnMainSync {
                recycler.scrollBy(0, maxOf(recycler.height * 3, MIN_PAGE_SCROLL_PX))
            }
            instrumentation.waitForIdleSync()
            SystemClock.sleep(PAGE_SETTLE_MILLIS)
        }
        throw AssertionError("Loaded only $loadedCount of $requiredCount required Agent rows")
    }

    private fun agentRowCount(adapter: ConversationHubListAdapter): Int =
        adapter.currentList.count { row ->
            row is ConversationHubRow.Conversation && row.item.kind == ConversationHubItemKind.AGENT
        }

    private fun clickVisibleAgentRow(
        instrumentation: android.app.Instrumentation,
        recycler: RecyclerView,
        adapter: ConversationHubListAdapter
    ): String {
        var clickedStableId = ""
        instrumentation.runOnMainSync {
            val layout = recycler.layoutManager as LinearLayoutManager
            val position = (layout.findFirstVisibleItemPosition()..layout.findLastVisibleItemPosition())
                .firstOrNull { candidate ->
                    val row = adapter.currentList.getOrNull(candidate)
                    row is ConversationHubRow.Conversation &&
                        row.item.kind == ConversationHubItemKind.AGENT &&
                        layout.findViewByPosition(candidate) != null
                }
                ?: throw AssertionError("No visible Agent conversation row")
            val row = adapter.currentList[position]
            val rowView = requireNotNull(layout.findViewByPosition(position))
            val clickable = findClickableView(rowView)
                ?: throw AssertionError("Agent conversation row is not clickable")
            assertTrue("Agent conversation click was not handled", clickable.performClick())
            clickedStableId = row.stableId
        }
        return clickedStableId
    }

    private fun waitForAnchor(
        instrumentation: android.app.Instrumentation,
        recycler: RecyclerView,
        adapter: ConversationHubListAdapter,
        stableRowId: String
    ): ScrollAnchor {
        var result: ScrollAnchor? = null
        waitUntil("Conversation list did not restore anchor $stableRowId") {
            result = readAnchor(instrumentation, recycler, adapter)
            result?.stableRowId == stableRowId
        }
        return requireNotNull(result)
    }

    private fun readAnchor(
        instrumentation: android.app.Instrumentation,
        recycler: RecyclerView,
        adapter: ConversationHubListAdapter
    ): ScrollAnchor {
        var result: ScrollAnchor? = null
        instrumentation.runOnMainSync {
            val layout = recycler.layoutManager as LinearLayoutManager
            val position = layout.findFirstVisibleItemPosition()
            val row = adapter.currentList.getOrNull(position)
                ?: throw AssertionError("No row at first visible position $position")
            val view = layout.findViewByPosition(position)
                ?: throw AssertionError("No view at first visible position $position")
            result = ScrollAnchor(
                position = position,
                stableRowId = row.stableId,
                topOffset = view.top - recycler.paddingTop
            )
        }
        return requireNotNull(result)
    }

    private fun findRecyclerView(view: View): RecyclerView? {
        if (view is RecyclerView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findRecyclerView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun findClickableView(view: View): View? {
        if (view.isClickable) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findClickableView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun waitUntil(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + UI_TIMEOUT_MILLIS
        while (SystemClock.elapsedRealtime() < deadline) {
            if (condition()) return
            SystemClock.sleep(50L)
        }
        throw AssertionError(message)
    }

    private fun writeScreenshot(
        instrumentation: android.app.Instrumentation,
        activity: MainActivity
    ): File {
        val output = File(requireNotNull(activity.getExternalFilesDir(null)), SCREENSHOT_FILE)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        FileOutputStream(output).use { stream ->
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
        }
        return output
    }

    private data class ScrollAnchor(
        val position: Int,
        val stableRowId: String,
        val topOffset: Int
    )

    private companion object {
        const val MIN_CONVERSATIONS_ARGUMENT = "galaxyssi_min_conversations"
        const val UI_TIMEOUT_MILLIS = 30_000L
        const val LOAD_TIMEOUT_MILLIS = 120_000L
        const val PAGE_SETTLE_MILLIS = 140L
        const val MIN_PAGE_SCROLL_PX = 2_000
        const val ANCHOR_OFFSET_PX = 37
        const val OFFSET_TOLERANCE_PX = 2
        const val REPORT_FILE = "conversation-hub-scroll-restore-report.json"
        const val SCREENSHOT_FILE = "conversation-hub-scroll-restore-1000.png"
    }
}
