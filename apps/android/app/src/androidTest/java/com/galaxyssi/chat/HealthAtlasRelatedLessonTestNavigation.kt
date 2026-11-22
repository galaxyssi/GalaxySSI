package com.galaxyssi.chat

import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

internal fun ActivityScenario<HealthBodyAtlasActivity>.openAtlasRelatedLesson(id: String) {
    lateinit var heading: String
    lateinit var label: String
    lateinit var button: View
    onActivity { activity ->
        val root = activity.window.decorView
        assertNull(root.findViewWithTag<View>("atlas-related-lesson-$id"))
        val player = requireNotNull(root.findViewWithTag<HealthAtlasFunctionPlayer>("atlas-function-player"))
        val (_, story) = player.story.relatedLessons.single { it.first == id }
        val target = requireNotNull(HealthBodyAtlas.load(activity)[id])
        heading = activity.getString(R.string.health_atlas_related_lessons)
        label = activity.getString(R.string.health_atlas_related_lesson_label, target.name, activity.getString(story.title))
        button = requireNotNull(root.findViewWithTag("atlas-function-menu"))
        button.requestRectangleOnScreen(Rect(0, 0, button.width, button.height), true)
    }
    val runner = InstrumentationRegistry.getInstrumentation()
    runner.waitForIdleSync()
    onActivity { assertTrue(button.performClick()) }
    fun click(text: String) {
        val deadline = SystemClock.elapsedRealtime() + 4_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = runner.uiAutomation.rootInActiveWindow
            val textNode = root?.findAccessibilityNodeInfosByText(text)
                ?.firstOrNull { it.isVisibleToUser && it.text?.toString() == text }
            var node = textNode
            while (node != null && node.isVisibleToUser) {
                if (node.isClickable && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return
                node = node.parent
            }
            SystemClock.sleep(40)
        }
        throw AssertionError("Could not open atlas menu item: $text")
    }
    click(heading)
    click(label)
    runner.waitForIdleSync()
}
