package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class HealthCameraUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun launch() = ActivityScenario.launch<HealthCameraActivity>(Intent(instrumentation.targetContext, HealthCameraActivity::class.java)
        .putExtra("capture_camera", false))
    @Test fun collectionPageOffersRealActionsWithoutStartingTheCameraOrShowingBottomTabs() {
        launch().use { scenario ->
            awaitPage(scenario)
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup
                assertEquals(7, root.childCount)
                val texture = descendants(root).filterIsInstance<TextureView>().single()
                assertEquals(View.GONE, (texture.parent as View).visibility)
                val all = descendants(root).filterIsInstance<TextView>().map { it.text.toString() }
                assertTrue(activity.getString(R.string.health_photo_start_recognition) in all)
                assertTrue(activity.getString(R.string.health_manual) in all)
                assertTrue(activity.getString(R.string.health_choose_images) in all)
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try { File(instrumentation.targetContext.getExternalFilesDir(null), "health-camera-draft-ui.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                } } finally { bitmap.recycle() }
            }
        }
    }
    @Test fun backgroundClearsPhotoViewsAndRecreationKeepsTheSameFilesOnlyMode() {
        launch().use { scenario ->
            awaitPage(scenario)
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup
                assertEquals(0, (root.getChildAt(3) as ViewGroup).childCount)
                assertEquals("", (root.getChildAt(6) as TextView).text.toString())
            }
            scenario.moveToState(Lifecycle.State.RESUMED); awaitPage(scenario)
            scenario.recreate(); awaitPage(scenario)
            scenario.onActivity { activity -> assertEquals(View.GONE, (descendants(activity.window.decorView).filterIsInstance<TextureView>().single().parent as View).visibility) }
        }
    }
    @Test fun manualFallbackReallyOpensTheNativeEditor() {
        val scenario = ActivityScenario.launch<HealthCenterActivity>(Intent(instrumentation.targetContext, HealthCenterActivity::class.java).putExtra("health_manual", true))
        scenario.use {
            val deadline = SystemClock.elapsedRealtime() + 10_000
            var ready = false
            do { it.onActivity { activity -> ready = descendants(activity.body).any { view -> view.tag == "health-field-systolic" } }
                if (!ready) SystemClock.sleep(50)
            } while (!ready && SystemClock.elapsedRealtime() < deadline)
            assertTrue(ready)
        }
    }
    private fun awaitPage(scenario: ActivityScenario<HealthCameraActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        do {
            var ready = false
            scenario.onActivity { activity -> ready = descendants(activity.window.decorView).filterIsInstance<TextView>()
                .any { it.text.toString() == activity.getString(R.string.health_photo_start_recognition) } }
            if (ready) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Native page collection did not load")
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
