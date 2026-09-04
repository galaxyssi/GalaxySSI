package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.text.Selection
import android.text.Spannable
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.EditText
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.ParagraphSelectingEditText
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
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

    @Test
    fun assistantOutputLongPressSelectsParagraphAndKeepsWholeReplyInOneView() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            val text = "第一段内容\n\n第二段可以跨行选择\n\n第三段"
            lateinit var output: ParagraphSelectingTextView
            instrumentation.runOnMainSync {
                val row = activity.agentAssistantTranscriptRow(
                    AgentTranscriptEntry(
                        id = "paragraph-selection-output",
                        role = AgentTranscriptRole.ASSISTANT,
                        text = text,
                        timestampMillis = System.currentTimeMillis()
                    )
                )
                output = requireNotNull(row.findDescendantParagraphTextView())
                assertEquals(text, output.text.toString())
                activity.addContentView(
                    row,
                    android.view.ViewGroup.LayoutParams(
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                        android.view.ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
            }
            instrumentation.waitForIdleSync()

            var touchX = 0f
            var touchY = 0f
            instrumentation.runOnMainSync {
                val layout = requireNotNull(output.layout)
                val targetOffset = text.indexOf("跨行")
                val line = layout.getLineForOffset(targetOffset)
                touchX = output.totalPaddingLeft + layout.getPrimaryHorizontal(targetOffset) - output.scrollX
                touchY = output.totalPaddingTop +
                    (layout.getLineTop(line) + layout.getLineBottom(line)) / 2f - output.scrollY
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
                output.dispatchTouchEvent(event)
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
                output.dispatchTouchEvent(event)
                event.recycle()
            }
            instrumentation.waitForIdleSync()

            instrumentation.runOnMainSync {
                assertEquals(text.indexOf("第二段"), Selection.getSelectionStart(output.text))
                assertEquals(text.indexOf("\n\n第三段"), Selection.getSelectionEnd(output.text))
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test
    fun assistantOutputDoubleTapReadsOnlyTheTappedParagraph() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            val text = "第一段内容\n\n第二段可以单独朗读\n\n第三段"
            lateinit var output: ParagraphSelectingTextView
            var spokenParagraph = ""
            instrumentation.runOnMainSync {
                output = ParagraphSelectingTextView(activity).apply {
                    this.text = text
                    textSize = 18f
                    setPadding(24, 24, 24, 24)
                    setOnParagraphDoubleTapListener { selection -> spokenParagraph = selection.paragraph }
                }
                activity.addContentView(
                    output,
                    android.view.ViewGroup.LayoutParams(
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                        android.view.ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
            }
            instrumentation.waitForIdleSync()

            var touchX = 0f
            var touchY = 0f
            instrumentation.runOnMainSync {
                val layout = requireNotNull(output.layout)
                val targetOffset = text.indexOf("单独")
                val line = layout.getLineForOffset(targetOffset)
                touchX = output.totalPaddingLeft + layout.getPrimaryHorizontal(targetOffset) - output.scrollX
                touchY = output.totalPaddingTop +
                    (layout.getLineTop(line) + layout.getLineBottom(line)) / 2f - output.scrollY
            }

            val firstDown = SystemClock.uptimeMillis()
            val secondDown = firstDown + 120L
            instrumentation.runOnMainSync {
                listOf(
                    MotionEvent.obtain(firstDown, firstDown, MotionEvent.ACTION_DOWN, touchX, touchY, 0),
                    MotionEvent.obtain(firstDown, firstDown + 40L, MotionEvent.ACTION_UP, touchX, touchY, 0),
                    MotionEvent.obtain(secondDown, secondDown, MotionEvent.ACTION_DOWN, touchX, touchY, 0),
                    MotionEvent.obtain(secondDown, secondDown + 40L, MotionEvent.ACTION_UP, touchX, touchY, 0)
                ).forEach { event ->
                    output.dispatchTouchEvent(event)
                    event.recycle()
                }
            }
            instrumentation.waitForIdleSync()

            assertEquals("第二段可以单独朗读", spokenParagraph)
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test
    fun structuredAndProcessParagraphsShareCrossParagraphSelectionSurfaces() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            instrumentation.runOnMainSync {
                val structured = activity.agentAssistantTranscriptRow(
                    AgentTranscriptEntry(
                        id = "structured-selection-output",
                        role = AgentTranscriptRole.ASSISTANT,
                        text = "第一段\n\n## 标题\n\n第二段\n\n- 列表一\n- 列表二\n\n第三段",
                        timestampMillis = System.currentTimeMillis()
                    )
                )
                val structuredOutputs = structured.findDescendantParagraphTextViews()
                assertEquals(1, structuredOutputs.size)
                val structuredText = structuredOutputs.single().text as Spannable
                val selectionStart = structuredText.indexOf("第二段")
                val selectionEnd = structuredText.indexOf("第三段") + "第三段".length
                Selection.setSelection(structuredText, selectionStart, selectionEnd)
                assertTrue(structuredText.substring(selectionStart, selectionEnd).contains("列表二"))

                val process = activity.agentProcessNarrationRows(
                    listOf(
                        AgentTranscriptEntry(
                            id = "process-selection-1",
                            role = AgentTranscriptRole.PROCESS,
                            text = "第一段处理说明",
                            timestampMillis = 1L
                        ),
                        AgentTranscriptEntry(
                            id = "process-selection-2",
                            role = AgentTranscriptRole.PROCESS,
                            text = "第二段处理说明",
                            timestampMillis = 2L
                        )
                    )
                ) as ParagraphSelectingTextView
                assertEquals("第一段处理说明\n\n第二段处理说明", process.text.toString())
                Selection.setSelection(process.text as Spannable, 0, process.text.length)
                assertEquals(process.text.length, Selection.getSelectionEnd(process.text))
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun View.findDescendantParagraphTextView(): ParagraphSelectingTextView? {
        if (this is ParagraphSelectingTextView) return this
        if (this !is android.view.ViewGroup) return null
        for (index in 0 until childCount) {
            getChildAt(index).findDescendantParagraphTextView()?.let { return it }
        }
        return null
    }

    private fun View.findDescendantParagraphTextViews(): List<ParagraphSelectingTextView> = buildList {
        if (this@findDescendantParagraphTextViews is ParagraphSelectingTextView) {
            add(this@findDescendantParagraphTextViews)
        }
        if (this@findDescendantParagraphTextViews is android.view.ViewGroup) {
            for (index in 0 until childCount) {
                addAll(getChildAt(index).findDescendantParagraphTextViews())
            }
        }
    }
}
