package com.galaxyssi.chat

import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Rect
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

internal fun ActivityScenario<HealthBodyAtlasActivity>.openAtlasRelatedLesson(id: String) {
    val runner = InstrumentationRegistry.getInstrumentation()
    runner.waitForIdleSync()
    lateinit var heading: String
    lateinit var label: String
    lateinit var targetName: String
    lateinit var targetStory: HealthAtlasFunctionStory
    lateinit var originalPlayer: HealthAtlasFunctionPlayer
    lateinit var button: View
    onActivity { activity ->
        val root = activity.window.decorView
        assertNull(root.findViewWithTag<View>("atlas-related-lesson-$id"))
        val player = requireNotNull(root.findViewWithTag<HealthAtlasFunctionPlayer>("atlas-function-player"))
        val (_, story) = player.story.relatedLessons.single { it.first == id }
        val target = requireNotNull(HealthBodyAtlas.load(activity)[id])
        originalPlayer = player
        targetStory = story
        targetName = target.name
        heading = activity.getString(R.string.health_atlas_related_lessons)
        label = activity.getString(R.string.health_atlas_related_lesson_label, target.name, activity.getString(story.title))
        button = requireNotNull(root.findViewWithTag("atlas-function-menu"))
        button.requestRectangleOnScreen(Rect(0, 0, button.width, button.height), true)
    }
    runner.waitForIdleSync()
    onActivity {
        assertTrue("Animation options button is outside the visible scroll area",
            button.getGlobalVisibleRect(Rect()))
        assertTrue(button.performClick())
    }
    val automation = runner.uiAutomation
    val service = automation.serviceInfo
    val originalFlags = service.flags
    service.flags = originalFlags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
    automation.serviceInfo = service
    fun click(text: String) {
        val deadline = SystemClock.elapsedRealtime() + 4_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            val roots = automation.windows.mapNotNull { it.root } + listOfNotNull(automation.rootInActiveWindow)
            val bounds = roots.asSequence().filter { it.packageName?.toString() == runner.targetContext.packageName }
                .flatMap { it.findAccessibilityNodeInfosByText(text).asSequence() }
                .filter { it.isVisibleToUser && it.text?.toString() == text }
                .map { node -> Rect().also(node::getBoundsInScreen) }
                .firstOrNull { !it.isEmpty }
            if (bounds != null) {
                // PopupMenu rows receive taps through the list, not through the label TextView.
                val downTime = SystemClock.uptimeMillis()
                for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
                    val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action,
                        bounds.exactCenterX(), bounds.exactCenterY(), 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
                    try { assertTrue(automation.injectInputEvent(event, true)) } finally { event.recycle() }
                }
                return
            }
            SystemClock.sleep(40)
        }
        throw AssertionError("Could not open atlas menu item: $text")
    }
    try {
        click(heading)
        click(label)
        val deadline = SystemClock.elapsedRealtime() + 4_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            var arrived = false
            onActivity { activity ->
                val root = activity.window.decorView
                val player = root.findViewWithTag<HealthAtlasFunctionPlayer>("atlas-function-player")
                val title = root.findViewWithTag<TextView>("health-page-title")?.text?.toString()
                arrived = player !== originalPlayer && player?.story == targetStory && title == targetName
            }
            if (arrived) return
            SystemClock.sleep(40)
        }
        throw AssertionError("Related animation did not open: $label")
    } finally {
        service.flags = originalFlags
        automation.serviceInfo = service
    }
}
