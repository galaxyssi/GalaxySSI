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
import android.view.inspector.WindowInspector
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasDistributionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }; if (!found) SystemClock.sleep(40)
        }
        assertTrue(key, found)
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        // Subscribe before launch so the service observes the window-added event.
        instrumentation.uiAutomation
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario ->
                ready(scenario, "atlas-whole-art")
                scenario.onActivity {
                    it.view("atlas-hotspot-heart").performClick(); it.view("atlas-tab-1").performClick()
                    it.view("atlas-open-research").performClick(); it.view("atlas-research-tab-1").performClick()
                }
                block(scenario)
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(300)
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() != context.packageName &&
            SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(50)
        assertEquals(context.packageName, instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString())
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-distribution-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    @Test fun modelSwitchAndSlidersOnlyReplaceTheModelRegion() = native { scenario ->
        scenario.onActivity {
            val adme = it.view("atlas-adme-liver"); val scroll = it.view("atlas-scroll")
            (it.view("atlas-elimination-half-life") as SeekBar).progress = 7
            it.view("atlas-drug-model-1").performClick()
            assertSame(adme, it.view("atlas-adme-liver")); assertSame(scroll, it.view("atlas-scroll"))
            val chart = it.view("atlas-distribution-chart")
            val seek = it.view("atlas-distribution-elapsed") as SeekBar
            seek.progress = 0
            val diagram = it.view("atlas-distribution-diagram") as HealthAtlasDistributionDiagram
            assertEquals(100.0, diagram.model.amounts.central, 0.0)
            seek.progress = 16
            assertEquals(31.31146654418996, diagram.model.amounts.central, 1e-10)
            assertSame(chart, it.view("atlas-distribution-chart")); assertSame(seek, it.view("atlas-distribution-elapsed"))
            it.view("atlas-drug-model-0").performClick()
            assertEquals(7, (it.view("atlas-elimination-half-life") as SeekBar).progress)
            it.view("atlas-drug-model-1").performClick()
            assertEquals(16, (it.view("atlas-distribution-elapsed") as SeekBar).progress)
        }
    }
    @Test fun inputsModeAndParentNavigationRestoreWithoutLeakingToOtherOrgans() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-drug-model-1").performClick(); (it.view("atlas-distribution-outward") as SeekBar).progress = 63
            (it.view("atlas-distribution-elapsed") as SeekBar).progress = 27
            it.view("atlas-adme-liver").performClick(); it.view("atlas-tab-1").performClick()
            it.view("atlas-open-research").performClick(); it.view("atlas-research-tab-1").performClick()
            assertTrue(it.view("atlas-drug-model-0").isSelected)
            it.view("atlas-drug-model-1").performClick()
            assertEquals(30, (it.view("atlas-distribution-outward") as SeekBar).progress)
            it.onBackPressed(); it.onBackPressed()
            assertEquals(63, (it.view("atlas-distribution-outward") as SeekBar).progress)
        }
        scenario.recreate(); ready(scenario, "atlas-distribution-chart")
        scenario.onActivity {
            assertTrue(it.view("atlas-drug-model-1").isSelected)
            assertEquals(63, (it.view("atlas-distribution-outward") as SeekBar).progress)
            assertEquals(27, (it.view("atlas-distribution-elapsed") as SeekBar).progress)
        }
    }
    @Test fun backgroundAndResetDoNotChangeOtherModels() = native { scenario ->
        scenario.onActivity {
            (it.view("atlas-elimination-half-life") as SeekBar).progress = 8
            it.view("atlas-drug-model-1").performClick(); (it.view("atlas-distribution-loss") as SeekBar).progress = 0
            (it.view("atlas-distribution-return") as SeekBar).progress = 170
        }
        scenario.moveToState(Lifecycle.State.CREATED); SystemClock.sleep(200); scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity {
            assertEquals(0, (it.view("atlas-distribution-loss") as SeekBar).progress)
            it.view("atlas-distribution-reset").performClick()
            assertEquals(HealthAtlasDistribution(), (it.view("atlas-distribution-diagram") as HealthAtlasDistributionDiagram).model)
            it.view("atlas-drug-model-0").performClick()
            assertEquals(8, (it.view("atlas-elimination-half-life") as SeekBar).progress)
        }
    }
    @Test fun agentPromptsIncludeOnlyTheSelectedDrugModelAndPublicAssumptions() {
        for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
            val local = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(local)
            val model = HealthAtlasDrugState(HealthAtlasDrugMode.TWO, HealthAtlasDistribution(70, 20, 0, 40))
            val prompt = HealthAtlasAgentContext.prompt(local, atlas, atlas["liver"], topic = HealthAtlasResearchTopic.DRUGS,
                elimination = HealthAtlasElimination(7, 21), drugs = model)
            assertTrue(prompt.contains(HealthAtlasDistributionText.prompt(local, model.distribution)))
            assertFalse(prompt.contains(local.getString(R.string.health_atlas_elimination_assumptions)))
            for (topic in listOf(null, HealthAtlasResearchTopic.PHYSIOLOGY, HealthAtlasResearchTopic.AGING))
                assertFalse(HealthAtlasAgentContext.prompt(local, atlas, atlas["liver"], topic = topic, drugs = model)
                    .contains(HealthAtlasDistribution.SOURCE))
            val single = HealthAtlasAgentContext.prompt(local, atlas, atlas["liver"], topic = HealthAtlasResearchTopic.DRUGS,
                drugs = model.copy(mode = HealthAtlasDrugMode.SINGLE))
            assertFalse(single.contains(HealthAtlasDistribution.SOURCE))
        }
    }
    @Test fun nativeConfirmationUsesTheVisibleDistributionValues() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-drug-model-1").performClick(); (it.view("atlas-distribution-outward") as SeekBar).progress = 70
            it.view("atlas-ask").performClick()
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            val roots = WindowInspector.getGlobalWindowViews()
            val message = roots.firstNotNullOfOrNull { it.findViewById<TextView>(android.R.id.message) }!!.text.toString()
            assertTrue(message.contains(HealthAtlasDistributionText.prompt(context, HealthAtlasDistribution(outward = 70))))
            roots.firstNotNullOfOrNull { it.findViewById<View>(android.R.id.button2) }!!.performClick()
        }
    }
    @Test fun graphAndNativeLabelsRenderWithLargeTypeAcrossThemesAndWidths() {
        instrumentation.runOnMainSync {
            for (night in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES))
                for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
                    val local = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
                        setLocale(locale); fontScale = 1.8f; uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or night
                    })
                    for (width in listOf(720, 1080, 1600)) for (view in listOf(HealthAtlasDistributionDiagram(local), HealthAtlasDistributionChart(local))) {
                        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                        view.layout(0, 0, width, view.measuredHeight)
                        if (view is HealthAtlasDistributionDiagram) {
                            val height = view.height
                            for (time in listOf(0, 16, 192)) {
                                view.model = HealthAtlasDistribution(quarterHours = time)
                                view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                                view.layout(0, 0, width, view.measuredHeight)
                                assertEquals(height, view.height)
                            }
                        }
                        fun labels(node: View): List<TextView> = if (node is TextView) listOf(node) else if (node is ViewGroup)
                            (0 until node.childCount).flatMap { labels(node.getChildAt(it)) } else emptyList()
                        labels(view).forEach { text ->
                            assertTrue(text.height >= text.layout.height + text.compoundPaddingTop + text.compoundPaddingBottom)
                            assertTrue(text.layout.lineCount > 0)
                            for (line in 0 until text.layout.lineCount) assertTrue(text.layout.getLineWidth(line) <= text.width + 1)
                        }
                        val bitmap = Bitmap.createBitmap(width, view.height, Bitmap.Config.ARGB_8888)
                        try {
                            val background = local.getColor(R.color.page_bg); bitmap.eraseColor(background); view.draw(Canvas(bitmap))
                            var changed = 0
                            for (y in 0 until bitmap.height step 6) for (x in 0 until width step 6) if (bitmap.getPixel(x, y) != background) changed++
                            assertTrue(changed > 100)
                        } finally { bitmap.recycle() }
                    }
                }
        }
    }
    @Test fun allParameterEndpointsKeepAccessibleNumbersAndConservation() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-drug-model-1").performClick()
            for (key in listOf("outward", "return", "loss", "elapsed")) {
                val seek = it.view("atlas-distribution-$key") as SeekBar
                for (value in listOf(0, seek.max)) {
                    seek.progress = value
                    assertEquals((it.view("atlas-distribution-label-$key") as TextView).text.toString(), seek.contentDescription.toString())
                    val model = (it.view("atlas-distribution-diagram") as HealthAtlasDistributionDiagram).model
                    val amounts = model.amounts
                    assertEquals(100.0, amounts.central + amounts.peripheral + amounts.eliminated, 1e-9)
                    assertTrue(it.view("atlas-distribution-chart").contentDescription.contains(HealthAtlasDistributionText.summary(it, model)))
                }
            }
        }
    }
    @Test fun curvePixelsChangeWhenTransferRatesChange() {
        instrumentation.runOnMainSync {
            val view = HealthAtlasDistributionChart(context)
            view.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            view.layout(0, 0, 1080, view.measuredHeight)
            val first = Bitmap.createBitmap(1080, view.height, Bitmap.Config.ARGB_8888)
            val second = Bitmap.createBitmap(1080, view.height, Bitmap.Config.ARGB_8888)
            try {
                first.eraseColor(context.getColor(R.color.page_bg)); second.eraseColor(context.getColor(R.color.page_bg))
                view.draw(Canvas(first)); view.model = HealthAtlasDistribution(0, 0, 0, 0); view.draw(Canvas(second))
                var changed = 0
                for (y in 0 until view.height step 3) for (x in 0 until view.width step 3)
                    if (first.getPixel(x, y) != second.getPixel(x, y)) changed++
                assertTrue("Changing rates left the curves unchanged", changed > 100)
            } finally { first.recycle(); second.recycle() }
        }
    }
    @Test fun finalDistributionPageAndControlsAreVisibleOnDevice() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-drug-model-1").performClick()
            val scroll = it.view("atlas-scroll") as ScrollView
            val rect = android.graphics.Rect(); it.view("atlas-distribution-diagram").getDrawingRect(rect)
            scroll.offsetDescendantRectToMyCoords(it.view("atlas-distribution-diagram"), rect); scroll.scrollTo(0, rect.top - 100)
        }
        capture("overview")
        scenario.onActivity {
            val scroll = it.view("atlas-scroll") as ScrollView
            val rect = android.graphics.Rect(); it.view("atlas-distribution-label-elapsed").getDrawingRect(rect)
            scroll.offsetDescendantRectToMyCoords(it.view("atlas-distribution-label-elapsed"), rect); scroll.scrollTo(0, rect.top - 40)
        }
        capture("controls")
    }
}
