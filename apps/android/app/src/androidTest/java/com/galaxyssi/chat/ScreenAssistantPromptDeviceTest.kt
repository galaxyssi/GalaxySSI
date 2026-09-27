package com.galaxyssi.chat

import android.content.Context
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.EditText
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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
