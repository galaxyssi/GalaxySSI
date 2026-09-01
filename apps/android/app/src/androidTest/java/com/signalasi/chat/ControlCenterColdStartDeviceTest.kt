package com.signalasi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ControlCenterColdStartDeviceTest {
    @Test
    fun immediateSettingsNavigationNeverInflatesLegacySettingsPage() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assertEquals(0, context.resources.getIdentifier("meProfileCard", "id", context.packageName))

        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            instrumentation.runOnMainSync { activity.showMainTab(PAGE_SETTINGS) }

            waitUntil("Dynamic control center did not replace its loading indicator") {
                var rendered = false
                instrumentation.runOnMainSync {
                    val content = activity.findViewById<LinearLayout>(R.id.settingsContent)
                    rendered = content.findViewById<View?>(R.id.settingsLoadingIndicator) == null &&
                        content.childCount > 1
                }
                rendered
            }
            instrumentation.waitForIdleSync()

            var title = ""
            var contentText = ""
            instrumentation.runOnMainSync {
                title = activity.findViewById<TextView>(R.id.mainTitle).text.toString()
                contentText = collectText(activity.findViewById(R.id.settingsContent))
            }
            assertEquals(
                context.getString(R.string.settings_control_center_title),
                title
            )
            assertTrue(
                contentText.contains(context.getString(R.string.settings_my_signalasi))
            )
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun collectText(view: View): String = buildString {
        if (view is TextView) append(view.text).append('\n')
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) append(collectText(view.getChildAt(index)))
        }
    }

    private fun waitUntil(message: String, timeoutMillis: Long = 15_000L, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        while (SystemClock.elapsedRealtime() < deadline) {
            if (condition()) return
            SystemClock.sleep(50L)
        }
        assertTrue(message, condition())
    }
}
