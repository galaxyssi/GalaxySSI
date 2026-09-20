package com.galaxyssi.chat

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.text.Selection
import android.text.Spannable
import android.view.MotionEvent
import android.view.InputDevice
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
import org.junit.Assert.*
import org.junit.Test

class PeerTextSelectionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val contact = Contact("selection-test", "Selection test", "")
    private val text = "First paragraph for selection.\n\nSecond paragraph with more words.\n\nThird paragraph."

    @Test fun receivedMessageSupportsParagraphSelectionAndPartialCopy() = checkSelection(mine = false)
    @Test fun sentMessageSupportsParagraphSelectionAndPartialCopy() = checkSelection(mine = true)

    private fun checkSelection(mine: Boolean) = withActivity { activity ->
        lateinit var list: RecyclerView
        lateinit var output: ParagraphSelectingTextView
        var oldPopupCount = 0
        instrumentation.runOnMainSync {
            list = RecyclerView(activity).apply {
                layoutManager = LinearLayoutManager(activity)
                adapter = MessageAdapter(listOf(ChatMessage(1L, text, mine, contact)),
                    onMessageActions = { oldPopupCount++ })
                setBackgroundColor(android.graphics.Color.WHITE)
            }
            activity.addContentView(list, ViewGroup.LayoutParams(-1, -1))
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            output = (requireNotNull(list.findViewHolderForAdapterPosition(0)) as MessageAdapter.VH)
                .bubble as ParagraphSelectingTextView
            assertTrue(output.isTextSelectable)
        }
        longPress(output, text.indexOf("with more"))
        SystemClock.sleep(350L)
        instrumentation.uiAutomation.takeScreenshot()?.let { screenshot ->
            val name = if (mine) "peer-selection-sent.png" else "peer-selection-received.png"
            java.io.File(activity.cacheDir, name).outputStream().use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            screenshot.recycle()
        }
        instrumentation.runOnMainSync {
            assertEquals(0, oldPopupCount)
            assertEquals(text.indexOf("Second"), output.selectionStart)
            assertEquals(text.indexOf("\n\nThird"), output.selectionEnd)
            // A single selectable buffer retains paragraph separators and native copy semantics.
            val start = text.indexOf("paragraph")
            val end = text.indexOf("Third") + "Third".length
            Selection.setSelection(output.text as Spannable, start, end)
            assertTrue(output.onTextContextMenuItem(android.R.id.copy))
            val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            assertEquals(text.substring(start, end), clipboard.primaryClip?.getItemAt(0)?.text.toString())
        }
    }

    @Test fun recycledVoiceBubbleRestoresTextSelectionWithoutInterceptingLongPress() = withActivity { activity ->
        instrumentation.runOnMainSync {
            val voice = ChatMessage(1L, "[\u8bed\u97f3] test", false, contact)
            val plain = ChatMessage(2L, text, false, contact)
            var actions = 0
            val adapter = MessageAdapter(listOf(voice), onMessageActions = { actions++ })
            val holder = adapter.onCreateViewHolder(FrameLayout(activity), 0)
            adapter.onBindViewHolder(holder, 0)
            assertFalse(holder.bubble.isTextSelectable)
            assertTrue(holder.bubble.performLongClick())
            assertEquals(1, actions)
            adapter.syncMessages(listOf(plain))
            adapter.onBindViewHolder(holder, 0)
            assertTrue(holder.bubble.isTextSelectable)
            assertNotNull(holder.bubble.customSelectionActionModeCallback)
            assertEquals(text, holder.bubble.text.toString())
        }
    }

    @Test fun moreActionsResolveMessageAfterEarlierHistoryIsInserted() = withActivity { activity ->
        instrumentation.runOnMainSync {
            val message = ChatMessage(2L, text, false, contact)
            var actionPosition = -1
            val adapter = MessageAdapter(listOf(message), onMessageActions = { actionPosition = it })
            val holder = adapter.onCreateViewHolder(FrameLayout(activity), 0)
            adapter.onBindViewHolder(holder, 0)
            val callback = requireNotNull(holder.bubble.customSelectionActionModeCallback)
            val mode = requireNotNull(activity.startActionMode(callback))
            val more = requireNotNull(mode.menu.findItem(R.id.peer_selection_more))
            adapter.syncMessages(listOf(ChatMessage(1L, "Earlier", true, contact), message))
            assertTrue(callback.onActionItemClicked(mode, more))
            assertEquals(1, actionPosition)
        }
    }

    private fun longPress(view: ParagraphSelectingTextView, offset: Int) {
        var x = 0f
        var y = 0f
        instrumentation.runOnMainSync {
            val layout = requireNotNull(view.layout)
            val line = layout.getLineForOffset(offset)
            val location = IntArray(2)
            view.getLocationOnScreen(location)
            x = location[0] + view.totalPaddingLeft + layout.getPrimaryHorizontal(offset) - view.scrollX
            y = location[1] + view.totalPaddingTop + (layout.getLineTop(line) + layout.getLineBottom(line)) / 2f - view.scrollY
        }
        val down = SystemClock.uptimeMillis()
        fun event(action: Int) {
            MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0).also {
                it.source = InputDevice.SOURCE_TOUCHSCREEN
                instrumentation.sendPointerSync(it)
                it.recycle()
            }
        }
        event(MotionEvent.ACTION_DOWN)
        SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 160L)
        event(MotionEvent.ACTION_UP)
        instrumentation.waitForIdleSync()
    }

    private fun withActivity(block: (MainActivity) -> Unit) {
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        try {
            block(activity)
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
