package com.galaxyssi.watch

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class WatchSkillImportUiTest {
    @Test fun importOpensPhoneReceiverWithoutChangingInstalledSkills() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val before = WatchSkillManager(context).activeConfiguration()?.json
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("open_skills", true)) as MainActivity
        val monitor = instrumentation.addMonitor(WatchPhoneSetupActivity::class.java.name, null, false)
        var receiver: WatchPhoneSetupActivity? = null
        try {
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                descendants(activity.window.decorView).filterIsInstance<Button>()
                    .first { it.text == context.getString(R.string.skills_import) }.performClick()
            }
            receiver = instrumentation.waitForMonitorWithTimeout(monitor, 15000) as? WatchPhoneSetupActivity
            assertNotNull("Import must open the app's phone receiver", receiver)
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                assertTrue(descendants(receiver!!.window.decorView).filterIsInstance<TextView>()
                    .any { it.text == context.getString(R.string.skills_phone_title) })
            }
            assertEquals(before, WatchSkillManager(context).activeConfiguration()?.json)
        } finally {
            instrumentation.removeMonitor(monitor)
            instrumentation.runOnMainSync { receiver?.finish(); activity.finish() }
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
