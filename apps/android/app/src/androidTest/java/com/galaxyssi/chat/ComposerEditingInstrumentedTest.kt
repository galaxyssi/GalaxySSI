package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.ViewConfiguration
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ComposerEditingInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private var insertionMenus = 0

    private fun bothInputs(block: (ComposerEditingTestActivity) -> Unit) {
        for (id in listOf(R.id.agentGoalInput, R.id.messageInput)) {
            val activity = instrumentation.startActivitySync(
                Intent(instrumentation.targetContext, ComposerEditingTestActivity::class.java)
                    .putExtra("input_id", id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ) as ComposerEditingTestActivity
            try {
                insertionMenus = 0
                main {
                    // Keep OEM remote smart-selection callbacks from outliving this short-lived test host.
                    activity.input.setTextClassifier(android.view.textclassifier.TextClassifier.NO_OP)
                    activity.input.customInsertionActionModeCallback = object : ActionMode.Callback {
                        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                            insertionMenus++
                            return true
                        }
                        override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = true
                        override fun onActionItemClicked(mode: ActionMode, item: MenuItem) = false
                        override fun onDestroyActionMode(mode: ActionMode) = Unit
                    }
                }
                instrumentation.waitForIdleSync()
                block(activity)
            } finally {
                main { activity.finish() }
                instrumentation.waitForIdleSync()
            }
        }
    }

    @Test fun firstBlankTapShowsNativeInsertionMenuWithoutSelectingText() = bothInputs { activity ->
        touch(activity, holdMillis = 50)
        main {
            assertTrue("First blank tap must open native edit actions", insertionMenus > 0)
            assertEquals(3, activity.input.selectionStart)
            assertEquals(3, activity.input.selectionEnd)
            assertEquals(0, activity.recordingStarts)
        }
    }

    @Test fun blankLongPressDoesNotExpandParagraphOrResetCursorAfterRelease() = bothInputs { activity ->
        touch(activity, holdMillis = ViewConfiguration.getLongPressTimeout() + 180L)
        main {
            assertEquals(3, activity.input.selectionStart)
            assertEquals(3, activity.input.selectionEnd)
            assertTrue(insertionMenus > 0)
            assertEquals(0, activity.recordingStarts)
        }
    }

    @Test fun blankTapOnSecondLinePreservesItsInsertionPosition() = bothInputs { activity ->
        main { activity.input.setText("first\n123\nlast"); activity.input.setSelection(9) }
        instrumentation.waitForIdleSync()
        touch(activity, line = 1, holdMillis = 50)
        main { assertEquals(9, activity.input.selectionStart); assertEquals(9, activity.input.selectionEnd) }
    }

    @Test fun emptyEditorOffersNativeActionsWithoutRecording() = bothInputs { activity ->
        main { activity.input.setText("") }
        touch(activity, holdMillis = 50)
        main {
            assertEquals(0, activity.input.selectionStart)
            assertEquals(0, activity.input.selectionEnd)
            assertEquals(0, activity.recordingStarts)
        }
    }

    @Test fun longPressOnTextStillSelectsParagraph() = bothInputs { activity ->
        main { activity.input.setText("first\nsecond paragraph\nlast"); activity.input.setSelection(10) }
        instrumentation.waitForIdleSync()
        touch(activity, line = 1, onText = true, holdMillis = ViewConfiguration.getLongPressTimeout() + 180L)
        main { assertEquals(6, activity.input.selectionStart); assertEquals(22, activity.input.selectionEnd) }
    }

    @Test fun cancelledBlankTapDoesNotShowMenu() = bothInputs { activity ->
        touch(activity, holdMillis = 50, cancelled = true)
        main { assertEquals(0, insertionMenus) }
    }

    @Test fun draggingBlankSpaceDoesNotBecomeTapMenu() = bothInputs { activity ->
        touch(activity, holdMillis = 50, drag = true)
        main { assertEquals(0, insertionMenus) }
    }

    @Test fun focusLossCancelsPendingParagraphExpansion() = bothInputs { activity ->
        val point = point(activity, line = 0, onText = true)
        val down = SystemClock.uptimeMillis()
        event(activity, down, MotionEvent.ACTION_DOWN, point)
        main { activity.input.clearFocus(); activity.input.setSelection(3) }
        SystemClock.sleep(ViewConfiguration.getLongPressTimeout() + 200L)
        event(activity, down, MotionEvent.ACTION_CANCEL, point)
        main { assertEquals(3, activity.input.selectionStart); assertEquals(3, activity.input.selectionEnd) }
    }

    @Test fun textModeLongPressNeverStartsVoiceRecording() = bothInputs { activity ->
        touch(activity, holdMillis = 900)
        main { assertTrue(activity.editing); assertEquals(0, activity.recordingStarts) }
    }

    @Test fun idleModeStillSupportsHoldToTalk() = bothInputs { activity ->
        main { activity.editing = false; activity.input.clearFocus() }
        touch(activity, holdMillis = 500, cancelled = true)
        main { assertEquals(1, activity.recordingStarts); assertEquals(0, insertionMenus) }
    }

    @Test fun idleShortTapEntersTextModeWithoutRecording() = bothInputs { activity ->
        main { activity.editing = false; activity.input.clearFocus() }
        touch(activity, holdMillis = 50)
        main { assertTrue(activity.editing); assertEquals(0, activity.recordingStarts) }
    }

    private fun touch(activity: ComposerEditingTestActivity, line: Int = 0, onText: Boolean = false,
        holdMillis: Long, cancelled: Boolean = false, drag: Boolean = false) {
        val point = point(activity, line, onText)
        val down = SystemClock.uptimeMillis()
        event(activity, down, MotionEvent.ACTION_DOWN, point)
        if (drag) event(activity, down, MotionEvent.ACTION_MOVE, point.first - 100 to point.second)
        SystemClock.sleep(holdMillis)
        event(activity, down, if (cancelled) MotionEvent.ACTION_CANCEL else MotionEvent.ACTION_UP,
            if (drag) point.first - 100 to point.second else point)
        instrumentation.waitForIdleSync()
        SystemClock.sleep(150)
    }

    private fun point(activity: ComposerEditingTestActivity, line: Int, onText: Boolean): Pair<Float, Float> {
        var point = 0f to 0f
        main {
            val input = activity.input
            val layout = requireNotNull(input.layout)
            val x = if (onText) input.totalPaddingLeft + layout.getPrimaryHorizontal(layout.getLineStart(line) + 2)
                else input.width - input.totalPaddingRight - 40f
            point = x to (input.totalPaddingTop + (layout.getLineTop(line) + layout.getLineBottom(line)) / 2f - input.scrollY)
        }
        return point
    }

    private fun event(activity: ComposerEditingTestActivity, down: Long, action: Int, point: Pair<Float, Float>) = main {
        val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, point.first, point.second, 0)
        try { activity.input.dispatchTouchEvent(event) } finally { event.recycle() }
    }

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)
}
