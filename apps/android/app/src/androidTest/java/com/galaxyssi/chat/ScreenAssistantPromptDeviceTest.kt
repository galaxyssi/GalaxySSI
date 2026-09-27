package com.galaxyssi.chat

import android.content.Context
import android.graphics.Rect
import android.os.SystemClock
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.EditText
import android.widget.ImageButton
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ScreenAssistantPromptDeviceTest {
    @Test fun promptUsesNormalWindowAndAvoidsKeyboardAndSystemBars() = withPrompt { activity, _ ->
        val attrs = activity.window.attributes
        assertEquals(WindowManager.LayoutParams.TYPE_BASE_APPLICATION, attrs.type)
        assertEquals(Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, attrs.gravity)
        assertEquals(WindowInsets.Type.systemBars() or WindowInsets.Type.ime(), attrs.fitInsetsTypes)
        assertEquals(false, attrs.isFitInsetsIgnoringVisibility)
        assertNotNull(activity.findViewById<EditText>(android.R.id.edit))
    }

    @Test fun cancellingPromptNeverSubmitsScreenAnalysis() = withPrompt { activity, submitted ->
        InstrumentationRegistry.getInstrumentation().runOnMainSync { activity.onBackPressed() }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        assertEquals(0, submitted.get())
    }

    @Test fun blankDraftKeepsVisibleVoiceAndDisabledSend() = withPrompt { activity, submitted ->
        val voice = activity.findViewById<ImageButton>(R.id.screenPromptVoice)
        val send = activity.findViewById<ImageButton>(R.id.screenPromptSend)
        assertTrue(voice.isShown)
        assertFalse(send.isEnabled)
        InstrumentationRegistry.getInstrumentation().runOnMainSync { send.performClick() }
        assertEquals(0, submitted.get())
    }

    @Test fun multilineDraftKeepsSendAndVoiceVisibleAboveKeyboard() = withPrompt { activity, submitted ->
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            activity.findViewById<EditText>(android.R.id.edit).setText(
                (1..20).joinToString("\n") { "\u8bf7\u9605\u8bfb\u5f53\u524d\u9875\u9762\u5e76\u5206\u6790\u7b2c${it}\u6bb5\u5185\u5bb9\u3002" })
        }
        instrumentation.waitForIdleSync()
        SystemClock.sleep(600)
        instrumentation.runOnMainSync {
            val send = activity.findViewById<ImageButton>(R.id.screenPromptSend)
            val voice = activity.findViewById<ImageButton>(R.id.screenPromptVoice)
            val input = activity.findViewById<EditText>(android.R.id.edit)
            val sendBounds = Rect()
            val voiceBounds = Rect()
            assertTrue(send.getGlobalVisibleRect(sendBounds))
            assertTrue(voice.getGlobalVisibleRect(voiceBounds))
            assertEquals(send.height, sendBounds.height())
            assertEquals(voice.height, voiceBounds.height())
            assertTrue(send.isEnabled)
            assertTrue(input.height < input.lineHeight * input.lineCount)
            assertEquals(WindowManager.LayoutParams.WRAP_CONTENT, activity.window.attributes.height)
            send.performClick()
        }
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (submitted.get() == 0 && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(50)
        assertEquals(1, submitted.get())
    }

    @Test fun closeButtonDoesNotSubmitFilledDraft() = withPrompt { activity, submitted ->
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            activity.findViewById<EditText>(android.R.id.edit).setText("\u8bf7\u5206\u6790\u5f53\u524d\u5c4f\u5e55")
            activity.findViewById<ImageButton>(R.id.screenPromptCancel).performClick()
        }
        instrumentation.waitForIdleSync()
        assertEquals(0, submitted.get())
    }

    private fun withPrompt(test: (ScreenAssistantPromptActivity, AtomicInteger) -> Unit) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val monitor = instrumentation.addMonitor(ScreenAssistantPromptActivity::class.java.name, null, false)
        val submitted = AtomicInteger()
        try {
            instrumentation.runOnMainSync {
                ScreenAssistantPromptActivity.show(ApplicationProvider.getApplicationContext<Context>(),
                    R.string.screen_assistant_send) { submitted.incrementAndGet() }
            }
            val activity = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 5_000))
                as ScreenAssistantPromptActivity
            instrumentation.waitForIdleSync()
            test(activity, submitted)
        } finally {
            instrumentation.runOnMainSync { ScreenAssistantPromptActivity.dismissIfOpen() }
            instrumentation.waitForIdleSync()
            instrumentation.removeMonitor(monitor)
        }
    }
}
