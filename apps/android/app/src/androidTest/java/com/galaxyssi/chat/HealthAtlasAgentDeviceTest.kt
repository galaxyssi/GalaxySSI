package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasAgentDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(value: String): View? = if (tag == value) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(value) } else null
    private fun Activity.view(tag: String) = requireNotNull(window.decorView.tagged(tag)) { tag }
    private fun await(check: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        while (!check() && SystemClock.elapsedRealtime() < until) SystemClock.sleep(50)
        assertTrue("UI did not reach the expected state", check())
    }
    private fun native(seed: Boolean = true, test: (HealthOverviewDatabases, ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            if (seed) HealthRecordStore(context, names.records).use { store ->
                assertTrue(store.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "121", "diastolic" to "79"),
                    "mmHg", System.currentTimeMillis(), note = "PRIVATE_ATLAS_FIXTURE")) is HealthSaveResult.Saved)
            }
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario ->
                await { var loaded = false; scenario.onActivity { loaded = it.window.decorView.tagged("atlas-whole-art") != null }; loaded }
                scenario.onActivity { it.view("atlas-hotspot-heart").performClick() }
                test(names, scenario)
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>) = await {
        var value = false; scenario.onActivity { value = it.view("atlas-ask").isEnabled }; value
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(350)
        await { context.packageName == instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() }
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-agent-$name.png").outputStream().use {
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    @Test fun publicContextIncludesCardiacInputsAndCurrentStageWithoutPrivateRecords() {
        val atlas = HealthBodyAtlas.load(context)
        val model = HealthAtlasSimulation(100, 70, .5f)
        val prompt = HealthAtlasAgentContext.prompt(context, atlas, atlas["heart"], model)
        assertTrue(prompt.contains("100 bpm") && prompt.contains("70 mL") && prompt.contains("7 L/min"))
        assertTrue(prompt.contains(atlas.mechanism(atlas["heart"]!!).stages[2]))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_teaching_note)))
        assertFalse(prompt.contains("PRIVATE_ATLAS_FIXTURE"))
        val structure = HealthAtlasAgentContext.prompt(context, atlas, atlas["heart"])
        assertFalse(structure.contains("bpm"))
    }
    @Test fun researchPromptsCarryOnlyTheirOwnInputsAndSources() {
        val atlas = HealthBodyAtlas.load(context)
        val heart = atlas["heart"]!!
        val drugs = HealthAtlasAgentContext.prompt(context, atlas, heart, HealthAtlasSimulation(100, 70),
            topic = HealthAtlasResearchTopic.DRUGS, elimination = HealthAtlasElimination(8, 16))
        assertTrue(drugs.contains("25") && drugs.contains(HealthAtlasResearchSources.KINETICS))
        assertFalse(drugs.contains("bpm"))
        val aging = HealthAtlasAgentContext.prompt(context, atlas, heart, topic = HealthAtlasResearchTopic.AGING,
            elimination = HealthAtlasElimination(8, 16))
        assertTrue(aging.contains(HealthAtlasResearchSources.AGING))
        assertFalse(aging.contains(HealthAtlasResearchSources.KINETICS))
        val wrongModel = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.POTASSIUM)
        val scope = HealthAtlasAgentContext.prompt(context, atlas, heart, quantitative = wrongModel)
        assertFalse(scope.contains(wrongModel.kind.source))
        atlas.items.forEach { item ->
            HealthAtlasResearchTopic.entries.forEach { topic ->
                assertTrue(HealthAtlasAgentContext.prompt(context, atlas, item, topic = topic).length in 1..8000)
            }
        }
    }
    @Test fun heartConfirmationUsesVisibleInputsAndPausesItsAnimation() = native { _, scenario ->
        scenario.onActivity { activity ->
            activity.openAtlasModelDetails()
            (activity.view("atlas-parameter-first") as SeekBar).progress = 60
            activity.view("atlas-simulation-play").performClick()
            activity.view("atlas-ask").performClick()
            assertEquals(activity.getString(R.string.health_body_play), activity.view("atlas-simulation-play").contentDescription)
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            val roots = WindowInspector.getGlobalWindowViews()
            val message = roots.firstNotNullOfOrNull { it.findViewById<TextView>(android.R.id.message) }!!.text.toString()
            assertTrue(message.contains("100 bpm") && message.contains("70 mL") && message.contains("7 L/min"))
            assertFalse(message.contains("PRIVATE_ATLAS_FIXTURE"))
            roots.firstNotNullOfOrNull { it.findViewById<View>(android.R.id.button2) }!!.performClick()
        }
    }
    @Test fun pinnedValuesActionOpensOnlyCurrentMetricAndPeriodWithoutSendingAnything() = native { names, scenario ->
        scenario.onActivity { it.view("atlas-tab-2").performClick(); it.view("atlas-period-0").performClick() }
        ready(scenario)
        capture("values")
        val monitor = instrumentation.addMonitor(HealthAssistantActivity::class.java.name, null, false)
        var opened: Activity? = null
        try {
            scenario.onActivity {
                assertEquals(it.getString(R.string.health_atlas_compare), (it.view("atlas-ask") as TextView).text)
                it.view("atlas-ask").performClick()
            }
            opened = instrumentation.waitForMonitorWithTimeout(monitor, 15_000)
            val assistant = requireNotNull(opened)
            val handoff = requireNotNull(assistant.intent.healthTrendAnalysisHandoff())
            assertEquals(names, assistant.intent.healthNavigationDatabases())
            assertEquals(HealthMetric.BLOOD_PRESSURE, handoff.spec.metric)
            assertEquals("mmHg", handoff.spec.unit)
            assertEquals(LocalDate.now(ZoneId.systemDefault()), handoff.spec.last)
            assertEquals(handoff.spec.last.minusDays(6), handoff.spec.first)
            val preview = HealthTrendAnalysis.prepare(context, names, handoff)
            assertEquals(1L, preview.numericRecords)
            assertFalse(preview.payload().toString().contains("PRIVATE_ATLAS_FIXTURE"))
            instrumentation.runOnMainSync { assistant.view("health-assistant-calculate").performClick() }
            await { var result = false; instrumentation.runOnMainSync {
                result = assistant.window.decorView.tagged("health-trend-analysis-coverage") != null
            }; result }
            capture("scoped-analysis")
        } finally {
            opened?.let { instrumentation.runOnMainSync { it.finish() } }
            instrumentation.removeMonitor(monitor)
        }
    }
    @Test fun emptyValuesNeverFallBackToPublicQuestion() = native(seed = false) { _, scenario ->
        scenario.onActivity { it.view("atlas-tab-2").performClick() }
        await { var loaded = false; scenario.onActivity { loaded = it.window.decorView.tagged("atlas-personal-chart") != null }; loaded }
        scenario.onActivity { assertFalse(it.view("atlas-ask").isEnabled) }
    }
    @Test fun changingToAnEmptyMetricDoesNotReuseThePreviousRecord() = native { _, scenario ->
        scenario.onActivity { it.view("atlas-tab-2").performClick() }; ready(scenario)
        fun choose(metric: HealthMetric) {
            scenario.onActivity { it.view("atlas-metric-${metric.name}").performClick() }
        }
        choose(HealthMetric.RESTING_HEART_RATE)
        await { var loaded = false; scenario.onActivity { loaded = it.window.decorView.tagged("atlas-personal-chart") != null }; loaded }
        scenario.onActivity { assertFalse(it.view("atlas-ask").isEnabled) }
        capture("empty-metric")
        choose(HealthMetric.BLOOD_PRESSURE); ready(scenario)
    }
    @Test fun permissionRevocationAndBackgroundClearThePinnedAction() = native { names, scenario ->
        scenario.onActivity { it.view("atlas-tab-2").performClick() }; ready(scenario)
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertFalse(it.view("atlas-ask").isEnabled) }
        scenario.moveToState(Lifecycle.State.RESUMED); ready(scenario)
        HealthPrivacyStore(context, names.privacy).use {
            it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
        }
        await { var disabled = false; scenario.onActivity { disabled = !it.view("atlas-ask").isEnabled }; disabled }
        scenario.onActivity { it.view("atlas-tab-0").performClick(); assertTrue(it.view("atlas-ask").isEnabled) }
    }
    @Test fun periodReloadImmediatelyInvalidatesThePreviousHandoff() = native { _, scenario ->
        scenario.onActivity { it.view("atlas-tab-2").performClick() }; ready(scenario)
        scenario.onActivity {
            it.view("atlas-period-2").performClick()
            assertFalse(it.view("atlas-ask").isEnabled)
        }
        ready(scenario)
        scenario.recreate()
        await { var restored = false; scenario.onActivity {
            restored = it.window.decorView.tagged("atlas-period-2")?.isSelected == true &&
                it.window.decorView.tagged("atlas-ask")?.isEnabled == true
        }; restored }
    }
}
