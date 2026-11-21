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

class HealthAtlasSensoryDeviceTest {
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
        try { File(context.getExternalFilesDir(null), "body-atlas-sensory-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }

    @Test fun allSensoryAndNeuralCellsHaveOwnArtAndValidBilingualMarkers() {
        val english = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.ENGLISH) })
        val chinese = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) })
        val atlas = HealthBodyAtlas.load(english)
        val plates = HealthAtlasSensoryPlates.all
        assertEquals(16, plates.size)
        assertEquals(34, plates.sumOf { it.features.size })
        assertEquals(3, plates.sumOf { it.markers.size })
        assertEquals(16, plates.map { it.drawable }.toSet().size)
        for (plate in plates) {
            val owner = requireNotNull(plate.owner)
            assertNotNull(atlas[owner])
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
        for (cell in atlas.items.filter { it.kind == HealthAtlasKind.CELL && it.systems.any { system ->
            system == "sensory" || system == "nervous"
        } }) assertEquals(cell.id, HealthAtlasPlates.forId(cell.id)?.owner)
    }

    @Test fun retinaViewsSwitchAndRestoreWithoutChangingTheEyePage() = native { scenario ->
        scenario.onActivity {
            it.open("retina")
            assertTrue(it.view("atlas-view-0").isSelected)
            assertNotNull(it.view("atlas-feature-retina-light-direction"))
            assertNotNull(it.view("atlas-feature-retina-signal-direction"))
        }
        capture("layers", scenario.localized(R.string.health_atlas_sensory_retina_section_view))
        scenario.onActivity {
            it.view("atlas-view-1").performClick()
            assertTrue(it.view("atlas-hotspot-retina").isSelected)
        }
        scenario.recreate(); ready(scenario, "atlas-view-1")
        scenario.onActivity {
            assertTrue(it.view("atlas-view-1").isSelected)
            it.view("atlas-view-0").performClick()
            assertNotNull(it.view("atlas-hotspot-cell-rod-photoreceptor"))
            it.onBackPressed(); it.open("eye")
            assertNull(it.window.decorView.tagged("atlas-view-1"))
            assertNotNull(it.view("atlas-hotspot-retina"))
        }
    }

    @Test fun rodRelayUsesBothInterneuronsAndDoesNotLeakIntoConeStages() = native { scenario ->
        scenario.onActivity {
            it.open("retina"); it.view("atlas-tab-3").performClick()
            val path = it.view("atlas-retinal-path") as HealthAtlasRetinaPath
            val section = it.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            val atlas = HealthBodyAtlas.load(it)
            val mechanism = atlas.mechanism(requireNotNull(atlas["retina"]))
            for (i in 0..3) {
                it.view("atlas-retina-node-$i").performClick()
                assertEquals(i, path.stage)
                assertEquals(i, section.stage)
                assertTrue(section.contentDescription.contains(mechanism.stages[i]))
                assertEquals(mechanism.stages[i], (it.view("atlas-retina-step-text") as TextView).text.toString())
            }
            it.view("atlas-retina-node-2").performClick()
            assertNull(it.window.decorView.tagged("atlas-retina-open-cell-retinal-aii-amacrine-cell"))
            it.view("atlas-retina-node-1").performClick()
            assertNotNull(it.view("atlas-retina-open-cell-retinal-bipolar-cell"))
            assertNotNull(it.view("atlas-retina-open-cell-retinal-aii-amacrine-cell"))
        }
        capture("circuit", scenario.localized(R.string.health_atlas_sensory_retinal_path_title))
        scenario.recreate(); ready(scenario, "atlas-retinal-path")
        scenario.onActivity {
            assertEquals(1, (it.view("atlas-retinal-path") as HealthAtlasRetinaPath).stage)
            assertEquals(1, (it.view("atlas-section-diagram") as HealthAtlasSectionLessonView).stage)
            it.view("atlas-retina-open-cell-retinal-aii-amacrine-cell").performClick()
            assertNotNull(it.view("atlas-feature-aii-on-connection"))
            assertNull(it.window.decorView.tagged("atlas-retinal-path"))
            it.onBackPressed()
            assertTrue(it.view("atlas-retina-node-1").isSelected)
            val atlas = HealthBodyAtlas.load(it)
            val scope = it.getString(R.string.health_atlas_sensory_retinal_scope)
            val phase = HealthAtlasSimulation(phase = .25f)
            assertTrue(HealthAtlasAgentContext.prompt(it, atlas, atlas["retina"], simulation = phase).contains(scope))
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas["eye"], simulation = phase).contains(scope))
        }
    }

    @Test fun photonAbsorptionScopeAndControlsRemainLocalToTheRod() = native { scenario ->
        scenario.onActivity {
            it.open("cell-rod-photoreceptor"); it.view("atlas-tab-3").performClick()
            val scroll = it.view("atlas-scroll")
            val control = it.view("atlas-physiology-photon-mean") as SeekBar
            assertEquals(100, control.progress)
            control.progress = 0
            assertEquals("0 %", (it.view("atlas-physiology-output") as TextView).text.toString())
            control.progress = 200
            assertSame(scroll, it.view("atlas-scroll"))
            assertTrue((it.view("atlas-physiology-companion") as TextView).text.contains("%"))
        }
        capture("photon", scenario.localized(R.string.health_atlas_sensory_photon_title))
        scenario.recreate(); ready(scenario, "atlas-physiology-photon-mean")
        scenario.onActivity {
            assertEquals(200, (it.view("atlas-physiology-photon-mean") as SeekBar).progress)
            it.onBackPressed()
            it.open("cell-cone-photoreceptor"); it.view("atlas-tab-3").performClick()
            assertNull(it.window.decorView.tagged("atlas-physiology-photon-mean"))
        }
    }
}
