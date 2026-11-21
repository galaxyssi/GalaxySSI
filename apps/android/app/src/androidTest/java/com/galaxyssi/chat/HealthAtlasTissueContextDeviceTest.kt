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

class HealthAtlasTissueContextDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun Activity.open(id: String) {
        view(if (id.startsWith("cell-")) "atlas-tab-3" else "atlas-tab-2").performClick()
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
        try { File(context.getExternalFilesDir(null), "body-atlas-context-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }

    @Test fun allMicroscopicCatalogueEntriesUseTheirOwnDistinctPlates() {
        val atlas = HealthBodyAtlas.load(context)
        val cells = atlas.items.filter { it.kind == HealthAtlasKind.CELL }
        assertEquals(107, cells.size)
        val drawings = cells.map { item ->
            val plate = requireNotNull(HealthAtlasPlates.forId(item.id)) { item.id }
            assertEquals(item.id, plate.owner)
            assertEquals(item.id, atlas.mechanism(item).id)
            assertTrue(atlas.mechanism(item).source.startsWith("https://"))
            plate.drawable
        }
        assertEquals(cells.size, drawings.toSet().size)
        val fragment = requireNotNull(HealthAtlasPlates.forId("fragment-platelet"))
        assertEquals("fragment-platelet", fragment.owner)
        assertFalse(fragment.drawable in drawings)
    }

    @Test fun newPlateLandmarksAreOnTheArtAndLocalized() {
        val english = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.ENGLISH) })
        val chinese = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) })
        val atlas = HealthBodyAtlas.load(english)
        val plates = HealthAtlasTissueContextPlates.all
        assertEquals(25, plates.size)
        assertEquals(53, plates.sumOf { it.features.size })
        assertEquals(4, plates.sumOf { it.markers.size })
        for (plate in plates) {
            val owner = requireNotNull(plate.owner)
            assertNotNull(atlas[owner])
            assertSame(plate, HealthAtlasPlates.forId(owner))
            assertNotNull(plate.source)
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
    }

    @Test fun nailAndSebaceousCutawaysExposeTheRightStructuresAndLinks() = native { scenario ->
        scenario.onActivity {
            it.open("nails")
            for (feature in listOf("fold", "matrix", "plate", "bed", "free-edge"))
                assertNotNull(it.view("atlas-feature-nail-$feature"))
            assertNotNull(it.view("atlas-layers"))
            assertNotNull(it.view("atlas-fullscreen"))
        }
        capture("nail-lengthwise", scenario.localized(R.string.health_atlas_context_nail_section))
        scenario.onActivity { it.view("atlas-feature-nail-matrix").performClick() }
        awaitVisibleText(scenario.localized(R.string.health_atlas_context_nail_matrix_detail))
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        instrumentation.waitForIdleSync()
        scenario.onActivity {
            assertNotNull(it.view("atlas-feature-nail-matrix"))
            it.onBackPressed()
            it.open("sebaceous-glands")
            assertNotNull(it.view("atlas-feature-sebaceous-duct"))
            assertNotNull(it.view("atlas-feature-sebaceous-lobules"))
        }
        capture("sebaceous-gland", scenario.localized(R.string.health_atlas_context_sebaceous_section))
        scenario.onActivity {
            it.view("atlas-hotspot-cell-sebocyte").performClick()
            assertNotNull(it.view("atlas-feature-sebocyte-lipid"))
            it.onBackPressed()
            it.view("atlas-hotspot-hair-follicles").performClick()
            assertNotNull(it.view("atlas-feature-hair-section-papilla"))
            it.onBackPressed()
            assertNotNull(it.view("atlas-feature-sebaceous-lobules"))
        }
    }

    @Test fun sweatAnimationAndHeatModelRestoreIndependentlyOfTheCell() = native { scenario ->
        scenario.onActivity {
            it.open("sweat-glands")
            assertNotNull(it.view("atlas-feature-sweat-pore"))
            it.view("atlas-hotspot-cell-sweat-gland-secretory-cell").performClick()
            assertNotNull(it.view("atlas-feature-eccrine-secretory-apex"))
            it.view("atlas-tab-3").performClick()
            assertNull(it.window.decorView.tagged("atlas-physiology-sweat-evaporated"))
            it.onBackPressed()
            it.view("atlas-tab-3").performClick()
            val diagram = it.view("atlas-sweat-diagram") as HealthAtlasSweatView
            diagram.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            diagram.layout(0, 0, diagram.measuredWidth, diagram.measuredHeight)
            fun frame() = Bitmap.createBitmap(diagram.width, diagram.height, Bitmap.Config.ARGB_8888).also {
                diagram.draw(Canvas(it))
            }
            val first = frame()
            it.view("atlas-process-stage-3").performClick()
            val last = frame()
            try { assertFalse(first.sameAs(last)) } finally { first.recycle(); last.recycle() }
            assertEquals(3, diagram.stage)
            assertTrue(diagram.contentDescription.toString().contains(it.getString(R.string.health_atlas_context_sweat_stage_3)))
            val scroll = it.view("atlas-scroll")
            (it.view("atlas-physiology-sweat-evaporated") as SeekBar).progress = 0
            assertEquals("0 W", (it.view("atlas-physiology-output") as TextView).text.toString())
            assertSame(scroll, it.view("atlas-scroll"))
            (it.view("atlas-physiology-sweat-evaporated") as SeekBar).progress = 75
        }
        capture("sweat", scenario.localized(R.string.health_atlas_context_sweat_title))
        scenario.recreate(); ready(scenario, "atlas-sweat-diagram")
        scenario.onActivity {
            assertEquals(3, (it.view("atlas-sweat-diagram") as HealthAtlasSweatView).stage)
            assertEquals(75, (it.view("atlas-physiology-sweat-evaporated") as SeekBar).progress)
            val atlas = HealthBodyAtlas.load(it)
            val scope = it.getString(R.string.health_atlas_context_evap_scope)
            val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.SWEAT_EVAPORATION).withInput(1, 75)
            assertTrue(HealthAtlasAgentContext.prompt(it, atlas, atlas["sweat-glands"], quantitative = model).contains(scope))
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas["hair-follicles"], quantitative = model).contains(scope))
        }
    }

    @Test fun hairOrganHasItsOwnStructureAndLinksToTheMatrixCell() = native { scenario ->
        scenario.onActivity {
            it.open("hair-follicles")
            assertNotNull(it.view("atlas-feature-hair-section-shaft"))
            assertNotNull(it.view("atlas-feature-hair-section-papilla"))
        }
        capture("hair", scenario.localized(R.string.health_atlas_context_hair_follicle_view))
        scenario.onActivity {
            it.view("atlas-hotspot-cell-hair-matrix-cell").performClick()
            assertNotNull(it.view("atlas-feature-hair-matrix-bulb"))
            assertNull(it.window.decorView.tagged("atlas-feature-hair-section-shaft"))
            it.onBackPressed(); it.view("atlas-tab-3").performClick()
            it.view("atlas-process-stage-2").performClick()
            val stage = (it.view("atlas-simulation-stage") as TextView).text
            assertTrue(stage.contains(it.getString(R.string.health_atlas_context_hair_stage_2)))
            assertNull(it.window.decorView.tagged("atlas-sweat-diagram"))
        }
    }
}
