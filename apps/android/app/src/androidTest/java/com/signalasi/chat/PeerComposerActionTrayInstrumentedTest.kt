package com.signalasi.chat

import android.content.Intent
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PeerComposerActionTrayInstrumentedTest {
    @Test
    fun actionTrayMatchesAgentComposerAndClosesBeforeNavigation() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        val launchIntent = instrumentation.targetContext.packageManager
            .getLaunchIntentForPackage(instrumentation.targetContext.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            ?: error("SignalASI launcher intent unavailable")
        instrumentation.targetContext.startActivity(launchIntent)
        val activity = instrumentation.waitForMonitorWithTimeout(monitor, 15_000L) as? MainActivity
            ?: error("SignalASI MainActivity did not start")

        try {
            instrumentation.runOnMainSync {
                assertEquals(View.GONE, activity.chatActionTray.visibility)

                activity.enterChatComposerTextMode()
                assertEquals(View.VISIBLE, activity.imageButton.visibility)

                activity.setChatActionTrayExpanded(true)
                assertFalse(activity.chatComposerTextMode)
                assertEquals(View.VISIBLE, activity.chatActionTray.visibility)
                assertEquals(45f, activity.imageButton.rotation)
                listOf(
                    R.id.chatActionNewSession,
                    R.id.chatActionSessions,
                    R.id.chatActionScan,
                    R.id.chatActionCamera,
                    R.id.chatActionAddFile
                ).forEach { id ->
                    assertTrue(activity.findViewById<View>(id).isClickable)
                }

                activity.onBackPressed()
                assertEquals(View.GONE, activity.chatActionTray.visibility)
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
            instrumentation.removeMonitor(monitor)
        }
    }
}
