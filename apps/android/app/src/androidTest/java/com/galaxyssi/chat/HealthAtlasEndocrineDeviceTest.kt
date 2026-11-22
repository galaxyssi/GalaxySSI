package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
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
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

class HealthAtlasEndocrineDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun Activity.open(id: String) {
        view("atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            var found = false
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (found) return
            SystemClock.sleep(50)
        }
        fail("Missing $key")
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun visibleText(text: String): Boolean {
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return false
        return root.packageName == context.packageName && root.findAccessibilityNodeInfosByText(text).isNotEmpty()
    }
    private fun awaitVisibleText(text: String) {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5_000
        while (SystemClock.elapsedRealtime() < deadline && !visibleText(text)) SystemClock.sleep(80)
        assertTrue("Missing visible text: $text", visibleText(text))
    }
    private fun capture(name: String, title: String) {
        awaitVisibleText(title)
        SystemClock.sleep(250)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(context.getExternalFilesDir(null), "body-atlas-endocrine-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }

    @Test fun everyEndocrineCellAndNewGlandOwnsALocalizedAnatomyPlate() {
        val chinese = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocale(Locale.SIMPLIFIED_CHINESE)
        })
        val english = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocale(Locale.ENGLISH)
        })
        val atlas = HealthBodyAtlas.load(english)
        val plates = HealthAtlasEndocrinePlates.all
        assertEquals(18, plates.size)
        assertEquals(18, plates.map { it.drawable }.toSet().size)
        assertEquals(37, plates.sumOf { it.features.size })
        assertEquals(4, plates.sumOf { it.markers.size })
        val glands = plates.filter { atlas[requireNotNull(it.owner)]?.kind == HealthAtlasKind.ORGAN }.map { it.owner }.toSet()
        assertEquals(HealthAtlasEndocrinePath.all.keys, glands)
        for (plate in plates) {
            val owner = requireNotNull(plate.owner)
            assertSame(plate, HealthAtlasPlates.forId(owner))
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                for (marker in plate.markers + plate.features.map { it.marker }) {
                    val x = (360 * marker.x).roundToInt().coerceIn(1, 358)
                    val y = (280 * marker.y).roundToInt().coerceIn(1, 278)
                    assertTrue("$owner/${marker.id}", (-1..1).any { dx -> (-1..1).any { dy ->
                        Color.alpha(bitmap.getPixel(x + dx, y + dy)) > 180
                    } })
                }
                for (key in plate.features.flatMap { listOf(it.title, it.explanation) }) {
                    assertTrue(chinese.getString(key).any { it in '\u4e00'..'\u9fff' })
                    assertNotEquals(english.getString(key), chinese.getString(key))
                }
            } finally { bitmap.recycle() }
        }
        for (cell in atlas.items.filter { it.kind == HealthAtlasKind.CELL && "endocrine" in it.systems })
            assertEquals(cell.id, HealthAtlasPlates.forId(cell.id)?.owner)
    }

    @Test fun thyroidCircuitAndFeedbackRestoreWithoutUsingPersonalTsh() = native { scenario ->
        scenario.onActivity {
            it.open("thyroid-gland")
            it.view("atlas-hotspot-cell-thyroid-parafollicular-cell").performClick()
            assertNotNull(it.view("atlas-feature-c-cell-granules"))
            it.openAtlasModelDetails()
            assertNull(it.window.decorView.tagged("atlas-endocrine-path"))
            assertNull(it.window.decorView.tagged("atlas-physiology-feedback-gain"))
            it.onBackPressed()
            it.openAtlasModelDetails()
            val scroll = it.view("atlas-scroll")
            it.view("atlas-endocrine-node-3").performClick()
            assertTrue(it.view("atlas-endocrine-node-3").isSelected)
            assertEquals(View.GONE, it.view("atlas-endocrine-open-node").visibility)
            (it.view("atlas-physiology-feedback-gain") as SeekBar).progress = 300
            assertEquals("20 %", (it.view("atlas-physiology-output") as TextView).text.toString())
            assertSame(scroll, it.view("atlas-scroll"))
        }
        capture("thyroid-path", scenario.localized(R.string.health_atlas_endocrine_thyroid_path_title))
        scenario.recreate(); ready(scenario, "atlas-endocrine-path")
        scenario.onActivity {
            assertEquals(3, (it.view("atlas-endocrine-path") as HealthAtlasEndocrinePathView).stage)
            assertEquals(300, (it.view("atlas-physiology-feedback-gain") as SeekBar).progress)
            val atlas = HealthBodyAtlas.load(it)
            val quantitative = requireNotNull(HealthAtlasPhysiology.restore("thyroid-gland", intArrayOf(80, 300)))
            val scope = it.getString(R.string.health_atlas_endocrine_feedback_scope)
            val prompt = HealthAtlasAgentContext.prompt(it, atlas, atlas["thyroid-gland"],
                simulation = HealthAtlasSimulation(phase = .75f), quantitative = quantitative)
            assertTrue(prompt.contains(scope))
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas["parathyroid-glands"],
                simulation = HealthAtlasSimulation(phase = .75f), quantitative = quantitative).contains(scope))
            it.view("atlas-endocrine-node-1").performClick()
            it.view("atlas-endocrine-open-node").performClick()
            assertNotNull(it.view("atlas-feature-thyrotroph-hormone"))
            it.onBackPressed()
            assertTrue(it.view("atlas-endocrine-node-1").isSelected)
        }
    }

    @Test fun adrenalHasIndependentBranchNodesAndOpensTheMedullaCell() = native { scenario ->
        scenario.onActivity {
            it.open("adrenal-glands")
            assertNotNull(it.view("atlas-feature-adrenal-cortex"))
            assertNotNull(it.view("atlas-feature-adrenal-medulla"))
            it.openAtlasModelDetails()
            it.view("atlas-endocrine-node-3").performClick()
            assertEquals(it.getString(R.string.health_atlas_endocrine_adrenal_path_3),
                (it.view("atlas-endocrine-current") as TextView).text.toString())
            assertNull(it.window.decorView.tagged("atlas-physiology-feedback-gain"))
        }
        capture("adrenal-path", scenario.localized(R.string.health_atlas_endocrine_adrenal_path_title))
        scenario.onActivity {
            it.view("atlas-endocrine-open-node").performClick()
            assertNotNull(it.view("atlas-feature-chroma-vesicles"))
            it.onBackPressed()
            assertTrue(it.view("atlas-endocrine-node-3").isSelected)
        }
    }

    @Test fun parathyroidAndPituitaryUseDistinctStagesAndSources() = native { scenario ->
        val glands = listOf(
            Triple("parathyroid-glands", "atlas-feature-para-pair-upper", R.string.health_atlas_endocrine_parathyroid_path_title),
            Triple("pituitary-gland", "atlas-feature-pit-posterior", R.string.health_atlas_endocrine_pituitary_path_title),
        )
        for ((owner, landmark, label) in glands) {
            scenario.onActivity {
                it.open(owner)
                assertNotNull(it.view(landmark))
                it.openAtlasModelDetails()
                val atlas = HealthBodyAtlas.load(it)
                val mechanism = atlas.mechanism(requireNotNull(atlas[owner]))
                assertEquals(owner, mechanism.id)
                for (i in 0..3) {
                    it.view("atlas-endocrine-node-$i").performClick()
                    assertEquals(mechanism.stages[i], (it.view("atlas-endocrine-current") as TextView).text.toString())
                }
            }
            capture(owner, scenario.localized(label))
            scenario.onActivity { it.onBackPressed() }
        }
    }
}
