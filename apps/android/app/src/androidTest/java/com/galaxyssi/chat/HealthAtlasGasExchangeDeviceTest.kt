package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasGasExchangeDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val cells = listOf("type-i-pneumocyte", "type-ii-pneumocyte", "ciliated-airway-cell", "goblet-cell", "club-cell").map { "cell-$it" }
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
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun Activity.open(id: String) {
        view(if (id.startsWith("cell-")) "atlas-tab-3" else "atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id); view("atlas-entry-$id").performClick()
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
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-gas-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    @Test fun catalogueConnectsAlveolarStructuresToCellsAndSpecificMechanisms() {
        val atlas = HealthBodyAtlas.load(context)
        assertEquals(listOf("respiratory-membrane", "pulmonary-capillaries"), atlas["alveoli"]!!.related)
        assertTrue(atlas.cells(atlas["respiratory-membrane"]!!).any { it.id == "cell-type-i-pneumocyte" })
        assertTrue(atlas.cells(atlas["pulmonary-capillaries"]!!).any { it.id == "cell-erythrocyte" })
        assertEquals(5, cells.map { atlas.mechanism(atlas[it]!!).stages }.toSet().size)
        for (id in cells) {
            assertEquals(id, atlas[id]!!.mechanism); assertEquals(id, HealthAtlasPlates.forId(id)?.owner)
        }
        assertEquals("https://pubmed.ncbi.nlm.nih.gov/29874100/", atlas.mechanism(atlas["cell-club-cell"]!!).source)
        val membrane = HealthAtlasPlates.viewsForId("respiratory-membrane")
        assertEquals("respiratory-membrane", membrane.first().owner)
        assertTrue(membrane[1].caption(context, atlas, atlas["respiratory-membrane"]).contains(atlas["alveoli"]!!.name))
    }
    @Test fun artworkHasAlphaAndVisibleCanonicalMarkers() {
        val plate = HealthAtlasPlates.forId("alveoli")!!
        val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
        try {
            assertTrue(bitmap.width >= 1024 && bitmap.height >= 1024)
            assertTrue(Color.alpha(bitmap.getPixel(0, 0)) < 5)
            assertTrue(Color.alpha(bitmap.getPixel(bitmap.width - 1, bitmap.height - 1)) < 5)
            for (marker in plate.markers) assertTrue(marker.id, Color.alpha(bitmap.getPixel(
                (marker.x * bitmap.width).toInt(), (marker.y * bitmap.height).toInt())) > 200)
        } finally { bitmap.recycle() }
    }
    @Test fun clubCellSourceCaptionMatchesItsHumanResearchPaper() = native { scenario ->
        scenario.onActivity {
            fun has(view: View, text: String): Boolean = view is TextView && view.text.toString() == text ||
                view is ViewGroup && (0 until view.childCount).any { index -> has(view.getChildAt(index), text) }
            it.open("cell-club-cell"); it.view("atlas-tab-1").performClick()
            assertTrue(has(it.window.decorView, it.getString(R.string.health_atlas_reference_pubmed)))
            assertFalse(has(it.window.decorView, it.getString(R.string.health_atlas_reference_openstax)))
            it.view("atlas-open-research").performClick()
            assertTrue(has(it.window.decorView, it.getString(R.string.health_atlas_reference_pubmed)))
        }
    }
    @Test fun navigationAndRecreationKeepGasPhaseAndVentilationInputsIndependent() = native { scenario ->
        scenario.onActivity {
            it.open("lungs"); it.view("atlas-entry-alveoli").performClick(); it.openAtlasModelDetails()
            (it.view("atlas-physiology-rate") as SeekBar).progress = 20
            it.view("atlas-process-stage-2").performClick()
            it.view("atlas-gas-membrane").performClick()
            assertTrue(it.view("atlas-view-0").isSelected)
            it.view("atlas-view-1").performClick()
            assertTrue(it.view("atlas-hotspot-respiratory-membrane").isSelected)
            it.view("atlas-entry-cell-type-i-pneumocyte").performClick(); it.openAtlasModelDetails()
            assertNull(it.window.decorView.tagged("atlas-gas-alveolus"))
        }
        scenario.recreate(); ready(scenario, "atlas-process-stage-0")
        scenario.onActivity {
            it.onBackPressed(); it.onBackPressed()
            assertTrue(it.view("atlas-process-stage-2").isSelected)
            assertEquals(20, (it.view("atlas-physiology-rate") as SeekBar).progress)
            it.view("atlas-open-research").performClick(); it.view("atlas-process-stage-1").performClick()
            it.view("atlas-research-tab-1").performClick(); assertNull(it.window.decorView.tagged("atlas-gas-alveolus"))
            it.view("atlas-research-tab-0").performClick(); assertTrue(it.view("atlas-process-stage-1").isSelected)
            it.view("atlas-simulation-reset").performClick()
            assertEquals(6, (it.view("atlas-physiology-rate") as SeekBar).progress)
        }
    }
    @Test fun backgroundStopsAnimationAndDoesNotRestartIt() = native { scenario ->
        scenario.onActivity { it.open("alveoli"); it.openAtlasModelDetails(); it.view("atlas-simulation-play").performClick() }
        SystemClock.sleep(220); scenario.moveToState(Lifecycle.State.CREATED)
        var saved = -1
        scenario.onActivity { saved = (it.view("atlas-simulation-progress") as SeekBar).progress }
        SystemClock.sleep(220); scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity {
            assertEquals(saved, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(it.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
        }
    }
    @Test fun largeTextFitsBothLocalesAndThemesAndBothArrowsAnimate() = native { scenario ->
        scenario.onActivity { activity ->
            fun fits(view: View) {
                if (view is TextView) assertTrue(view.height >= view.layout.height + view.compoundPaddingTop + view.compoundPaddingBottom)
                if (view is ViewGroup) for (i in 0 until view.childCount) {
                    val child = view.getChildAt(i)
                    assertTrue(child.left >= 0 && child.top >= 0 && child.right <= view.width && child.bottom <= view.height)
                    fits(child)
                }
            }
            for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE))
                for (night in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                    val config = Configuration(activity.resources.configuration).apply {
                        setLocale(locale); uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or night; fontScale = 1.6f
                    }
                    val themed = activity.createConfigurationContext(config)
                    val data = HealthBodyAtlas.load(themed)
                    for (width in listOf(720, 1080, 1600)) {
                        var selected = -1; var opened = ""
                        val diagram = HealthAtlasGasExchangeView(themed, data.mechanism(data["alveoli"]!!), { selected = it }, { opened = it })
                        diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                        diagram.layout(0, 0, width, diagram.measuredHeight); fits(diagram)
                        val stableHeight = diagram.height
                        for (stage in 0..3) {
                            diagram.tagged("atlas-process-stage-$stage")!!.performClick(); assertEquals(stage, selected)
                            diagram.phase = stage / 4f
                            diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                            diagram.layout(0, 0, width, diagram.measuredHeight); fits(diagram)
                            assertEquals(stableHeight, diagram.height)
                        }
                        diagram.tagged("atlas-gas-membrane")!!.performClick(); assertEquals("respiratory-membrane", opened)
                        diagram.tagged("atlas-gas-blood")!!.performClick(); assertEquals("pulmonary-capillaries", opened)
                        for (gas in HealthAtlasGas.entries) {
                            val arrow = diagram.tagged("atlas-gas-arrow-${gas.name}")!!
                            fun draw(phase: Float): Bitmap {
                                diagram.phase = phase
                                return Bitmap.createBitmap(arrow.width, arrow.height, Bitmap.Config.ARGB_8888).also { arrow.draw(Canvas(it)) }
                            }
                            val before = draw(.1f); val after = draw(.8f)
                            try { assertFalse(before.sameAs(after)) } finally { before.recycle(); after.recycle() }
                        }
                    }
                }
        }
    }
    @Test fun publicContextSeparatesIllustrativePressuresFromPersonalRecordsAndOtherTopics() {
        val data = HealthBodyAtlas.load(context)
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTILATION, listOf(26, 500, 150))
        val prompt = HealthAtlasAgentContext.prompt(context, data, data["alveoli"], HealthAtlasSimulation(phase = .5f), model)
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_gas_scope)))
        for (gradient in HealthAtlasGasExchange.gradients) assertTrue(prompt.contains(HealthAtlasGasExchangeText.summary(context, gradient)))
        for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING))
            assertFalse(HealthAtlasAgentContext.prompt(context, data, data["alveoli"], HealthAtlasSimulation(), model, topic)
                .contains(context.getString(R.string.health_atlas_gas_scope)))
        assertFalse(HealthAtlasAgentContext.prompt(context, data, data["heart"], HealthAtlasSimulation(), model)
            .contains(context.getString(R.string.health_atlas_gas_scope)))
    }
    @Test fun realConfirmationIncludesCurrentGasContextAndCanBeCancelled() = native { scenario ->
        scenario.onActivity { it.open("alveoli"); it.openAtlasModelDetails(); it.view("atlas-process-stage-2").performClick(); it.view("atlas-ask").performClick() }
        val expected = HealthAtlasGasExchangeText.summary(context, HealthAtlasGasExchange.gradients[1])
        val root = activeWindow(expected)
        assertTrue(root.findAccessibilityNodeInfosByText(expected).isNotEmpty())
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
    }
    @Test fun structureFullscreenAndGasDirectionsRenderOnDevice() = native { scenario ->
        scenario.onActivity { it.open("alveoli") }; capture("structure")
        scenario.onActivity { it.view("atlas-fullscreen").performClick() }; capture("fullscreen")
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); instrumentation.waitForIdleSync(); SystemClock.sleep(250)
        scenario.onActivity { it.view("atlas-hotspot-pulmonary-capillaries").performClick(); it.openAtlasModelDetails() }
        capture("diagram-top")
        scenario.onActivity {
            it.view("atlas-process-stage-2").performClick()
            it.view("atlas-process-stage-2").requestRectangleOnScreen(Rect(0, 0, it.view("atlas-process-stage-2").width, it.view("atlas-process-stage-2").height), true)
        }; capture("directions")
    }
    @Test fun alveolarSimulationShowsTheDiagramBeforeTheNumericModel() = native { scenario ->
        scenario.onActivity { it.open("alveoli"); it.openAtlasModelDetails() }
        instrumentation.waitForIdleSync()
        scenario.onActivity {
            val diagram = it.view("atlas-process")
            val slider = it.view("atlas-physiology-rate")
            val a = IntArray(2); val b = IntArray(2)
            diagram.getLocationOnScreen(a); slider.getLocationOnScreen(b)
            assertTrue(b[1] >= a[1] + diagram.height)
        }
        capture("alveolar-simulation")
    }
}
