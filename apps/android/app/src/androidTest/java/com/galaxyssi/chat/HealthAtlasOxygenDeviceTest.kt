package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
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

class HealthAtlasOxygenDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val kind = HealthAtlasPhysiologyKind.OXYGEN_BINDING
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue("Missing $key", found)
    }
    private fun Activity.open(id: String) {
        view(if (id.startsWith("cell-")) "atlas-tab-3" else "atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick(); view("atlas-tab-3").performClick()
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
        instrumentation.waitForIdleSync(); SystemClock.sleep(350)
        activeWindow()
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-oxygen-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun controlsUpdateAndRestoreIndependentlyForBloodAndRedCells() = native { scenario ->
        scenario.onActivity {
            it.open("cell-erythrocyte")
            val output = it.view("atlas-physiology-output") as TextView
            val saturation = output.text.toString()
            val companion = it.view("atlas-physiology-companion") as TextView
            val before = companion.text.toString()
            (it.view("atlas-physiology-hemoglobin") as SeekBar).progress = 25
            assertEquals(saturation, output.text.toString()); assertNotEquals(before, companion.text.toString())
            (it.view("atlas-physiology-p50") as SeekBar).progress = 250
            assertNotEquals(saturation, output.text.toString())
            (it.view("atlas-physiology-oxygen-pressure") as SeekBar).progress = 40
            assertTrue(output.text.contains("50"))
            it.view("atlas-tab-1").performClick(); it.view("atlas-open-research").performClick()
            assertEquals(25, (it.view("atlas-physiology-hemoglobin") as SeekBar).progress)
        }
        scenario.recreate(); ready(scenario, "atlas-physiology-output")
        scenario.onActivity {
            assertEquals(250, (it.view("atlas-physiology-p50") as SeekBar).progress)
            assertEquals(25, (it.view("atlas-physiology-hemoglobin") as SeekBar).progress)
            it.onBackPressed(); it.onBackPressed(); it.open("blood")
            assertEquals(100, (it.view("atlas-physiology-hemoglobin") as SeekBar).progress)
            it.onBackPressed(); it.open("cell-erythrocyte")
            assertEquals(25, (it.view("atlas-physiology-hemoglobin") as SeekBar).progress)
            it.view("atlas-physiology-reset").performClick()
            kind.inputs.forEach { input -> assertEquals(input.initial - input.range.first,
                (it.view("atlas-physiology-${input.key}") as SeekBar).progress) }
        }
    }

    @Test fun publicPreviewCarriesBothSourcesAndCurrentTeachingInputs() = native { scenario ->
        scenario.onActivity {
            it.open("cell-erythrocyte")
            (it.view("atlas-physiology-hemoglobin") as SeekBar).progress = 25
            it.view("atlas-ask").performClick()
        }
        instrumentation.waitForIdleSync()
        val expected = HealthAtlasPhysiologyText.context(context, HealthAtlasPhysiology(kind).withInput(2, 75))
        val root = activeWindow(kind.source)
        assertTrue(root.findAccessibilityNodeInfosByText(kind.source).any { it.text?.contains(expected) == true })
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
    }

    @Test fun sourcesAndLocalizedUnitsRemainExplicit() = native { scenario ->
        scenario.onActivity { activity ->
            val body = HealthCenterViews(activity).column()
            var opened = ""
            HealthAtlasPhysiologyPanel(activity, body, kind, null) { opened = it }
            kind.sources.forEachIndexed { index, url ->
                body.tagged(if (index == 0) "atlas-physiology-source" else "atlas-physiology-source-$index")!!.performClick()
                assertEquals(url, opened)
            }
            for (language in listOf("en", "zh")) {
                val config = android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale(language)) }
                val localized = context.createConfigurationContext(config)
                val text = HealthAtlasPhysiologyText.context(localized, HealthAtlasPhysiology(kind))
                assertFalse(text.contains("%%")); assertTrue(text.contains("g/L")); assertTrue(text.contains("mL O₂/dL"))
                assertTrue(text.contains(localized.getString(R.string.health_atlas_model_synthetic)))
                kind.sources.forEach { assertTrue(text.contains(it)) }
            }
        }
    }

    @Test fun teachingValuesCannotLeakIntoOtherAnatomyOrResearchTopics() {
        val atlas = HealthBodyAtlas.load(context)
        val model = HealthAtlasPhysiology(kind).withInput(2, 75)
        val redCell = atlas["cell-erythrocyte"]!!
        val included = HealthAtlasAgentContext.prompt(context, atlas, redCell, quantitative = model)
        assertTrue(included.contains(HealthAtlasPhysiologyText.context(context, model)))
        for (id in listOf("cell-neuron", "cell-neutrophil", "lungs")) {
            val other = HealthAtlasAgentContext.prompt(context, atlas, atlas[id], quantitative = model)
            assertFalse(other.contains(kind.source))
        }
        for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING)) {
            assertFalse(HealthAtlasAgentContext.prompt(context, atlas, redCell, quantitative = model, topic = topic).contains(kind.source))
        }
    }

    @Test fun screenshotsShowCurveComponentsAndChangedParameters() = native { scenario ->
        scenario.onActivity { it.open("cell-erythrocyte") }
        capture("default")
        scenario.onActivity {
            (it.view("atlas-physiology-oxygen-pressure") as SeekBar).progress = 40
            (it.view("atlas-physiology-p50") as SeekBar).progress = 250
            (it.view("atlas-physiology-hemoglobin") as SeekBar).progress = 25
        }
        capture("adjusted")
        scenario.onActivity {
            val scroll = it.view("atlas-scroll") as android.widget.ScrollView
            val target = it.view("atlas-physiology-source")
            val bounds = android.graphics.Rect(0, 0, target.width, target.height)
            scroll.offsetDescendantRectToMyCoords(target, bounds)
            scroll.scrollTo(0, bounds.top + scroll.scrollY)
        }
        capture("sources-and-process")
    }
}
