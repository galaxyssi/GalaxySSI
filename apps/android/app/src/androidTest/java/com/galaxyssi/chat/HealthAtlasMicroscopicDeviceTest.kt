package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
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
import java.util.Locale
import java.util.UUID

class HealthAtlasMicroscopicDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun View.texts(): List<String> = when (this) {
        is TextView -> listOf(text.toString())
        is ViewGroup -> (0 until childCount).flatMap { getChildAt(it).texts() }
        else -> emptyList()
    }
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun entries(atlas: HealthBodyAtlas) = atlas.items.filter {
        it.kind == HealthAtlasKind.CELL || it.kind == HealthAtlasKind.FRAGMENT
    }
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
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { ready(it, "atlas-whole-art"); block(it) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun Activity.open(id: String) {
        view("atlas-tab-3").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync()
        val atlas = HealthBodyAtlas.load(context)
        val title = atlas.mechanism(requireNotNull(atlas[name])).title
        val deadline = SystemClock.elapsedRealtime() + 5000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            ready = root != null && root.packageName?.toString() == context.packageName &&
                root.findAccessibilityNodeInfosByText(title).isNotEmpty()
            if (!ready) SystemClock.sleep(50)
        }
        assertTrue("Visible microscopic mechanism: $name", ready)
        SystemClock.sleep(350)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-microscopic-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun everyCellAndFragmentOwnsItsLocalizedMechanism() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val items = entries(atlas)
            assertEquals(108, items.size)
            assertEquals(108, items.map { atlas.mechanism(it).title }.toSet().size)
            assertEquals(108, items.map { atlas.mechanism(it).stages }.toSet().size)
            items.forEach {
                assertEquals(it.id, atlas.mechanism(it).id)
                assertEquals(it.kind.name.lowercase(Locale.ROOT), atlas.mechanism(it).kind)
            }
            val platelet = atlas["fragment-platelet"]!!
            assertEquals(HealthAtlasKind.FRAGMENT, platelet.kind)
            assertEquals(listOf(HealthMetric.PLATELETS), HealthAtlasMetrics.forItem(platelet))
            assertEquals("https://openstax.org/books/anatomy-and-physiology-2e/pages/18-5-hemostasis", atlas.mechanism(platelet).source)
            assertTrue(atlas.search("fragment-platelet", HealthAtlasKind.CELL).contains(platelet))
        }
    }

    @Test fun deletedReassignedAndDowngradedMicroscopicMechanismsAreRejected() {
        val atlas = HealthBodyAtlas.load(context)
        for (id in listOf("cell-dendritic-cell", "fragment-platelet")) {
            val inherited = atlas.items.map { if (it.id == id) it.copy(mechanism = atlas["immune"]!!.mechanism) else it }
            assertTrue(runCatching { HealthBodyAtlas(inherited, atlas.mechanisms.filterNot { it.id == id }) }.isFailure)
            assertTrue(runCatching { HealthBodyAtlas(atlas.items, atlas.mechanisms.filterNot { it.id == id }) }.isFailure)
            val downgraded = atlas.mechanisms.map { if (it.id == id) it.copy(kind = "generic") else it }
            assertTrue(runCatching { HealthBodyAtlas(atlas.items, downgraded) }.isFailure)
        }
        val wrong = atlas.items.map { if (it.id == "heart") it.copy(mechanism = "fragment-platelet") else it }
        assertTrue(runCatching { HealthBodyAtlas(wrong, atlas.mechanisms) }.isFailure)
        val wrongKind = atlas.mechanisms.map { if (it.id == "fragment-platelet") it.copy(kind = "cell") else it }
        assertTrue(runCatching { HealthBodyAtlas(atlas.items, wrongKind) }.isFailure)
    }

    @Test fun everyMicroscopicEntryRendersItsOwnFunctionAndSimulation() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        for (item in entries(atlas)) scenario.onActivity { activity ->
            activity.open(item.id)
            activity.view("atlas-tab-1").performClick()
            val model = atlas.mechanism(item)
            val functionText = activity.window.decorView.texts().joinToString("\n")
            assertTrue(item.id, functionText.contains(model.title))
            model.stages.forEach { assertTrue(item.id, functionText.contains(it)) }
            assertTrue(functionText.contains(context.getString(if (model.reference == null)
                R.string.health_atlas_reference_openstax else R.string.health_atlas_reference_pubmed)))
            activity.openAtlasModelDetails()
            val scroll = activity.view("atlas-scroll")
            val ask = activity.view("atlas-ask")
            for (stage in 0..3) {
                activity.view("atlas-process-stage-$stage").performClick()
                assertEquals(stage * 250, (activity.view("atlas-simulation-progress") as SeekBar).progress)
                assertTrue((activity.view("atlas-simulation-stage") as TextView).text.contains(model.stages[stage]))
                assertSame(scroll, activity.view("atlas-scroll")); assertSame(ask, activity.view("atlas-ask"))
            }
            activity.onBackPressed()
        }
    }

    @Test fun allPromptsCarryOnlyTheSelectedStageAndItsPublicSource() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            for (item in entries(atlas)) for (stage in 0..3) {
                val model = atlas.mechanism(item)
                val state = HealthAtlasSimulation(phase = stage / 4f)
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, item, simulation = state)
                assertTrue(prompt.contains(item.name)); assertTrue(prompt.contains(model.source))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_teaching_note)))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_stage, stage + 1, 4, model.stages[stage])))
                for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING)) {
                    val unrelated = HealthAtlasAgentContext.prompt(localized, atlas, item, simulation = state, topic = topic)
                    assertFalse(unrelated.contains(localized.getString(R.string.health_atlas_stage, stage + 1, 4, model.stages[stage])))
                }
            }
        }
    }

    @Test fun plateletStageRestoresWithoutLeakingToMegakaryocyte() = native { scenario ->
        scenario.onActivity { it.open("fragment-platelet"); it.openAtlasModelDetails(); it.view("atlas-process-stage-2").performClick() }
        scenario.recreate(); ready(scenario, "atlas-simulation-progress")
        scenario.onActivity {
            assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
            it.onBackPressed(); it.open("cell-megakaryocyte"); it.openAtlasModelDetails()
            assertEquals(0, (it.view("atlas-simulation-progress") as SeekBar).progress)
            it.onBackPressed(); it.open("fragment-platelet"); it.openAtlasModelDetails()
            assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
        }
    }

    @Test fun extendedCellPlaybackStopsInBackgroundAndResetsLocally() = native { scenario ->
        scenario.onActivity { it.open("cell-rod-photoreceptor"); it.openAtlasModelDetails(); it.view("atlas-simulation-play").performClick() }
        SystemClock.sleep(200); scenario.moveToState(Lifecycle.State.CREATED)
        var progress = -1
        scenario.onActivity { progress = (it.view("atlas-simulation-progress") as SeekBar).progress }
        SystemClock.sleep(200); scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity {
            assertEquals(progress, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(it.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
            it.view("atlas-process-stage-3").performClick(); it.view("atlas-simulation-reset").performClick()
            assertEquals(0, (it.view("atlas-simulation-progress") as SeekBar).progress)
        }
    }

    @Test fun representativeMicroscopicScreensHaveReadableNativeStages() = native { scenario ->
        for (id in listOf("fragment-platelet", "cell-rod-photoreceptor", "cell-thyroid-follicular-cell")) {
            scenario.onActivity { it.open(id); it.openAtlasModelDetails(); it.view("atlas-process-stage-1").performClick() }
            instrumentation.waitForIdleSync()
            capture(id)
            scenario.onActivity { it.onBackPressed() }
        }
    }
}
