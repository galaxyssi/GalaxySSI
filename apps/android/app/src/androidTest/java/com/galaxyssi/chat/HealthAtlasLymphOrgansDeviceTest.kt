package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.SeekBar
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

class HealthAtlasLymphOrgansDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun Activity.open(id: String) {
        view(if (id.startsWith("cell-")) "atlas-tab-3" else "atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            var found = false
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (found) return
            SystemClock.sleep(50)
        }
        fail("Missing $key")
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun visibleText(text: String): Boolean {
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return false
        return root.packageName == context.packageName && root.findAccessibilityNodeInfosByText(text).isNotEmpty()
    }
    private fun awaitVisibleText(text: String) {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5_000
        while (SystemClock.elapsedRealtime() < deadline && !visibleText(text)) SystemClock.sleep(80)
        assertTrue("Missing visible text: $text", visibleText(text))
    }
    private fun capture(name: String, title: String) {
        awaitVisibleText(title)
        SystemClock.sleep(250)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(context.getExternalFilesDir(null), "body-atlas-lymph-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }


    @Test fun nineOrgansHaveTheirOwnSectionsLocalizedMarkersAndCanonicalLinks() {
        val en = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.ENGLISH) })
        val zh = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) })
        val atlas = HealthBodyAtlas.load(en)
        val all = HealthAtlasLymphOrgans.all
        assertEquals(9, all.size)
        assertEquals(9, all.map { it.drawable }.toSet().size)
        assertEquals(30, all.sumOf { it.features.size })
        for (plate in all) {
            val id = requireNotNull(plate.owner)
            val item = requireNotNull(atlas[id])
            assertSame(plate, HealthAtlasPlates.forId(id))
            assertEquals(id, item.mechanism)
            assertTrue(plate.markers.isNotEmpty())
            assertTrue(plate.markers.all { it.id in item.related && atlas[it.id] != null })
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                en.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                for (marker in plate.markers + plate.features.map { it.marker }) {
                    val x = (marker.x * 360f).roundToInt()
                    val y = (marker.y * 280f).roundToInt()
                    assertTrue("$id/${marker.id}", Color.alpha(bitmap.getPixel(x, y)) > 180)
                }
                val keys = listOf(plate.viewLabel) + plate.features.flatMap { listOf(it.title, it.explanation) }
                for (key in keys) {
                    assertTrue(zh.getString(key).any { it in '\u4e00'..'\u9fff' })
                    assertNotEquals(en.getString(key), zh.getString(key))
                }
            } finally { bitmap.recycle() }
        }
    }

    @Test fun everyOrganOpensFromTheDirectoryAndPlaysItsOwnDirectedLesson() = native { scenario ->
        for (plate in HealthAtlasLymphOrgans.all) scenario.onActivity { activity ->
            val id = requireNotNull(plate.owner)
            activity.open(id)
            val label = activity.view("atlas-art-caption") as TextView
            assertEquals(activity.getString(plate.viewLabel), label.text.toString())
            val link = plate.markers.first().id
            activity.view("atlas-hotspot-$link").performClick()
            assertNotSame(plate, HealthAtlasPlates.forId(link))
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-feature-${plate.features.first().marker.id}"))
            activity.openAtlasModelDetails()
            val diagram = activity.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            assertEquals(id, diagram.lesson.owner)
            assertNull(activity.window.decorView.tagged("atlas-simulation-art"))
            for (i in 0..3) {
                activity.view("atlas-process-stage-$i").performClick()
                val current = plate.features[diagram.lesson.stageFeatures[i]].title
                assertTrue(diagram.contentDescription.toString().startsWith(activity.getString(current)))
                assertEquals(i, diagram.stage)
            }
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-search"))
        }
    }

    @Test fun nodeShowsMovingLymphAndPreservesTheSelectedRouteAcrossResearchAndRecreation() = native { scenario ->
        scenario.onActivity {
            it.open("lymph-nodes"); it.openAtlasModelDetails()
            val diagram = it.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            diagram.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            diagram.layout(0, 0, diagram.measuredWidth, diagram.measuredHeight)
            fun frame() = Bitmap.createBitmap(diagram.width, diagram.height, Bitmap.Config.ARGB_8888).also {
                diagram.draw(Canvas(it))
            }
            val first = frame()
            it.view("atlas-process-stage-3").performClick()
            val last = frame()
            try { assertFalse(first.sameAs(last)) } finally { first.recycle(); last.recycle() }
            val atlas = HealthBodyAtlas.load(it)
            val state = HealthAtlasSimulation.initial("lymph-nodes").copy(phase = .75f)
            val lesson = it.getString(R.string.health_atlas_lymph_node_stage_3)
            val scope = it.getString(R.string.health_atlas_lymph_illustration_scope)
            val preview = HealthAtlasAgentContext.prompt(it, atlas, atlas["lymph-nodes"], simulation = state)
            assertTrue(preview.contains(lesson) && preview.contains(scope))
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas["heart"], simulation = state).contains(scope))
        }
        capture("node", scenario.localized(R.string.health_atlas_lymph_node_title))
        scenario.recreate(); ready(scenario, "atlas-section-diagram")
        scenario.onActivity {
            assertEquals(3, (it.view("atlas-section-diagram") as HealthAtlasSectionLessonView).stage)
            it.view("atlas-open-research").performClick()
            assertTrue(it.view("atlas-research-tab-drugs").isSelected)
            it.onBackPressed()
            assertEquals(3, (it.view("atlas-section-diagram") as HealthAtlasSectionLessonView).stage)
            assertNull(it.window.decorView.tagged("atlas-physiology-lymph-pressure"))
        }
    }

    @Test fun valveControlsAreScopedToTheCollectingVesselAndUpdateInPlace() = native { scenario ->
        scenario.onActivity {
            it.open("lymphatic-vessels"); it.openAtlasModelDetails()
            val pressure = it.view("atlas-physiology-lymph-pressure") as SeekBar
            val resistance = it.view("atlas-physiology-lymph-resistance") as SeekBar
            val scroller = it.view("atlas-scroll")
            val output = it.view("atlas-physiology-output") as TextView
            pressure.progress = 20
            assertEquals("0 mL/min", output.text.toString())
            val companion = it.view("atlas-physiology-companion") as TextView
            assertEquals(it.getString(R.string.health_atlas_lymph_valve_model_closed, HealthAtlasPhysiologyText.number(-.5)),
                companion.text.toString())
            pressure.progress = 60
            resistance.progress = 60
            assertEquals(HealthAtlasPhysiologyText.number(.25) + " mL/min", output.text.toString())
            assertSame(scroller, it.view("atlas-scroll"))
        }
        scenario.recreate(); ready(scenario, "atlas-physiology-lymph-pressure")
        scenario.onActivity {
            assertEquals(60, (it.view("atlas-physiology-lymph-resistance") as SeekBar).progress)
            it.onBackPressed(); it.open("thoracic-duct"); it.openAtlasModelDetails()
            assertNull(it.window.decorView.tagged("atlas-physiology-lymph-pressure"))
            assertEquals(0, (it.view("atlas-section-diagram") as HealthAtlasSectionLessonView).stage)
        }
    }
}
