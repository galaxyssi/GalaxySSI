package com.signalasi.chat

import android.app.Instrumentation
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class StartupHandoffDeviceTest {
    @Test
    fun launcherUsesStartupActivityAndForwardsExtrasToMain() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val launchIntent = requireNotNull(context.packageManager.getLaunchIntentForPackage(context.packageName))
        assertEquals(StartupActivity::class.java.name, launchIntent.component?.className)

        val marker = "startup-handoff-device-test"
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        val activity = try {
            context.startActivity(launchIntent.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                putExtra(EXTRA_MARKER, marker)
            })
            instrumentation.waitForMonitorWithTimeout(monitor, 20_000L) as? MainActivity
        } finally {
            instrumentation.removeMonitor(monitor)
        }

        assertNotNull("MainActivity was not opened by StartupActivity", activity)
        assertEquals(marker, activity?.intent?.getStringExtra(EXTRA_MARKER))
        activity?.finish()
    }

    private companion object {
        const val EXTRA_MARKER = "signalasi_startup_test_marker"
    }
}
