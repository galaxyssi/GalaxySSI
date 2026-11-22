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

class HealthAtlasDigestiveDeviceTest {
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
        try { File(context.getExternalFilesDir(null), "body-atlas-digestive-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }

    @Test fun platesBelongToTheirOwnersAndHaveVisibleLocalizedLandmarks() {
        val chinese = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocale(Locale.SIMPLIFIED_CHINESE)
        })
        val english = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocale(Locale.ENGLISH)
        })
        val atlas = HealthBodyAtlas.load(english)
        val plates = HealthAtlasDigestivePlates.all
        assertEquals(14, plates.size)
        assertEquals(27, plates.sumOf { it.features.size })
        assertEquals(4, plates.sumOf { it.markers.size })
        assertEquals(14, plates.map { it.drawable }.toSet().size)
        for (plate in plates) {
            val owner = requireNotNull(plate.owner)
            assertEquals(if (owner.startsWith("cell-")) HealthAtlasKind.CELL else HealthAtlasKind.ORGAN, atlas[owner]?.kind)
            assertSame(plate, HealthAtlasPlates.forId(owner))
            assertTrue(plate.markers.all { atlas[it.id] != null })
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
        for (cell in atlas.items.filter { it.kind == HealthAtlasKind.CELL && it.systems.any { system ->
            system == "gut" || system == "digestive"
        } }) assertEquals(cell.id, HealthAtlasPlates.forId(cell.id)?.owner)
    }

    @Test fun pancreasRoutesAndSyntheticMixRestoreAndDrillIntoIslet() = native { scenario ->
        scenario.onActivity {
            it.open("pancreas"); it.openAtlasModelDetails()
            assertTrue(it.view("atlas-pancreatic-route-duct").isSelected)
            assertTrue(it.view("atlas-pancreatic-route-blood").isSelected)
            it.view("atlas-process-stage-2").performClick()
            assertTrue(it.view("atlas-pancreatic-route-duct").isSelected)
            assertFalse(it.view("atlas-pancreatic-route-blood").isSelected)
            (it.view("atlas-physiology-bicarb-flow") as SeekBar).progress = 0
            assertTrue((it.view("atlas-physiology-output") as TextView).text.contains("20 mmol/L"))
        }
        capture("pancreas", scenario.localized(R.string.health_atlas_digestive_pancreas_title))
        scenario.recreate(); ready(scenario, "atlas-pancreatic-routes")
        scenario.onActivity {
            assertEquals(2, (it.view("atlas-pancreatic-routes") as HealthAtlasPancreaticRoutes).stage)
            assertEquals(0, (it.view("atlas-physiology-bicarb-flow") as SeekBar).progress)
            it.view("atlas-process-stage-3").performClick()
            assertFalse(it.view("atlas-pancreatic-route-duct").isSelected)
            assertTrue(it.view("atlas-pancreatic-route-blood").isSelected)
            val atlas = HealthBodyAtlas.load(it)
            val prompt = HealthAtlasAgentContext.prompt(it, atlas, atlas["pancreas"],
                simulation = HealthAtlasSimulation(phase = .75f),
                quantitative = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.BICARBONATE_MIX))
            assertTrue(prompt.contains(it.getString(R.string.health_atlas_digestive_routes_endo_chain)))
            assertTrue(prompt.contains(it.getString(R.string.health_atlas_digestive_bicarb_scope)))
            it.view("atlas-pancreatic-route-blood").performClick()
            assertNotNull(it.view("atlas-feature-islet-capillary"))
            assertNull(it.window.decorView.tagged("atlas-physiology-bicarb-flow"))
        }
        val capillary = scenario.localized(R.string.health_atlas_digestive_islet_capillary)
        capture("islet", capillary)
        scenario.onActivity { assertTrue(it.view("atlas-feature-islet-capillary").performClick()) }
        awaitVisibleText(scenario.localized(R.string.health_atlas_digestive_islet_capillary_detail))
    }

    @Test fun allFourIsletStagesUseTheSelectedCellAndNeverInheritDuctalInputs() = native { scenario ->
        scenario.onActivity {
            it.open("pancreatic-islets")
            for (id in HealthAtlasIsletStages.CELL_IDS) assertNotNull(it.view("atlas-hotspot-$id"))
            it.openAtlasModelDetails()
            for ((index, id) in HealthAtlasIsletStages.CELL_IDS.withIndex()) {
                it.view("atlas-process-stage-$index").performClick()
                assertEquals(index, (it.view("atlas-islet-stages") as HealthAtlasIsletStages).stage)
                assertNull(it.window.decorView.tagged("atlas-physiology-bicarb-flow"))
                it.view("atlas-islet-selected-cell").performClick()
                assertNotNull(it.view("atlas-art-image"))
                val atlas = HealthBodyAtlas.load(it)
                assertTrue(it.view("atlas-art-image").contentDescription.contains(requireNotNull(atlas[id]).name))
                it.onBackPressed()
                assertEquals(index, (it.view("atlas-islet-stages") as HealthAtlasIsletStages).stage)
            }
        }
        capture("islet-function", scenario.localized(R.string.health_atlas_digestive_islets_title))
    }
}
