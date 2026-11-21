package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test
import java.io.File
import java.util.UUID

class HealthAtlasIllustrationStyleDeviceTest {
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
        try { File(context.getExternalFilesDir(null), "body-atlas-style-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    private fun ActivityScenario<HealthBodyAtlasActivity>.localized(id: Int): String {
        var value = ""
        onActivity { value = it.getString(id) }
        return value
    }


    @Test fun repaintedBitmapPlatesRetainResolutionAndTransparentAnatomyHotspots() {
        val frames = listOf(
            Triple(null, 1024, 1536), Triple("heart", 1086, 1448),
            Triple("lungs", 1254, 1254), Triple("liver", 1254, 1254),
            Triple("kidneys", 1254, 1254), Triple("brain", 1254, 1254),
            Triple("gut", 1024, 1536),
        )
        var anchors = 0
        for ((id, width, height) in frames) {
            val plate = requireNotNull(HealthAtlasPlates.forId(id))
            val art = requireNotNull(BitmapFactory.decodeResource(context.resources, plate.drawable))
            try {
                assertEquals(width, art.width)
                assertEquals(height, art.height)
                for (x in listOf(0, width - 1)) for (y in listOf(0, height - 1))
                    assertEquals("Unexpected background at $id", 0, Color.alpha(art.getPixel(x, y)))
                for (marker in plate.markers) {
                    val sample = art.getPixel((marker.x * width).toInt(), (marker.y * height).toInt())
                    assertTrue("Missing illustration at $id/${marker.id}", Color.alpha(sample) >= 200)
                    anchors++
                }
            } finally { art.recycle() }
        }
        assertEquals(26, anchors)
    }

    @Test fun frontIllustrationKeepsBrainNavigationLive() = native { scenario ->
        capture("body", scenario.localized(R.string.health_body_title))
        scenario.onActivity { it.view("atlas-hotspot-brain").performClick() }
        ready(scenario, "atlas-hotspot-cerebellum")
        capture("brain", scenario.localized(R.string.health_atlas_brain_name))
        scenario.onActivity {
            it.onBackPressed()
            assertNotNull(it.view("atlas-whole-art"))
            assertNotNull(it.view("atlas-hotspot-brain"))
        }
    }

    @Test fun directionalTrailGrowsAndClearsOnTheSameNativeDiagram() = native { scenario ->
        scenario.onActivity {
            it.open("esophagus"); it.view("atlas-tab-3").performClick()
            val diagram = it.view("atlas-section-diagram") as HealthAtlasSectionLessonView
            diagram.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            diagram.layout(0, 0, diagram.measuredWidth, diagram.measuredHeight)
            fun pixelsAt(phase: Float): Int {
                diagram.phase = phase
                val raster = Bitmap.createBitmap(diagram.width, diagram.height, Bitmap.Config.ARGB_8888)
                try {
                    diagram.draw(Canvas(raster))
                    var count = 0
                    for (x in 0 until raster.width) for (y in 0 until raster.height)
                        if (raster.getPixel(x, y) == 0xff285f82.toInt()) count++
                    return count
                } finally { raster.recycle() }
            }
            val start = pixelsAt(0f)
            val advancing = pixelsAt(.20f)
            assertTrue("Arrow must render at the start", start > 0)
            assertTrue("Traveled portion must grow", advancing > start)
            assertEquals("Rewinding removes the traveled line", start, pixelsAt(0f))
            it.view("atlas-process-stage-1").performClick()
            assertEquals(1, diagram.stage)
            assertSame(diagram, it.view("atlas-section-diagram"))
        }
        capture("path", scenario.localized(R.string.health_atlas_gut_section_esophagus_title))
    }
}
