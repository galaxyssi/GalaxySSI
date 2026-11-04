package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthImportUiDeviceTest {
    @Test fun progressUpdatesRetainAllExistingChildrenAndDoNotReplaceTheTaskView() {
        ActivityScenario.launch(HealthCaptureActivity::class.java).use { scenario -> scenario.onActivity { context ->
            val ui = HealthCenterViews(context)
            val view = HealthImportTaskView(context, ui, {}, {}, {}, {})
            val job = HealthImportJob(UUID.randomUUID().toString(), "content://test/source", 1,
                name = "test.pdf", totalBytes = 1_000_000, state = HealthImportState.COPYING)
            view.bind(job, "1%"); val children = descendants(view)
            repeat(100) { view.bind(job.copy(copiedBytes = it * 10_000L), "$it%") }
            val after = descendants(view)
            assertEquals(children.size, after.size)
            children.indices.forEach { assertSame(children[it], after[it]) }
        } }
    }
    @Test fun nativeImportPageClearsItsDecryptedViewsInBackgroundAndRestoresWithoutBottomTabs() {
        ActivityScenario.launch(HealthCaptureActivity::class.java).use { scenario ->
            awaitCapture(scenario)
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as LinearLayout
                assertEquals(2, root.childCount)
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as LinearLayout
                assertEquals(0, (root.getChildAt(1) as ViewGroup).childCount)
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            awaitCapture(scenario)
            scenario.recreate()
            awaitCapture(scenario)
        }
    }
    private fun awaitCapture(scenario: ActivityScenario<HealthCaptureActivity>) {
        val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
        do {
            var ready = false
            scenario.onActivity { activity -> ready = descendants(activity.window.decorView).filterIsInstance<android.widget.TextView>()
                .any { it.text.toString() == activity.getString(R.string.health_take_photo) } }
            if (ready) return
            android.os.SystemClock.sleep(50)
        } while (android.os.SystemClock.elapsedRealtime() < deadline)
        fail("The native health import page did not finish loading")
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
