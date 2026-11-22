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
import android.widget.SeekBar
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasVesselFlowDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val kind = HealthAtlasPhysiologyKind.VESSEL_FLOW
    private val ids = listOf("blood-vessels", "arteries", "veins", "coronary-vessels")
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
        view("atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id); view("atlas-entry-$id").performClick()
        openAtlasModelDetails()
    }
    private fun Activity.setInputs(values: List<Int>) = values.forEachIndexed { index, value ->
        (view("atlas-physiology-${kind.inputs[index].key}") as SeekBar).progress = value - kind.inputs[index].range.first
    }
    private fun activeWindow(text: String): android.view.accessibility.AccessibilityNodeInfo {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName &&
                root.findAccessibilityNodeInfosByText(text).isNotEmpty()) return root
            SystemClock.sleep(50)
        }
        error("Expected atlas content did not become accessible: $text")
    }
    private fun capture(name: String, expected: String) {
        activeWindow(expected); SystemClock.sleep(350)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-vessel-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    @Test fun fourInputsUpdateLocallyAndSmallPositiveFlowIsNotRoundedToZero() = native { scenario ->
        scenario.onActivity {
            for (id in ids) {
                it.open(id)
                val scroll = it.view("atlas-scroll"); val ask = it.view("atlas-ask")
                val view = it.view("atlas-vessel-flow") as HealthAtlasVesselFlowView
                val values = listOf(1, 51, 100, 60)
                it.setInputs(values)
                assertSame(scroll, it.view("atlas-scroll")); assertSame(ask, it.view("atlas-ask"))
                assertSame(view, it.view("atlas-vessel-flow"))
                assertEquals(.051, view.flow.radiusMm, 0.0)
                val model = HealthAtlasPhysiology(kind, values)
                val text = (it.view("atlas-physiology-output") as TextView).text.toString()
                assertEquals(HealthAtlasPhysiologyText.resultNumber(model, model.result) + " mL/min", text)
                assertNotEquals("0 mL/min", text)
                assertTrue((it.view("atlas-vessel-geometry") as TextView).text.contains("0.051"))
                it.view("atlas-physiology-reset").performClick()
                assertEquals(HealthAtlasVesselFlow(), view.flow)
                it.onBackPressed()
            }
        }
    }
    @Test fun allFourParametersRestorePerEntryAndCarryToPhysiologyResearch() = native { scenario ->
        val values = listOf(17, 153, 73, 42)
        scenario.onActivity { it.open("arteries"); it.setInputs(values) }
        scenario.recreate(); ready(scenario, "atlas-vessel-flow")
        scenario.onActivity {
            fun verify() = values.forEachIndexed { index, value ->
                assertEquals(value - kind.inputs[index].range.first,
                    (it.view("atlas-physiology-${kind.inputs[index].key}") as SeekBar).progress)
            }
            verify()
            it.view("atlas-tab-1").performClick(); it.view("atlas-open-research").performClick()
            assertTrue(it.view("atlas-research-tab-drugs").isSelected)
            it.onBackPressed(); verify()
            it.onBackPressed(); it.open("veins")
            assertEquals(HealthAtlasVesselFlow(), (it.view("atlas-vessel-flow") as HealthAtlasVesselFlowView).flow)
            it.onBackPressed(); it.open("arteries"); verify()
        }
    }
    @Test fun publicContextIsLocalizedScopedAndIncludesThreeScientificReferences() {
        for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val model = HealthAtlasPhysiology(kind, listOf(1, 51, 100, 60))
            for (id in ids) {
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], quantitative = model)
                assertTrue(prompt.contains(HealthAtlasPhysiologyText.result(localized, model)))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_vessel_scope)))
                kind.sources.forEach { assertTrue(prompt.contains(it)) }
                assertTrue(prompt.contains(HealthAtlasVesselFlowText.context(localized, requireNotNull(model.vesselFlow))))
            }
            for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING))
                assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas["arteries"], quantitative = model, topic = topic)
                    .contains(localized.getString(R.string.health_atlas_vessel_scope)))
            assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas["heart"], quantitative = model)
                .contains(localized.getString(R.string.health_atlas_vessel_scope)))
        }
    }
    @Test fun diagramsChangeWithGeometryAndZeroPressureAndLargeTextFits() = native { scenario ->
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
            for (width in listOf(720, 1080, 1600)) {
                val view = HealthAtlasVesselFlowView(activity); enlarge(view)
                fun draw(): Bitmap {
                    view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    view.layout(0, 0, width, view.measuredHeight); fits(view)
                    val diagram = view.tagged("atlas-vessel-profile")!!
                    assertTrue(diagram.contentDescription.contains(HealthAtlasPhysiologyText.number(view.flow.centreSpeedMmPerSecond, 4)))
                    return Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also { diagram.draw(Canvas(it)) }
                }
                var previous = draw()
                for (flow in listOf(view.flow.copy(radiusMm = .2), view.flow.copy(lengthMm = 100.0), view.flow.copy(pressureMmHg = 0.0))) {
                    view.flow = flow; val current = draw()
                    try {
                        assertFalse(previous.sameAs(current))
                        val pixels = IntArray(current.width * current.height)
                        current.getPixels(pixels, 0, current.width, 0, 0, current.width, current.height)
                        assertTrue(pixels.count { android.graphics.Color.alpha(it) > 0 } > 1000)
                    } finally { previous.recycle(); previous = current }
                }
                previous.recycle()
            }
        }
    }
    @Test fun eachSourceOpensTheCorrectReference() = native { scenario ->
        scenario.onActivity { activity ->
            val body = HealthCenterViews(activity).column(); var opened = ""
            HealthAtlasPhysiologyPanel(activity, body, kind, null) { opened = it }
            kind.sources.forEachIndexed { index, source ->
                body.tagged("atlas-physiology-source" + if (index == 0) "" else "-$index")!!.performClick()
                assertEquals(source, opened)
            }
        }
    }
    @Test fun actualAgentPreviewUsesCurrentValuesAndCanBeCancelled() = native { scenario ->
        scenario.onActivity {
            it.open("arteries"); it.setInputs(listOf(1, 51, 100, 60)); it.view("atlas-ask").performClick()
        }
        val model = HealthAtlasPhysiology(kind, listOf(1, 51, 100, 60))
        val root = activeWindow(HealthAtlasPhysiologyText.result(context, model))
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
        instrumentation.waitForIdleSync()
        scenario.onActivity { assertNotNull(it.view("atlas-vessel-flow")) }
    }
    @Test fun nativeFlowControlsAndCurveAreVisible() = native { scenario ->
        scenario.onActivity { it.open("arteries") }
        capture("profile", context.getString(R.string.health_atlas_vessel_title))
        scenario.onActivity {
            val target = it.view("atlas-physiology-vessel-pressure")
            target.requestRectangleOnScreen(android.graphics.Rect(0, 0, target.width, target.height), true)
        }
        capture("controls", context.getString(R.string.health_atlas_vessel_pressure))
        scenario.onActivity {
            val target = it.view("atlas-physiology-vessel-viscosity")
            target.requestRectangleOnScreen(android.graphics.Rect(0, 0, target.width, target.height), true)
        }
        capture("all-controls", context.getString(R.string.health_atlas_vessel_viscosity))
        scenario.onActivity {
            it.setInputs(listOf(20, 153, 20, 20))
            val chart = it.view("atlas-physiology-curve")
            chart.requestRectangleOnScreen(android.graphics.Rect(0, 0, chart.width, chart.height), true)
        }
        capture("curve", "mL/min")
    }
}
