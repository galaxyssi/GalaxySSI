package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.EditText
import android.widget.SeekBar
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasEyeOpticsDeviceTest {
    private val instrument get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrument.targetContext
    private val kind = HealthAtlasPhysiologyKind.EYE_FOCUS
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(tag: String) = requireNotNull(window.decorView.tagged(tag)) { tag }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, tag: String) {
        val until = SystemClock.elapsedRealtime() + 15000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < until) {
            scenario.onActivity { found = it.window.decorView.tagged(tag) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue(tag, found)
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrument.uiAutomation
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(fixture)).use { ready(it, "atlas-whole-art"); block(it) }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }
    private fun Activity.openEye() {
        view("atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText("eye")
        view("atlas-entry-eye").performClick()
    }
    private fun Activity.input(key: String) = view("atlas-physiology-eye-$key") as SeekBar
    private fun Activity.optics() = view("atlas-eye-optics") as HealthAtlasEyeOpticsView
    private fun nodes(text: String): List<AccessibilityNodeInfo> {
        instrument.waitForIdleSync()
        val until = SystemClock.elapsedRealtime() + 6000
        while (SystemClock.elapsedRealtime() < until) {
            val root = instrument.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName) {
                val found = root.findAccessibilityNodeInfosByText(text)
                if (found.isNotEmpty()) return found
            }
            SystemClock.sleep(40)
        }
        error("Missing accessibility text: $text")
    }
    private fun capture(name: String, title: String) {
        nodes(title); SystemClock.sleep(350)
        val bitmap = requireNotNull(instrument.uiAutomation.takeScreenshot())
        try {
            File(context.getExternalFilesDir(null), "body-atlas-eye-$name.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { bitmap.recycle() }
    }

    @Test fun eyePlateTargetsOpenCanonicalEntriesAndKeepsContextInFullscreen() = native { scenario ->
        val data = HealthBodyAtlas.load(context)
        val plate = requireNotNull(HealthAtlasPlates.forId("eye"))
        assertEquals(HealthAtlasEyeOptics.ANATOMY_SOURCE, plate.source)
        scenario.onActivity { it.openEye() }
        capture("structure", context.getString(R.string.health_atlas_view_eye_section))
        scenario.onActivity { activity ->
            for (id in listOf("cornea", "lens", "retina")) {
                activity.view("atlas-hotspot-$id").performClick()
                assertEquals(data[id]!!.name, (activity.view("health-page-title") as TextView).text.toString())
                assertTrue((activity.view("atlas-art-caption") as TextView).text.contains(data["eye"]!!.name))
                assertTrue(activity.view("atlas-hotspot-$id").isSelected)
                activity.onBackPressed()
            }
            activity.view("atlas-fullscreen").performClick()
        }
        assertTrue(nodes(context.getString(R.string.health_atlas_view_eye_section)).any {
            it.className?.toString() == "android.widget.ImageView" && it.isVisibleToUser
        })
        assertEquals(R.drawable.health_atlas_eye_section, plate.drawable)
    }

    @Test fun controlsAndMatchActionUpdateTheDiagramInPlaceAndRestoreIndependently() = native { scenario ->
        scenario.onActivity {
            it.openEye(); it.view("atlas-tab-3").performClick()
            val scroll = it.view("atlas-scroll"); val diagram = it.optics()
            it.input("distance").progress = 0
            it.input("power").progress = 0
            assertEquals(HealthAtlasEyeOptics.FocusSide.BEHIND, diagram.eye.focusSide)
            it.input("power").progress = 1000
            assertEquals(HealthAtlasEyeOptics.FocusSide.IN_FRONT, diagram.eye.focusSide)
            it.view("atlas-eye-match-plane").performClick()
            assertEquals(782, it.input("power").progress)
            assertEquals(HealthAtlasEyeOptics.FocusSide.AT_PLANE, diagram.eye.focusSide)
            assertSame(scroll, it.view("atlas-scroll")); assertSame(diagram, it.optics())
        }
        scenario.recreate(); ready(scenario, "atlas-eye-optics")
        scenario.onActivity {
            assertEquals(782, it.input("power").progress)
            it.view("atlas-tab-0").performClick(); it.view("atlas-hotspot-lens").performClick()
            it.view("atlas-tab-3").performClick()
            assertEquals(HealthAtlasEyeOptics(), it.optics().eye)
            it.onBackPressed(); it.view("atlas-tab-1").performClick(); it.view("atlas-open-research").performClick()
            assertEquals(782, it.input("power").progress)
            it.view("atlas-physiology-reset").performClick()
            assertEquals(HealthAtlasEyeOptics(), it.optics().eye)
        }
    }

    @Test fun raysAndSectionDrawAtLargePhoneAndTabletWidthsInBothThemes() = native { scenario ->
        scenario.onActivity { activity ->
            for (mode in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                val configuration = Configuration(activity.resources.configuration).apply {
                    uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or mode
                }
                val themed = activity.createConfigurationContext(configuration)
                val drawing = requireNotNull(themed.getDrawable(R.drawable.health_atlas_eye_section))
                val bitmap = Bitmap.createBitmap(400, 280, Bitmap.Config.ARGB_8888)
                try {
                    drawing.setBounds(0, 0, 400, 280)
                    drawing.draw(Canvas(bitmap))
                    assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                    HealthAtlasPlates.forId("eye")!!.markers.forEach { marker ->
                        assertTrue(marker.id, Color.alpha(bitmap.getPixel((marker.x * 400).toInt(), (marker.y * 280).toInt())) > 200)
                    }
                } finally { bitmap.recycle() }
                val rays = HealthAtlasEyeOpticsView.RayDiagram(themed)
                rays.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                rays.layout(0, 0, rays.measuredWidth, rays.measuredHeight)
                val plot = Bitmap.createBitmap(rays.width, rays.height, Bitmap.Config.ARGB_8888)
                try {
                    rays.draw(Canvas(plot))
                    val pixels = IntArray(plot.width * plot.height)
                    plot.getPixels(pixels, 0, plot.width, 0, 0, plot.width, plot.height)
                    assertTrue(pixels.contains(themed.getColor(R.color.health_atlas_eye_ray)))
                    assertTrue(pixels.contains(themed.getColor(R.color.health_atlas_eye_retina)))
                } finally { plot.recycle() }
            }
            for (width in listOf(720, 1080, 1600)) {
                val optics = HealthAtlasEyeOpticsView(activity)
                for (i in 0 until optics.childCount) (optics.getChildAt(i) as? TextView)?.textSize = 26f
                optics.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                optics.layout(0, 0, width, optics.measuredHeight)
                for (i in 0 until optics.childCount) {
                    val child = optics.getChildAt(i)
                    assertTrue(child.left >= 0 && child.right <= width && child.bottom <= optics.height)
                    if (child is TextView) assertTrue(child.height >= child.layout.height + child.compoundPaddingTop + child.compoundPaddingBottom)
                }
                val rays = optics.tagged("atlas-eye-rays")!!
                fun draw() = Bitmap.createBitmap(rays.width, rays.height, Bitmap.Config.ARGB_8888).also { rays.draw(Canvas(it)) }
                optics.eye = HealthAtlasEyeOptics(.25, 55.0); val before = draw()
                optics.eye = HealthAtlasEyeOptics(6.0, 65.0); val after = draw()
                try {
                    assertFalse(before.sameAs(after))
                    val pixels = IntArray(after.width * after.height)
                    after.getPixels(pixels, 0, after.width, 0, 0, after.width, after.height)
                    assertTrue(pixels.count { Color.alpha(it) > 0 } > 1000)
                    assertTrue(rays.contentDescription.contains(activity.getString(R.string.health_atlas_eye_in_front)))
                } finally { before.recycle(); after.recycle() }
            }
        }
    }

    @Test fun localizedPromptsUseTheActualModelWithoutLeakingIntoOtherTopics() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val data = HealthBodyAtlas.load(localized)
            val model = HealthAtlasPhysiology(kind, listOf(25, 5500))
            val scope = localized.getString(R.string.health_atlas_eye_scope)
            for (id in listOf("eye", "lens")) {
                val prompt = HealthAtlasAgentContext.prompt(localized, data, data[id], quantitative = model)
                assertTrue(prompt.contains(scope))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_eye_behind)))
                assertTrue(prompt.contains(HealthAtlasEyeOptics.SOURCE))
            }
            for (topic in listOf(HealthAtlasResearchTopic.AGING, HealthAtlasResearchTopic.DRUGS))
                assertFalse(HealthAtlasAgentContext.prompt(localized, data, data["eye"], quantitative = model, topic = topic).contains(scope))
            assertFalse(HealthAtlasAgentContext.prompt(localized, data, data["retina"], quantitative = model).contains(scope))
        }
    }

    @Test fun actualPreviewIsCancellableAndOpticsCaptureShowsTheSelectedFocus() = native { scenario ->
        scenario.onActivity {
            it.openEye(); it.view("atlas-tab-3").performClick()
            it.input("distance").progress = 0; it.input("power").progress = 0
        }
        capture("behind", context.getString(R.string.health_atlas_eye_behind))
        scenario.onActivity {
            it.view("atlas-eye-match-plane").performClick()
            val command = it.view("atlas-eye-match-plane")
            command.requestRectangleOnScreen(Rect(0, 0, command.width, command.height), true)
        }
        capture("controls", context.getString(R.string.health_atlas_eye_match_plane))
        scenario.onActivity { it.view("atlas-ask").performClick() }
        val model = HealthAtlasPhysiology(kind, listOf(25, 6282))
        assertTrue(nodes(HealthAtlasEyeOptics.SOURCE).any { it.text?.contains(HealthAtlasPhysiologyText.context(context, model)) == true })
        assertTrue(nodes(context.getString(android.R.string.cancel)).any { it.performAction(AccessibilityNodeInfo.ACTION_CLICK) })
    }
}
