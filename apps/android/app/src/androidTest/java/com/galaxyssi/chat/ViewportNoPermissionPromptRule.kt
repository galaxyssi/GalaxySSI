package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.content.IntentFilter
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.rules.TestWatcher
import org.junit.runner.Description

/** These synthetic viewport tests do not need notifications, a microphone, or any permission grant. */
class ViewportNoPermissionPromptRule : TestWatcher() {
    private var monitor: Instrumentation.ActivityMonitor? = null
    override fun starting(description: Description) {
        monitor = InstrumentationRegistry.getInstrumentation().addMonitor(IntentFilter("android.content.pm.action.REQUEST_PERMISSIONS"),
            Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null), true)
    }
    override fun finished(description: Description) {
        monitor?.let(InstrumentationRegistry.getInstrumentation()::removeMonitor)
    }
}
