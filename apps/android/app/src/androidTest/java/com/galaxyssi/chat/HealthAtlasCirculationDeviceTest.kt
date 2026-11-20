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
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasCirculationDeviceTest {
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
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario ->
                ready(scenario, "atlas-whole-art")
                scenario.onActivity { it.view("atlas-hotspot-heart").performClick(); it.view("atlas-tab-3").performClick() }
                block(scenario)
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(250)
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() != context.packageName && SystemClock.elapsedRealtime() < deadline)
            SystemClock.sleep(50)
        assertEquals(context.packageName, instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString())
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-circulation-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun stagesPauseAndChangeTheVisibleRouteWithoutResettingCardiacInputs() = native { scenario ->
        scenario.onActivity {
            (it.view("atlas-parameter-first") as SeekBar).progress = 60
            it.view("atlas-simulation-play").performClick()
            it.view("atlas-process-stage-2").performClick()
            assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(60, (it.view("atlas-parameter-first") as SeekBar).progress)
            assertTrue(it.view("atlas-process-stage-2").isSelected)
            assertEquals(it.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
            assertTrue((it.view("atlas-circulation-flow") as TextView).text.toString().contains("7"))
            val view = it.view("atlas-process") as HealthAtlasCirculationView
            fun draw() = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { target -> view.draw(Canvas(target)) }
            view.phase = .02f; val first = draw(); view.phase = .20f; val second = draw()
            try { assertFalse(first.sameAs(second)) } finally { first.recycle(); second.recycle() }
        }
    }
    @Test fun diagramAndOutputRestoreAcrossNavigationAndRecreation() = native { scenario ->
        scenario.onActivity {
            (it.view("atlas-parameter-first") as SeekBar).progress = 50
            (it.view("atlas-parameter-second") as SeekBar).progress = 50
            it.view("atlas-process-stage-3").performClick()
            it.view("atlas-circulation-node-lungs").performClick()
            assertNotNull(it.view("atlas-hotspot-bronchi"))
        }
        scenario.recreate(); ready(scenario, "atlas-hotspot-bronchi")
        scenario.onActivity {
            it.onBackPressed()
            assertTrue(it.view("atlas-tab-3").isSelected)
            assertEquals(50, (it.view("atlas-parameter-first") as SeekBar).progress)
            assertEquals(50, (it.view("atlas-parameter-second") as SeekBar).progress)
            assertEquals(750, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(7.2, (it.view("atlas-process") as HealthAtlasCirculationView).flowLitresPerMinute!!, .0001)
            it.view("atlas-circulation-node-heart").performClick()
            assertTrue(it.view("atlas-tab-0").isSelected)
            it.onBackPressed(); assertTrue(it.view("atlas-tab-3").isSelected)
            it.view("atlas-simulation-reset").performClick()
            assertEquals(4.9, (it.view("atlas-process") as HealthAtlasCirculationView).flowLitresPerMinute!!, .0001)
        }
    }
    @Test fun researchUsesTheSameCircuitAndReturnsToItsInputs() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-open-research").performClick()
            it.view("atlas-process-stage-1").performClick()
            assertNotNull(it.view("atlas-source-circulation"))
            it.view("atlas-circulation-node-lungs").performClick()
            it.onBackPressed()
            assertTrue(it.view("atlas-research-tab-0").isSelected)
            assertEquals(250, (it.view("atlas-simulation-progress") as SeekBar).progress)
            it.view("atlas-research-tab-1").performClick()
            assertNull(it.window.decorView.tagged("atlas-circulation-node-lungs"))
        }
    }
    @Test fun backgroundingStopsTheCirculationAnimation() = native { scenario ->
        scenario.onActivity { it.view("atlas-simulation-play").performClick() }
        SystemClock.sleep(220)
        scenario.moveToState(Lifecycle.State.CREATED)
        var saved = -1
        scenario.onActivity { saved = (it.view("atlas-simulation-progress") as SeekBar).progress }
        SystemClock.sleep(220)
        scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity {
            assertEquals(saved, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(it.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
        }
    }
    @Test fun labelsFitLargeTypeInBothLanguagesAndThemes() = native { scenario ->
        scenario.onActivity { activity ->
            for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE))
                for (night in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                    val config = Configuration(activity.resources.configuration).apply {
                        setLocale(locale); uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or night; fontScale = 1.6f
                    }
                    val themed = activity.createConfigurationContext(config)
                    val atlas = HealthBodyAtlas.load(themed)
                    for (width in listOf(720, 1080, 1600)) {
                        var stage = -1
                        var opened = ""
                        val diagram = HealthAtlasCirculationView(themed, atlas.mechanism(atlas["heart"]!!), { stage = it }, { opened = it })
                        diagram.flowLitresPerMinute = 4.9
                        diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                        diagram.layout(0, 0, width, diagram.measuredHeight)
                        val children = (0 until diagram.childCount).map(diagram::getChildAt)
                        for (child in children) {
                            assertTrue(child.left >= 0 && child.top >= 0 && child.right <= width && child.bottom <= diagram.height)
                            if (child is TextView) assertTrue(child.height >= child.layout.height + child.compoundPaddingTop + child.compoundPaddingBottom)
                        }
                        for (a in children.indices) for (b in a + 1 until children.size) {
                            val x = children[a]; val y = children[b]
                            assertFalse("Overlapping circuit labels", x.left < y.right && y.left < x.right && x.top < y.bottom && y.top < x.bottom)
                        }
                        for (index in 0..3) {
                            val label = requireNotNull(diagram.tagged("atlas-process-stage-$index"))
                            assertTrue(label.isFocusable); label.performClick(); assertEquals(index, stage)
                        }
                        diagram.tagged("atlas-circulation-node-lungs")!!.performClick(); assertEquals("lungs", opened)
                        diagram.tagged("atlas-circulation-node-heart")!!.performClick(); assertEquals("heart", opened)
                        val bitmap = Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(themed.getColor(R.color.page_bg)); diagram.draw(Canvas(bitmap))
                            var drawn = 0
                            for (y in 0 until bitmap.height step 10) for (x in 0 until bitmap.width step 10)
                                if (bitmap.getPixel(x, y) != themed.getColor(R.color.page_bg)) drawn++
                            assertTrue(drawn > 500)
                        } finally { bitmap.recycle() }
                    }
                }
        }
    }
    @Test fun publicContextContainsDirectionAndScopeButOtherTopicsDoNot() {
        val atlas = HealthBodyAtlas.load(context)
        val item = atlas["heart"]!!
        val prompt = HealthAtlasAgentContext.prompt(context, atlas, item, HealthAtlasSimulation(90, 80, .5f))
        assertTrue(prompt.contains(HealthAtlasCirculation.SOURCE))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_circuit_path)))
        assertTrue(prompt.contains("7.2"))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_circuit_scope)))
        for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING)) {
            val other = HealthAtlasAgentContext.prompt(context, atlas, item, HealthAtlasSimulation(), topic = topic)
            assertTrue(other.contains(HealthAtlasHeartSection.ANATOMY_SOURCE))
            assertFalse(other.contains(context.getString(R.string.health_atlas_circuit_scope)))
            assertFalse(other.contains(context.getString(R.string.health_atlas_circuit_path)))
            assertFalse(other.contains(context.getString(R.string.health_atlas_cardiac_output) + ":"))
        }
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, atlas["kidneys"], HealthAtlasSimulation()).contains(HealthAtlasCirculation.SOURCE))
    }
    @Test fun actualConfirmationIncludesTheSelectedCirculationStage() = native { scenario ->
        scenario.onActivity { it.view("atlas-process-stage-2").performClick(); it.view("atlas-ask").performClick() }
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5000
        var root = instrumentation.uiAutomation.rootInActiveWindow
        while (root?.findAccessibilityNodeInfosByText(HealthAtlasCirculation.SOURCE).isNullOrEmpty() && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(50); root = instrumentation.uiAutomation.rootInActiveWindow
        }
        assertTrue(root!!.findAccessibilityNodeInfosByText(HealthAtlasCirculation.SOURCE).isNotEmpty())
        val atlas = HealthBodyAtlas.load(context)
        val stage = atlas.mechanism(atlas["heart"]!!).stages[2]
        assertTrue(root.findAccessibilityNodeInfosByText(stage).isNotEmpty())
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
    }
    @Test fun nativeCirculationScreensRenderAllStages() = native { scenario ->
        for (stage in 0..3) {
            scenario.onActivity { it.view("atlas-process-stage-$stage").performClick() }
            capture("stage-$stage")
        }
        scenario.onActivity { it.view("atlas-open-research").performClick() }
        capture("research")
    }
}
