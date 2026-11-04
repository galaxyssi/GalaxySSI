package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.text.NumberFormat
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthBodyExplorationDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    private fun native(block: (ActivityScenario<HealthBodyExplorationActivity>) -> Unit) {
        assumeFalse("Native body exploration needs an unlocked screen",
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        ActivityScenario.launch(HealthBodyExplorationActivity::class.java).use(block)
    }

    private fun View.findTag(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).findTag(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.findTag(key)) { "Missing native control: $key" }
    private fun Activity.label(key: String) = (view(key) as TextView).text.toString()

    private fun <T : Any> await(read: () -> T?): T {
        val deadline = SystemClock.elapsedRealtime() + 12_000
        do {
            read()?.let { return it }
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        error("Timed out waiting for the native body exploration state")
    }

    @Test fun allSystemsHaveFourReadableLayersAndValidDirectedLessons() {
        for (topic in HealthBodyTopic.entries) {
            val info = HealthBodyLessons.info(topic)
            assertEquals(4, info.layers.size)
            assertEquals(4, info.layers.distinct().size)
            info.layers.forEach { assertTrue(context.getString(it).length > 10) }
            val lesson = info.lesson
            assertTrue(lesson.url.startsWith("https://"))
            assertTrue(lesson.steps.all { it.from != it.to && it.from in lesson.nodes.indices && it.to in lesson.nodes.indices })
            lesson.steps.forEach { assertTrue(context.getString(it.detail).length > 10) }
        }
        val organ = HealthBodyLessons.lesson(HealthBodyTopic.CIRCULATION, HealthBodyLayer.ORGAN)
        val molecule = HealthBodyLessons.lesson(HealthBodyTopic.CIRCULATION, HealthBodyLayer.MOLECULE)
        assertEquals(listOf(0 to 1, 1 to 2, 2 to 3, 3 to 0), organ.steps.map { it.from to it.to })
        assertEquals(R.string.health_body_oxygen_title, molecule.title)
        assertEquals(2, molecule.steps.size)
    }

    @Test fun timelineClampsAndTheFictionalPumpUsesTheExpectedUnits() {
        assertEquals(HealthBodyFrame(0, 0f), HealthBodyTimeline.frame(Float.NaN, 4))
        assertEquals(HealthBodyFrame(0, 0f), HealthBodyTimeline.frame(-4f, 4))
        assertEquals(HealthBodyFrame(2, .75f), HealthBodyTimeline.frame(2.75f, 4))
        assertEquals(HealthBodyFrame(3, 1f), HealthBodyTimeline.frame(5f, 4))
        assertEquals(3.25f, HealthBodyTimeline.jump(3.75f, 4, 1), 0f)
        assertEquals(0.25f, HealthBodyTimeline.jump(0f, 4, -1), 0f)
        assertEquals(HealthBodyTimeline.duration(4, false) * 2, HealthBodyTimeline.duration(4, true))
        assertEquals(4500, HealthBodyPumpExperiment().outputMlPerMinute)
        assertEquals(800, HealthBodyPumpExperiment(40, 20).outputMlPerMinute)
        assertEquals(16800, HealthBodyPumpExperiment(140, 120).outputMlPerMinute)
        assertTrue(runCatching { HealthBodyPumpExperiment(0, 60) }.isFailure)
    }

    @Test fun overviewUsesTheProvidedIllustrationAndChangesLayerAndTopicWithoutLeaving() = native { scenario ->
        scenario.onActivity { activity ->
            val art = activity.view("health-body-illustration") as ImageView
            assertNotNull(art.drawable)
            assertTrue(art.drawable.intrinsicHeight > art.drawable.intrinsicWidth)
            assertTrue(activity.view("health-body-layer-ORGAN").isSelected)
            assertEquals(activity.getString(R.string.health_body_circ_title), activity.label("health-body-lesson-title"))
            activity.view("health-body-topic-BREATHING").performClick()
            assertEquals(activity.getString(R.string.health_body_breath_title), activity.label("health-body-lesson-title"))
            activity.view("health-body-layer-MOLECULE").performClick()
            assertTrue(activity.view("health-body-layer-MOLECULE").isSelected)
            assertEquals(activity.getString(R.string.health_body_oxygen_title), activity.label("health-body-lesson-title"))
            assertEquals(activity.getString(R.string.health_body_breath_molecule), activity.label("health-body-insight"))
        }
        scenario.recreate()
        scenario.onActivity {
            assertTrue(it.view("health-body-topic-BREATHING").isSelected)
            assertTrue(it.view("health-body-layer-MOLECULE").isSelected)
        }
    }

    @Test fun moreMenuOpensARealAdditionalLesson() = native { scenario ->
        scenario.onActivity { assertTrue(it.view("health-body-more").performClick()) }
        val title = context.getString(R.string.health_body_kidneys)
        val option = await {
            instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(title)
                ?.firstOrNull { it.text?.toString() == title && it.isClickable }
        }
        assertTrue(option.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        scenario.onActivity {
            assertEquals(it.getString(R.string.health_body_kidney_title), it.label("health-body-lesson-title"))
            assertTrue(it.view("health-body-more").isSelected)
            assertTrue(it.view("health-body-preview").performClick())
            assertNotNull(it.view("health-body-diagram"))
            assertTrue(it.label("health-body-phase").contains(it.getString(R.string.health_body_kidney_s1)))
        }
    }

    @Test fun animationChangesCanvasPixelsCanPauseAndStopsInBackground() = native { scenario ->
        scenario.onActivity { assertTrue(it.view("health-body-preview").performClick()) }
        await {
            var ready = false
            scenario.onActivity { ready = it.view("health-body-diagram").width > 0 }
            true.takeIf { ready }
        }
        var first: Bitmap? = null
        var second: Bitmap? = null
        var base = 0f
        val motion = ValueAnimator.areAnimatorsEnabled()
        fun draw(view: View) = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
        try {
            scenario.onActivity {
                val view = it.view("health-body-diagram") as HealthBodyDiagram
                base = view.position
                first = draw(view)
                if (!motion) it.view("health-body-next").performClick()
            }
            if (motion) await {
                var moved = false
                scenario.onActivity { moved = (it.view("health-body-diagram") as HealthBodyDiagram).position > base + .16f }
                true.takeIf { moved }
            }
            scenario.onActivity {
                val view = it.view("health-body-diagram") as HealthBodyDiagram
                second = draw(view)
                if (motion) {
                    assertEquals(it.getString(R.string.health_body_pause), it.view("health-body-play").contentDescription)
                    assertTrue(it.view("health-body-play").performClick())
                }
                base = view.position
            }
            assertFalse(requireNotNull(first).sameAs(requireNotNull(second)))
            SystemClock.sleep(250)
            scenario.onActivity {
                assertEquals(base, (it.view("health-body-diagram") as HealthBodyDiagram).position, 0f)
                if (motion) it.view("health-body-play").performClick()
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            var hiddenPosition = 0f
            scenario.onActivity { hiddenPosition = (it.view("health-body-diagram") as HealthBodyDiagram).position }
            SystemClock.sleep(250)
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity {
                assertEquals(hiddenPosition, (it.view("health-body-diagram") as HealthBodyDiagram).position, 0f)
                assertTrue(it.view("health-body-play").contentDescription != it.getString(R.string.health_body_pause))
            }
        } finally { first?.recycle(); second?.recycle() }
    }

    @Test fun experimentUsesItsOwnInputsAndReturnsToTheLesson() = native { scenario ->
        fun expected(activity: Activity, value: Double) = activity.getString(R.string.health_body_output,
            NumberFormat.getNumberInstance().apply { minimumFractionDigits = 2; maximumFractionDigits = 2 }.format(value))
        scenario.onActivity {
            it.view("health-body-preview").performClick()
            assertTrue(it.view("health-body-experiment").performClick())
            assertEquals(expected(it, 4.50), it.label("health-body-output"))
            (it.view("health-body-beats") as SeekBar).progress = 80 - HealthBodyPumpExperiment.BEATS.first
            (it.view("health-body-stroke") as SeekBar).progress = 80 - HealthBodyPumpExperiment.STROKE_ML.first
            assertEquals(expected(it, 6.40), it.label("health-body-output"))
            it.view("health-body-experiment-reset").performClick()
            assertEquals(expected(it, 4.50), it.label("health-body-output"))
            it.onBackPressed()
            assertNotNull(it.view("health-body-diagram"))
        }
    }

    @Test fun personalTrendIsOnlyOpenedByTheSeparateCommand() = native { scenario ->
        val monitor = instrumentation.addMonitor(HealthTrendActivity::class.java.name,
            Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null), true)
        try {
            scenario.onActivity {
                assertTrue(it.view("health-body-reference").performClick())
                assertNotNull(it.view("health-body-source"))
                assertEquals(0, monitor.hits)
                assertTrue(it.view("health-body-open-bp").performClick())
                assertEquals(1, monitor.hits)
            }
        } finally { instrumentation.removeMonitor(monitor) }
    }
}
