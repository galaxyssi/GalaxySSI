package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasGermlineDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue(key, found)
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun Activity.open(id: String) {
        view("atlas-tab-3").performClick()
        (view("atlas-search") as EditText).setText(id); view("atlas-entry-$id").performClick()
        openAtlasModelDetails()
    }
    private fun activeWindow(text: String? = null): android.view.accessibility.AccessibilityNodeInfo {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName &&
                (text == null || root.findAccessibilityNodeInfosByText(text).isNotEmpty())) return root
            SystemClock.sleep(50)
        }
        error("Atlas window did not become accessible")
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(250); activeWindow()
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-germline-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun allStageCountsUpdateWithoutRebuildingThePage() = native { scenario ->
        for (id in HealthAtlasGermline.supported) {
            scenario.onActivity { activity ->
                activity.open(id)
                val scroll = activity.view("atlas-scroll"); val ask = activity.view("atlas-ask")
                val diagram = activity.view("atlas-germline") as HealthAtlasGermlineView
                for (stage in 0..3) {
                    activity.view("atlas-process-stage-$stage").performClick()
                    assertSame(scroll, activity.view("atlas-scroll")); assertSame(ask, activity.view("atlas-ask"))
                    assertSame(diagram, activity.view("atlas-germline"))
                    val expected = HealthAtlasGermline.counts(id, stage)!!
                    assertEquals(expected, diagram.counts)
                    assertEquals(HealthAtlasGermlineText.numbers(activity, expected),
                        (activity.view("atlas-germline-numbers") as TextView).text.toString())
                    assertEquals(activity.getString(HealthAtlasGermlineText.target(expected.target)),
                        (activity.view("atlas-germline-target") as TextView).text.toString())
                    assertEquals(stage * 250, (activity.view("atlas-simulation-progress") as SeekBar).progress)
                }
                activity.view("atlas-simulation-reset").performClick()
                assertEquals(0, diagram.stage)
                activity.onBackPressed()
            }
        }
    }
    @Test fun selectionSurvivesRecreationAndRemainsScopedToEachCell() = native { scenario ->
        scenario.onActivity { it.open("cell-spermatocyte"); it.view("atlas-process-stage-2").performClick() }
        scenario.recreate(); ready(scenario, "atlas-germline")
        scenario.onActivity {
            assertEquals(2, (it.view("atlas-germline") as HealthAtlasGermlineView).stage)
            it.view("atlas-tab-0").performClick(); it.openAtlasModelDetails()
            assertEquals(2, (it.view("atlas-germline") as HealthAtlasGermlineView).stage)
            it.onBackPressed(); it.open("cell-oocyte-or-ovum")
            assertEquals(0, (it.view("atlas-germline") as HealthAtlasGermlineView).stage)
            it.onBackPressed(); it.open("cell-spermatocyte")
            assertEquals(2, (it.view("atlas-germline") as HealthAtlasGermlineView).stage)
        }
    }
    @Test fun backgroundStopsPlaybackAndStageTapKeepsItPaused() = native { scenario ->
        scenario.onActivity { it.open("cell-spermatocyte"); it.view("atlas-simulation-play").performClick() }
        SystemClock.sleep(200); scenario.moveToState(Lifecycle.State.CREATED)
        var phase = -1
        scenario.onActivity { phase = (it.view("atlas-simulation-progress") as SeekBar).progress }
        SystemClock.sleep(300); scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity {
            assertEquals(phase, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(context.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
            it.view("atlas-simulation-play").performClick(); it.view("atlas-process-stage-1").performClick()
        }
        SystemClock.sleep(300)
        scenario.onActivity {
            assertEquals(250, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(1, (it.view("atlas-germline") as HealthAtlasGermlineView).stage)
        }
    }
    @Test fun playbackAdvancesTheNumericalStageAndPauseFreezesIt() = native { scenario ->
        scenario.onActivity {
            it.open("cell-spermatocyte")
            (it.view("atlas-parameter-speed") as SeekBar).progress = 3
            it.view("atlas-simulation-play").performClick()
        }
        var current = 0
        val deadline = SystemClock.elapsedRealtime() + 9000
        while (current == 0 && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { current = (it.view("atlas-germline") as HealthAtlasGermlineView).stage }
            if (current == 0) SystemClock.sleep(40)
        }
        assertTrue(current > 0)
        var phase = -1
        scenario.onActivity {
            val play = it.view("atlas-simulation-play")
            if (play.contentDescription == it.getString(R.string.health_body_pause)) play.performClick()
            phase = (it.view("atlas-simulation-progress") as SeekBar).progress
            val view = it.view("atlas-germline") as HealthAtlasGermlineView
            assertEquals(HealthAtlasGermline.counts("cell-spermatocyte", view.stage), view.counts)
            assertEquals(23, view.counts.chromosomes)
        }
        SystemClock.sleep(200)
        scenario.onActivity { assertEquals(phase, (it.view("atlas-simulation-progress") as SeekBar).progress) }
    }
    @Test fun promptsCarryCurrentCountsSourcesAndLimitsOnlyForSelectedPhysiology() {
        for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            for (id in HealthAtlasGermline.supported) for (stage in 0..3) {
                val values = HealthAtlasSimulation(phase = stage / 4f)
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], simulation = values)
                val counts = HealthAtlasGermline.counts(id, stage)!!
                assertTrue(prompt.contains(HealthAtlasGermlineText.numbers(localized, counts)))
                assertTrue(prompt.contains(localized.getString(HealthAtlasGermlineText.target(counts.target))))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_germline_scope)))
                assertTrue(prompt.contains(HealthAtlasGermline.SOURCE))
                for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING))
                    assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], simulation = values, topic = topic)
                        .contains(localized.getString(R.string.health_atlas_germline_scope)))
            }
            for (id in listOf("cell-sertoli-cell", "cell-granulosa-cell", "cell-neuron", "male", "female"))
                assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], simulation = HealthAtlasSimulation())
                    .contains(localized.getString(R.string.health_atlas_germline_scope)))
        }
    }
    @Test fun countReferenceUsesExistingSourceFlowAndSupportCellsHaveNoGeneticModel() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            for (id in listOf("cell-spermatocyte", "cell-sertoli-cell", "cell-granulosa-cell", "cell-trophoblast")) {
                val body = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
                var opened: String? = null
                val panel = HealthAtlasSimulationPanel(activity, body, atlas, atlas[id]!!, null, null,
                    { _, _ -> }, { opened = it }, {})
                if (id in HealthAtlasGermline.supported) {
                    val countView = body.tagged("atlas-germline")!!
                    val scene = body.tagged("atlas-simulation-frame") as LinearLayout
                    assertTrue(scene.indexOfChild(scene.tagged("atlas-simulation-play")!!.parent as View) < scene.indexOfChild(countView))
                    assertTrue(scene.indexOfChild(scene.tagged("atlas-simulation-stage")) < scene.indexOfChild(countView))
                    assertTrue(body.indexOfChild(body.tagged("atlas-germline-scope")) > body.indexOfChild(scene))
                    body.tagged("atlas-source-germline")!!.performClick()
                    assertEquals(HealthAtlasGermline.SOURCE, opened)
                } else {
                    assertNull(body.tagged("atlas-germline")); assertNull(body.tagged("atlas-source-germline"))
                }
                panel.pause()
            }
        }
    }
    @Test fun diagramIsNonblankChangesWithDivisionAndFitsLargeText() = native { scenario ->
        scenario.onActivity { activity ->
            fun enlarge(view: View) {
                if (view is TextView) view.textSize = 26f
                if (view is ViewGroup) for (i in 0 until view.childCount) enlarge(view.getChildAt(i))
            }
            fun fits(view: View) {
                if (view is TextView) assertTrue(view.height >= view.layout.height + view.compoundPaddingTop + view.compoundPaddingBottom)
                if (view is ViewGroup) for (i in 0 until view.childCount) {
                    val child = view.getChildAt(i)
                    assertTrue(child.left >= 0 && child.top >= 0 && child.right <= view.width && child.bottom <= view.height)
                    fits(child)
                }
            }
            for (width in listOf(720, 1080, 1600)) for (id in HealthAtlasGermline.supported) {
                val view = HealthAtlasGermlineView(activity, id); enlarge(view)
                fun draw(): Bitmap {
                    view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    view.layout(0, 0, width, view.measuredHeight); fits(view)
                    val diagram = view.tagged("atlas-germline-diagram")!!
                    return Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also { diagram.draw(Canvas(it)) }
                }
                val before = draw(); view.stage = 2; val after = draw()
                try {
                    if (id != "cell-spermatozoon") assertFalse(before.sameAs(after))
                    val pixels = IntArray(after.width * after.height); after.getPixels(pixels, 0, after.width, 0, 0, after.width, after.height)
                    assertTrue(pixels.count { android.graphics.Color.alpha(it) > 0 } > 1000)
                    assertEquals(HealthAtlasGermlineText.numbers(activity, view.counts), view.tagged("atlas-germline-diagram")!!.contentDescription)
                } finally { before.recycle(); after.recycle() }
            }
        }
    }
    @Test fun actualAgentPreviewContainsCurrentMaternalCountsAndCanBeCancelled() = native { scenario ->
        scenario.onActivity {
            it.open("cell-oocyte-or-ovum"); it.view("atlas-process-stage-2").performClick()
            it.view("atlas-ask").performClick()
        }
        val root = activeWindow(context.getString(R.string.health_atlas_germline_maternal))
        val expected = HealthAtlasGermlineText.numbers(context, HealthAtlasGermline.counts("cell-oocyte-or-ovum", 2)!!)
        assertTrue(root.findAccessibilityNodeInfosByText(expected).isNotEmpty())
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
        instrumentation.waitForIdleSync()
        scenario.onActivity { assertEquals(2, (it.view("atlas-germline") as HealthAtlasGermlineView).stage) }
    }
    @Test fun nativeCountAndSupportCellScreensAreVisibleOnDevice() = native { scenario ->
        scenario.onActivity { it.open("cell-spermatocyte") }; capture("primary")
        scenario.onActivity { it.view("atlas-process-stage-2").performClick() }; capture("haploid")
        scenario.onActivity {
            it.onBackPressed(); it.open("cell-oocyte-or-ovum"); it.view("atlas-process-stage-3").performClick()
        }; capture("zygote")
        scenario.onActivity { it.onBackPressed(); it.open("cell-sertoli-cell") }; capture("support")
    }
}
