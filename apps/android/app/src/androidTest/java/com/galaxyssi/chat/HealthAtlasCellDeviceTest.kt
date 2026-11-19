package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
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
import java.util.Locale
import java.util.UUID

class HealthAtlasCellDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(value: String): View? = if (tag == value) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(value) } else null
    private fun Activity.view(tag: String) = requireNotNull(window.decorView.tagged(tag)) { tag }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario ->
                await(scenario, "atlas-whole-art"); block(scenario)
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun await(scenario: ActivityScenario<HealthBodyAtlasActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(tag) != null }
            if (!found) SystemClock.sleep(50)
        }
        assertTrue("Missing $tag", found)
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(350)
        val deadline = SystemClock.elapsedRealtime() + 5_000
        var owner = instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString()
        while (owner != context.packageName && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(50)
            owner = instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString()
        }
        assertEquals(context.packageName, owner)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-cell-$name.png").outputStream().use {
            image.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { image.recycle() }
    }
    @Test fun thirtyCellProcessesResolveInBothLocalesWithoutSharedStages() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val models = atlas.mechanisms.filter { it.kind == "cell" }
            assertEquals(30, models.size)
            assertEquals(30, models.map { it.title }.toSet().size)
            assertEquals(30, models.map { it.stages }.toSet().size)
            models.forEach {
                assertEquals(HealthAtlasKind.CELL, atlas[it.id]?.kind)
                assertEquals(it.id, atlas[it.id]?.mechanism)
                assertEquals(4, it.stages.size)
                assertTrue(it.stages.all(String::isNotBlank))
                assertTrue(it.source.startsWith("https://openstax.org/books/anatomy-and-physiology-2e/pages/"))
            }
        }
    }
    @Test fun cellMechanismOwnershipIsEnforcedAtLoadTime() {
        val atlas = HealthBodyAtlas.load(context)
        val wrong = atlas.items.map { if (it.id == "cell-neutrophil") it.copy(mechanism = "cell-erythrocyte") else it }
        assertTrue(runCatching { HealthBodyAtlas(wrong, atlas.mechanisms) }.isFailure)
        assertEquals(listOf(HealthMetric.RED_BLOOD_CELLS, HealthMetric.HEMOGLOBIN, HealthMetric.HEMATOCRIT),
            HealthAtlasMetrics.forItem(atlas["cell-erythrocyte"]!!))
        assertTrue(HealthAtlasMetrics.forItem(atlas["cell-neuron"]!!).isEmpty())
    }
    @Test fun cellPlatesAreDistinctTransparentAndNotAssignedToOtherCellTypes() {
        val ids = listOf("cell-erythrocyte", "cell-neuron")
        assertEquals(2, ids.map { HealthAtlasPlates.forId(it)!!.drawable }.toSet().size)
        for (id in ids) {
            val plate = requireNotNull(HealthAtlasPlates.forId(id))
            assertEquals(id, plate.owner)
            val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
            try {
                assertTrue(bitmap.width >= 512 && bitmap.height >= 512)
                assertTrue(Color.alpha(bitmap.getPixel(0, 0)) <= 5)
                var solid = 0
                var transparent = 0
                for (y in 0 until bitmap.height step 8) for (x in 0 until bitmap.width step 8) {
                    val alpha = Color.alpha(bitmap.getPixel(x, y))
                    if (alpha > 200) solid++
                    if (alpha < 5) transparent++
                }
                assertTrue("Blank plate: $id", solid > 500)
                assertTrue("Missing transparency: $id", transparent > 500)
            } finally { bitmap.recycle() }
        }
        assertNull(HealthAtlasPlates.forId("cell-astrocyte"))
        assertNull(HealthAtlasPlates.forId("cell-neutrophil"))
    }
    @Test fun everyCellStageIsFocusableAndFitsLargeText() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            for (model in atlas.mechanisms.filter { it.kind == "cell" }) {
                var selected = -1
                val process = HealthAtlasProcessView(activity, model) { selected = it }
                (0 until process.childCount).forEach { (process.getChildAt(it) as TextView).textSize = 26f }
                process.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                process.layout(0, 0, process.measuredWidth, process.measuredHeight)
                for (index in 0..3) {
                    val stage = process.getChildAt(index) as TextView
                    assertTrue(stage.isFocusable && stage.isClickable)
                    assertEquals("android.widget.Button", stage.accessibilityClassName)
                    assertTrue(stage.width >= HealthCenterViews(activity).dp(48))
                    assertTrue(stage.height >= stage.layout.height + stage.paddingTop + stage.paddingBottom)
                    assertTrue(stage.bottom <= process.height)
                    stage.performClick()
                    assertEquals(index, selected)
                    assertEquals(index / 4f, process.phase, 0f)
                    assertTrue(stage.isSelected)
                    assertEquals(1, (0 until process.childCount).count { process.getChildAt(it).isSelected })
                }
            }
        }
    }
    @Test fun cellScreensRenderAndSelectionRestoresAfterRecreation() = native { scenario ->
        for (id in listOf("cell-erythrocyte", "cell-neuron", "cell-neutrophil")) {
            scenario.onActivity {
                it.view("atlas-tab-3").performClick()
                (it.view("atlas-search") as EditText).setText(id)
                it.view("atlas-entry-$id").performClick()
                if (id != "cell-neutrophil") assertNotNull(it.view("atlas-art-image"))
            }
            capture("$id-structure")
            scenario.onActivity {
                it.view("atlas-tab-3").performClick()
                it.view("atlas-process-stage-2").performClick()
                assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
                val atlas = HealthBodyAtlas.load(it)
                assertTrue((it.view("atlas-simulation-stage") as TextView).text.contains(atlas.mechanism(atlas[id]!!).stages[2]))
            }
            instrumentation.waitForIdleSync()
            scenario.onActivity {
                val scroll = it.view("atlas-scroll") as android.widget.ScrollView
                val diagram = it.view("atlas-process")
                val bounds = android.graphics.Rect(0, 0, diagram.width, diagram.height)
                scroll.offsetDescendantRectToMyCoords(diagram, bounds)
                scroll.scrollTo(0, bounds.top + scroll.scrollY)
            }
            capture("$id-process")
            scenario.recreate()
            await(scenario, "atlas-simulation-progress")
            scenario.onActivity {
                assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
                assertTrue(it.view("atlas-process-stage-2").isSelected)
                it.onBackPressed()
            }
        }
    }
    @Test fun stageTapPausesPlaybackWithoutChangingOtherInputs() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick(); it.view("atlas-tab-3").performClick()
            (it.view("atlas-parameter-first") as SeekBar).progress = 60
            it.view("atlas-simulation-play").performClick()
        }
        SystemClock.sleep(150)
        scenario.onActivity { it.view("atlas-process-stage-1").performClick() }
        SystemClock.sleep(250)
        scenario.onActivity {
            assertEquals(250, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(60, (it.view("atlas-parameter-first") as SeekBar).progress)
            assertEquals(context.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
        }
    }
}
