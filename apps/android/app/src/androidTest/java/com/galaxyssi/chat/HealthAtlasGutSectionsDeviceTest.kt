package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PathMeasure
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ScrollView
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

class HealthAtlasGutSectionsDeviceTest {
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
        try { File(context.getExternalFilesDir(null), "body-atlas-gut-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }



    @Test fun allExclusiveSectionsContainTheirLocalizedLandmarksAndTracks() {
        val en = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.ENGLISH) })
        val zh = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) })
        val data = HealthBodyAtlas.load(en)
        val all = HealthAtlasGutSections.all
        assertEquals(14, all.size)
        assertEquals(47, all.sumOf { it.features.size })
        assertEquals(29, all.sumOf { it.markers.size })
        assertEquals(14, all.map { it.drawable }.toSet().size)
        assertEquals(6, all.count { HealthAtlasSectionLesson.forId(it.owner)!!.tracks.isNotEmpty() })
        for (plate in all) {
            val owner = requireNotNull(plate.owner)
            val entry = requireNotNull(data[owner])
            val views = HealthAtlasPlates.viewsForId(owner)
            val detail = HealthAtlasRegionalDetailPlates.forId(owner)
            assertEquals(owner, views.first().owner)
            if (detail != null) assertSame(detail, views.first())
            if (owner == "appendix") assertEquals(R.drawable.health_atlas_appendix_plate, views.first().drawable)
            val section = views.single { it.drawable == plate.drawable }
            assertEquals(plate.viewLabel, section.viewLabel)
            assertEquals(plate.markers, section.markers)
            assertEquals(plate.features, section.features)
            assertEquals(section, HealthAtlasPlates.forId(owner, section.viewKey))
            assertEquals(owner, data.mechanism(entry).id)
            assertTrue(plate.markers.all { data[it.id] != null && it.id in entry.related })
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                en.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                for (marker in plate.markers + plate.features.map { it.marker })
                    assertTrue("$owner/${marker.id}", Color.alpha(bitmap.getPixel(
                        (marker.x * 360f).roundToInt(), (marker.y * 280f).roundToInt())) > 180)
                val point = FloatArray(2)
                for ((stage, track) in HealthAtlasSectionLesson.forId(owner)!!.tracks.withIndex()) {
                    val path = PathMeasure(track(), false)
                    assertTrue(path.length > 0)
                    for (sample in 0..16) {
                        assertTrue(path.getPosTan(path.length * sample / 16, point, null))
                        assertTrue("$owner stage $stage sample $sample", Color.alpha(bitmap.getPixel(
                            point[0].roundToInt(), point[1].roundToInt())) > 180)
                    }
                }
            } finally { bitmap.recycle() }
            for (key in listOf(plate.viewLabel) + plate.features.flatMap { listOf(it.title, it.explanation) }) {
                assertTrue(zh.getString(key).any { it in '\u4e00'..'\u9fff' })
                assertNotEquals(en.getString(key), zh.getString(key))
            }
        }
    }

    @Test fun eachDirectoryEntryOpensItsOwnDiagramAndOwnFunctionAndReturnsThroughLinks() = native { scenario ->
        for (plate in HealthAtlasGutSections.all) scenario.onActivity { activity ->
            val id = requireNotNull(plate.owner)
            activity.open(id)
            val views = HealthAtlasPlates.viewsForId(id)
            assertEquals(id, views.first().owner)
            assertEquals(activity.getString(views.first().viewLabel),
                (activity.view("atlas-art-caption") as TextView).text.toString())
            val sectionIndex = views.indexOfFirst { it.drawable == plate.drawable }
            assertTrue("Missing section view for $id", sectionIndex >= 0)
            if (sectionIndex > 0) activity.view("atlas-view-$sectionIndex").performClick()
            assertEquals(activity.getString(plate.viewLabel), (activity.view("atlas-art-caption") as TextView).text.toString())
            plate.markers.firstOrNull()?.let { marker ->
                activity.view("atlas-hotspot-${marker.id}").performClick()
                activity.onBackPressed()
                assertEquals(activity.getString(plate.viewLabel), (activity.view("atlas-art-caption") as TextView).text.toString())
            }
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-open-research"))
            activity.openAtlasModelDetails()
            val diagram = activity.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            assertEquals(id, diagram.lesson.owner)
            assertNull(activity.window.decorView.tagged("atlas-simulation-art"))
            activity.view("atlas-process-stage-2").performClick()
            assertEquals(2, diagram.stage)
            val prefix = plate.features[diagram.lesson.stageFeatures[2]].title
            assertTrue(diagram.contentDescription.toString().startsWith(activity.getString(prefix)))
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-search"))
        }
    }

    @Test fun esophagusMotionAndResearchRestoreTheSameAnatomy() = native { scenario ->
        scenario.onActivity {
            it.open("esophagus"); it.openAtlasModelDetails()
            val view = it.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            view.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            view.layout(0, 0, view.measuredWidth, view.measuredHeight)
            fun frame() = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also {
                view.draw(Canvas(it))
            }
            val start = frame()
            view.phase = .17f
            val moved = frame()
            try { assertFalse(start.sameAs(moved)) } finally { start.recycle(); moved.recycle() }
            it.view("atlas-process-stage-3").performClick()
            assertEquals(3, view.stage)
            val atlas = HealthBodyAtlas.load(it)
            val state = HealthAtlasSimulation.initial("esophagus").copy(phase = .75f)
            val note = it.getString(R.string.health_atlas_gut_section_motion_scope)
            val preview = HealthAtlasAgentContext.prompt(it, atlas, atlas["esophagus"], simulation = state)
            assertTrue(preview.contains(note) && preview.contains(it.getString(R.string.health_atlas_gut_section_esophagus_stage_3)))
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas["lymph-nodes"], simulation = state).contains(note))
        }
        capture("esophagus", scenario.localized(R.string.health_atlas_gut_section_esophagus_title))
        scenario.recreate(); ready(scenario, "atlas-section-diagram")
        scenario.onActivity {
            assertEquals(3, (it.view("atlas-section-diagram") as HealthAtlasSectionLessonView).stage)
            it.view("atlas-open-research").performClick()
            assertEquals(3, (it.view("atlas-section-diagram") as HealthAtlasSectionLessonView).stage)
        }
    }

    @Test fun villusGeometryRespondsToSlidersAndDoesNotLeakToOtherEntries() = native { scenario ->
        scenario.onActivity {
            it.open("jejunum"); it.openAtlasModelDetails()
            val scroller = it.view("atlas-scroll")
            val geometry = it.view("atlas-villus-geometry") as HealthAtlasVillusAreaView
            val density = it.view("atlas-physiology-villus-density") as SeekBar
            val radius = it.view("atlas-physiology-villus-radius") as SeekBar
            val height = it.view("atlas-physiology-villus-height") as SeekBar
            density.progress = 0
            assertEquals("1 \u00d7", (it.view("atlas-physiology-output") as TextView).text.toString())
            assertEquals(0, geometry.model.inputs[0])
            density.progress = 24; radius.progress = 45; height.progress = 100
            val expected = HealthAtlasPhysiologyText.number(1 + 24 * 2 * Math.PI * .07 * 1.2)
            assertEquals("$expected \u00d7", (it.view("atlas-physiology-output") as TextView).text.toString())
            assertEquals(listOf(24, 70, 120), geometry.model.inputs)
            assertSame(geometry, it.view("atlas-villus-geometry"))
            assertSame(scroller, it.view("atlas-scroll"))
        }
        instrumentation.waitForIdleSync()
        scenario.onActivity {
            val scroll = it.view("atlas-scroll") as ScrollView
            val output = it.view("atlas-physiology-output")
            val position = Rect(0, 0, output.width, output.height)
            scroll.offsetDescendantRectToMyCoords(output, position)
            scroll.scrollTo(0, position.top - HealthCenterViews(it).dp(96))
        }
        capture("villus", scenario.localized(R.string.health_atlas_gut_section_area_views))
        scenario.recreate(); ready(scenario, "atlas-villus-geometry")
        scenario.onActivity {
            assertEquals(listOf(24, 70, 120), (it.view("atlas-villus-geometry") as HealthAtlasVillusAreaView).model.inputs)
            it.onBackPressed(); it.open("small-intestine"); it.openAtlasModelDetails()
            assertEquals(listOf(12, 45, 60), (it.view("atlas-villus-geometry") as HealthAtlasVillusAreaView).model.inputs)
            it.onBackPressed(); it.open("colon"); it.openAtlasModelDetails()
            assertNull(it.window.decorView.tagged("atlas-villus-geometry"))
            assertNull(it.window.decorView.tagged("atlas-physiology-villus-density"))
        }
    }
}
