package com.galaxyssi.chat

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DoorAccessActivityTest {
    @Test fun firstOpenShowsAccountAndPasswordWithoutSendingUnlock() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, DoorAccessActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as DoorAccessActivity
        instrumentation.waitForIdleSync()
        val labels = mutableListOf<String>()
        var inputCount = 0
        instrumentation.runOnMainSync {
            fun walk(view: View) {
                if (view is TextView) labels += view.text.toString()
                if (view is EditText) { inputCount++; labels += view.hint.toString() }
                if (view is ViewGroup) (0 until view.childCount).forEach { walk(view.getChildAt(it)) }
            }
            walk(activity.window.decorView)
        }
        assertEquals(2, inputCount)
        assertTrue(labels.contains(context.doorAccessText("account")))
        assertTrue(labels.contains(context.doorAccessText("login")))
        instrumentation.runOnMainSync { activity.finish() }
    }
}
