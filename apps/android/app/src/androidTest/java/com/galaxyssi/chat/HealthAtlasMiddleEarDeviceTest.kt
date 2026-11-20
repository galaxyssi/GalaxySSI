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
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.EditText
import android.widget.SeekBar
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasMiddleEarDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val kind = HealthAtlasPhysiologyKind.MIDDLE_EAR
    private val parts = listOf("external-ear", "middle-ear", "inner-ear", "cochlea", "vestibular-apparatus")

    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(tag: String) = requireNotNull(window.decorView.tagged(tag)) { tag }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        while (SystemClock.elapsedRealtime() < deadline) {
            var found = false
            scenario.onActivity { found = it.window.decorView.tagged(tag) != null }
            if (found) return
            SystemClock.sleep(40)
        }
        fail(tag)
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(fixture)).use { ready(it, "atlas-whole-art"); block(it) }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }
    private fun Activity.openEar() {
        view("atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText("ear")
        view("atlas-entry-ear").performClick()
    }
    private fun Activity.adjust(values: List<Int>) = values.forEachIndexed { index, number ->
        val spec = kind.inputs[index]
        (view("atlas-physiology-${spec.key}") as SeekBar).progress = number - spec.range.first
    }
    private fun Activity.transformer() = view("atlas-middle-ear-model") as HealthAtlasMiddleEarView

    private fun nodes(text: String): List<AccessibilityNodeInfo> {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 6000
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName) {
                val matches = root.findAccessibilityNodeInfosByText(text)
                if (matches.isNotEmpty()) return matches
            }
            SystemClock.sleep(40)
        }
        error("Missing accessibility text: $text")
    }
    private fun capture(name: String, expected: String) {
        nodes(expected)
        SystemClock.sleep(350)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(context.getExternalFilesDir(null), "body-atlas-ear-$name.png").outputStream().use {
                image.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { image.recycle() }
    }

    @Test fun allFiveHotspotsKeepTheCorrectAnatomyAndSixProcessesOwnTheirStages() = native { scenario ->
        scenario.onActivity { it.openEar() }
        capture("structure", context.getString(R.string.health_atlas_view_ear_section))
        val atlas = HealthBodyAtlas.load(context)
        val plate = requireNotNull(HealthAtlasPlates.forId("ear"))
        assertEquals(parts.toSet(), plate.markers.map { it.id }.toSet())
        assertEquals(HealthAtlasMiddleEar.ANATOMY_SOURCE, plate.source)
        scenario.onActivity { activity ->
            for (id in listOf("ear") + parts) {
                if (id != "ear") {
                    activity.view("atlas-hotspot-$id").performClick()
                    assertTrue(activity.view("atlas-hotspot-$id").isSelected)
                }
                assertEquals(atlas[id]!!.name, (activity.view("health-page-title") as TextView).text.toString())
                activity.view("atlas-tab-3").performClick()
                activity.view("atlas-process-stage-2").performClick()
                assertTrue(activity.view("atlas-process-stage-2").isSelected)
                val stage = (activity.view("atlas-simulation-stage") as TextView).text
                assertTrue(stage.contains(atlas.mechanism(atlas[id]!!).stages[2]))
                assertEquals(id in setOf("ear", "middle-ear"), activity.window.decorView.tagged("atlas-middle-ear-model") != null)
                if (id == "ear") activity.view("atlas-tab-0").performClick() else activity.onBackPressed()
            }
            activity.view("atlas-fullscreen").performClick()
        }
        assertTrue(nodes(context.getString(R.string.health_atlas_view_ear_section)).any {
            it.className?.toString() == "android.widget.ImageView" && it.isVisibleToUser
        })
    }

    @Test fun controlsUpdateLocallyAndRestoreAcrossRecreationAndResearch() = native { scenario ->
        val values = listOf(64, 40, 140)
        scenario.onActivity {
            it.openEar(); it.view("atlas-tab-3").performClick()
            val scroll = it.view("atlas-scroll"); val diagram = it.transformer()
            it.adjust(values)
            assertSame(scroll, it.view("atlas-scroll")); assertSame(diagram, it.transformer())
            assertEquals(HealthAtlasMiddleEar(64.0, 4.0, 1.4), diagram.model)
            assertTrue((it.view("atlas-physiology-output") as TextView).text.toString().contains("22.4"))
        }
        scenario.recreate(); ready(scenario, "atlas-middle-ear-model")
        scenario.onActivity {
            assertEquals(HealthAtlasMiddleEar(64.0, 4.0, 1.4), it.transformer().model)
            it.view("atlas-tab-0").performClick(); it.view("atlas-hotspot-middle-ear").performClick()
            it.view("atlas-tab-3").performClick()
            assertEquals(HealthAtlasMiddleEar(), it.transformer().model)
            it.onBackPressed(); it.view("atlas-tab-1").performClick(); it.view("atlas-open-research").performClick()
            assertEquals(HealthAtlasMiddleEar(64.0, 4.0, 1.4), it.transformer().model)
            it.view("atlas-physiology-reset").performClick()
            assertEquals(HealthAtlasMiddleEar(), it.transformer().model)
        }
    }

    @Test fun auditorySequenceMovesOnTheCrossSectionAndRestoresItsOwnStage() = native { scenario ->
        scenario.onActivity {
            it.openEar(); it.view("atlas-tab-3").performClick()
            val section = it.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            val artWidth = section.lesson.artWidth
            assertEquals(420, artWidth)
            val drawable = requireNotNull(it.getDrawable(section.lesson.plate.drawable))
            assertEquals(3 * drawable.intrinsicHeight, 2 * drawable.intrinsicWidth)
            val unmarked = Bitmap.createBitmap(artWidth, 280, Bitmap.Config.ARGB_8888)
            try {
                drawable.setBounds(0, 0, artWidth, 280)
                drawable.draw(Canvas(unmarked))
                for (feature in section.lesson.plate.features) {
                    val marker = feature.marker
                    assertTrue(marker.id, Color.alpha(unmarked.getPixel((marker.x * artWidth).toInt(), (marker.y * 280).toInt())) > 200)
                }
                val point = FloatArray(2)
                for ((stage, track) in section.lesson.tracks.withIndex()) {
                    val path = PathMeasure(track(), false)
                    for (i in 0..12) {
                        assertTrue(path.getPosTan(path.length * i / 12f, point, null))
                        assertTrue("Off-plate route: stage $stage, point $i",
                            Color.alpha(unmarked.getPixel(point[0].toInt(), point[1].toInt())) > 200)
                    }
                }
                val output = unmarked.getPixel(point[0].toInt(), point[1].toInt())
                assertTrue("Neural output should end on the ochre nerve", Color.red(output) > Color.blue(output) + 45)
            } finally { unmarked.recycle() }
            section.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            section.layout(0, 0, section.measuredWidth, section.measuredHeight)
            fun frame() = Bitmap.createBitmap(section.width, section.height, Bitmap.Config.ARGB_8888).also { section.draw(Canvas(it)) }
            val start = frame()
            section.phase = .17f
            val moving = frame()
            try { assertFalse(start.sameAs(moving)) } finally { start.recycle(); moving.recycle() }
            it.view("atlas-process-stage-3").performClick()
            assertEquals(3, section.stage)
            assertTrue(section.contentDescription.contains(it.getString(R.string.health_atlas_hearing_ear_3)))
            assertEquals(HealthAtlasMiddleEar(), it.transformer().model)
            section.phase = .96f
        }
        capture("sequence", context.getString(R.string.health_atlas_hearing_ear_title))
        scenario.recreate(); ready(scenario, "atlas-section-diagram")
        scenario.onActivity {
            val section = it.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            assertEquals(3, section.stage)
            it.view("atlas-simulation-reset").performClick()
            assertEquals(0, section.stage)
        }
    }

    @Test fun earArtworkAndResponsiveDiagramRenderVisiblePixels() = native { scenario ->
        scenario.onActivity { activity ->
            val plate = HealthAtlasPlates.forId("ear")!!
            val image = Bitmap.createBitmap(420, 280, Bitmap.Config.ARGB_8888)
            try {
                activity.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, image.width, image.height); draw(Canvas(image)) }
                assertEquals(0, Color.alpha(image.getPixel(0, 0)))
                plate.markers.forEach { marker ->
                    assertTrue(marker.id, Color.alpha(image.getPixel((marker.x * image.width).toInt(), (marker.y * image.height).toInt())) > 200)
                }
            } finally { image.recycle() }
            for (mode in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                val themed = activity.createConfigurationContext(Configuration(activity.resources.configuration).apply {
                    uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or mode
                })
                val view = HealthAtlasMiddleEarView.TransformerDiagram(themed)
                for (width in listOf(720, 1080, 1600)) {
                    view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    view.layout(0, 0, width, view.measuredHeight)
                    fun draw() = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
                    view.model = HealthAtlasMiddleEar(35.0, 5.0, 1.0); val before = draw()
                    view.model = HealthAtlasMiddleEar(75.0, 2.0, 1.6); val after = draw()
                    try {
                        assertFalse(before.sameAs(after))
                        val pixels = IntArray(after.width * after.height)
                        after.getPixels(pixels, 0, after.width, 0, 0, after.width, after.height)
                        assertTrue(pixels.contains(themed.getColor(R.color.health_atlas_ear_input)))
                        assertTrue(pixels.contains(themed.getColor(R.color.health_atlas_ear_output)))
                    } finally { before.recycle(); after.recycle() }
                }
            }
        }
    }

    @Test fun localizedContextNeverAssignsPressureToCochleaOrVestibularPathways() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val model = HealthAtlasPhysiology(kind)
            val titles = (listOf("ear") + parts).map { id -> atlas.mechanism(atlas[id]!!).title }
            assertEquals(6, titles.toSet().size)
            for (id in listOf("ear", "middle-ear")) {
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], quantitative = model)
                assertTrue(prompt.contains(HealthAtlasPhysiologyText.context(localized, model)))
                assertTrue(prompt.contains(HealthAtlasMiddleEar.MEASUREMENT_SOURCE))
            }
            for (id in parts.filter { it != "middle-ear" }) {
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], quantitative = model)
                assertFalse(prompt.contains(HealthAtlasMiddleEar.SOURCE))
            }
            for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING))
                assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas["ear"], quantitative = model, topic = topic)
                    .contains(HealthAtlasMiddleEar.SOURCE))
        }
    }

    @Test fun capturesThePressureModelAndCancelsItsLivePreviewWithoutSending() = native { scenario ->
        val inputs = listOf(64, 40, 140)
        scenario.onActivity { it.openEar(); it.view("atlas-tab-3").performClick(); it.adjust(inputs) }
        capture("model", context.getString(R.string.health_atlas_middle_ear_pressure_ratio))
        scenario.onActivity {
            val slider = it.view("atlas-physiology-ear-lever")
            slider.requestRectangleOnScreen(Rect(0, 0, slider.width, slider.height), true)
        }
        capture("controls", context.getString(R.string.health_atlas_middle_ear_lever_ratio))
        scenario.onActivity { it.view("atlas-ask").performClick() }
        val expected = HealthAtlasPhysiologyText.context(context, HealthAtlasPhysiology(kind, inputs))
        assertTrue(nodes(HealthAtlasMiddleEar.SOURCE).any { it.text?.contains(expected) == true })
        assertTrue(nodes(context.getString(android.R.string.cancel)).any { it.performAction(AccessibilityNodeInfo.ACTION_CLICK) })
    }
}
