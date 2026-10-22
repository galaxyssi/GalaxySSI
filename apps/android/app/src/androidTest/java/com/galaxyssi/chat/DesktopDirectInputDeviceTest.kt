package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.inputmethod.EditorInfo
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DesktopDirectInputDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun chineseCompositionCommitsExactlyOnce() = instrumentation.runOnMainSync {
        val output = mutableListOf<String>()
        val view = DesktopImeView(context).apply { onCommit = { output.add(it) } }
        val connection = view.onCreateInputConnection(EditorInfo())
        connection.setComposingText("n", 1); connection.setComposingText("ni", 1)
        assertTrue(output.isEmpty())
        connection.commitText("\u4f60\u597d", 1); connection.finishComposingText()
        connection.commitText(" ", 1)
        assertEquals(listOf("\u4f60\u597d", " "), output)
    }

    @Test fun hidingKeyboardDoesNotSendUnfinishedComposition() = instrumentation.runOnMainSync {
        val output = mutableListOf<String>()
        val view = DesktopImeView(context).apply { onCommit = { output.add(it) } }
        val connection = view.onCreateInputConnection(EditorInfo())
        connection.setComposingText("unfinished", 1)
        view.discardComposition(); connection.finishComposingText()
        assertTrue(output.isEmpty())
    }

    @Test fun deleteAndEnterAreRemoteKeysNotInsertedControlCharacters() = instrumentation.runOnMainSync {
        val output = mutableListOf<String>()
        val view = DesktopImeView(context).apply { onKey = { output.add(it) } }
        val connection = view.onCreateInputConnection(EditorInfo())
        connection.deleteSurroundingText(2, 1); connection.performEditorAction(EditorInfo.IME_ACTION_DONE)
        assertEquals(listOf("backspace", "backspace", "delete", "enter"), output)
    }

    @Test fun longPressDoesNotFirstSendLeftClick() {
        val calls = java.util.concurrent.CopyOnWriteArrayList<String>()
        lateinit var view: DesktopRemoteScreenView
        val bitmap = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
        val down = SystemClock.uptimeMillis()
        instrumentation.runOnMainSync {
            view = DesktopRemoteScreenView(context).apply {
                layout(0, 0, 400, 400); setScreenshot(bitmap)
                onImageTap = { _, _ -> calls.add("left") }
                onImageLongPress = { _, _ -> calls.add("right") }
            }
            event(view, down, down, MotionEvent.ACTION_DOWN)
        }
        Thread.sleep(ViewConfiguration.getLongPressTimeout() + 150L)
        instrumentation.runOnMainSync { event(view, down, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP) }
        Thread.sleep(ViewConfiguration.getDoubleTapTimeout() + 80L)
        assertEquals(listOf("right"), calls)
        instrumentation.runOnMainSync { view.clearScreenshot(); bitmap.recycle() }
    }

    @Test fun doubleTapIsOneDoubleClickWithoutExtraSingleClick() {
        val calls = java.util.concurrent.CopyOnWriteArrayList<String>()
        lateinit var view: DesktopRemoteScreenView
        val bitmap = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
        instrumentation.runOnMainSync {
            view = DesktopRemoteScreenView(context).apply {
                layout(0, 0, 400, 400); setScreenshot(bitmap)
                onImageTap = { _, _ -> calls.add("single") }
                onImageDoubleTap = { _, _ -> calls.add("double") }
            }
            val now = SystemClock.uptimeMillis()
            event(view, now, now, MotionEvent.ACTION_DOWN)
            event(view, now, now + 20, MotionEvent.ACTION_UP)
            event(view, now + 100, now + 100, MotionEvent.ACTION_DOWN)
            event(view, now + 100, now + 120, MotionEvent.ACTION_UP)
        }
        Thread.sleep(ViewConfiguration.getDoubleTapTimeout() + 150L)
        assertEquals(listOf("double"), calls)
        instrumentation.runOnMainSync { view.clearScreenshot(); bitmap.recycle() }
    }

    private fun event(view: DesktopRemoteScreenView, down: Long, time: Long, action: Int) {
        MotionEvent.obtain(down, time, action, 200f, 200f, 0).let {
            view.onTouchEvent(it); it.recycle()
        }
    }
}
