package com.signalasi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.EditText
import androidx.test.platform.app.InstrumentationRegistry
import com.signalasi.chat.ui.ParagraphSelectingEditText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ParagraphSelectionDeviceTest {
    @Test
    fun composerLongPressKeepsNativeSelectionAndExpandsToParagraph() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            val text = "第一段内容\n第二段可以跨行选择\n第三段"
            instrumentation.runOnMainSync {
                val agentInput = activity.findViewById<EditText>(R.id.agentGoalInput)
                val messageInput = activity.findViewById<EditText>(R.id.messageInput)
                assertTrue(agentInput is ParagraphSelectingEditText)
                assertTrue(messageInput is ParagraphSelectingEditText)

                activity.enterAgentComposerTextMode()
                agentInput.setText(text)
                agentInput.requestFocus()
                agentInput.setSelection(10)
            }
            instrumentation.waitForIdleSync()

            var touchX = 0f
            var touchY = 0f
            instrumentation.runOnMainSync {
                val input = activity.findViewById<EditText>(R.id.agentGoalInput)
                val layout = requireNotNull(input.layout)
                val targetOffset = 10
                val line = layout.getLineForOffset(targetOffset)
                touchX = input.totalPaddingLeft + layout.getPrimaryHorizontal(targetOffset) - input.scrollX
                touchY = input.totalPaddingTop +
                    (layout.getLineTop(line) + layout.getLineBottom(line)) / 2f - input.scrollY
            }
            val downTime = SystemClock.uptimeMillis()
            instrumentation.runOnMainSync {
                val event = MotionEvent.obtain(
                    downTime,
                    downTime,
                    MotionEvent.ACTION_DOWN,
                    touchX,
                    touchY,
                    0
                )
                activity.findViewById<EditText>(R.id.agentGoalInput).dispatchTouchEvent(event)
                event.recycle()
            }
            SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 150L)
            instrumentation.runOnMainSync {
                val event = MotionEvent.obtain(
                    downTime,
                    SystemClock.uptimeMillis(),
                    MotionEvent.ACTION_UP,
                    touchX,
                    touchY,
                    0
                )
                activity.findViewById<EditText>(R.id.agentGoalInput).dispatchTouchEvent(event)
                event.recycle()
            }
            instrumentation.waitForIdleSync()

            instrumentation.runOnMainSync {
                val input = activity.findViewById<EditText>(R.id.agentGoalInput)
                assertEquals(6, input.selectionStart)
                assertEquals(15, input.selectionEnd)
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
