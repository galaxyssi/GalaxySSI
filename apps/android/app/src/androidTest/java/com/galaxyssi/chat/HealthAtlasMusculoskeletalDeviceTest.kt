package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasMusculoskeletalDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
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
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun Activity.open(id: String) {
        view("atlas-tab-1").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(250)
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() != context.packageName &&
            SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(50)
        assertEquals(context.packageName, instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString())
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-musculoskeletal-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun fourPlatesHaveDistinctStableKeysAndCanonicalChildren() {
        val atlas = HealthBodyAtlas.load(context)
        val plates = HealthAtlasMusculoskeletalPlates.all
        assertEquals(4, plates.size)
        assertEquals(4, plates.map { it.viewKey }.toSet().size)
        assertEquals(4, plates.map { it.drawable }.toSet().size)
        for (id in listOf("skeletal", "muscle")) assertEquals(2, HealthAtlasPlates.viewsForId(id).size)
        for (plate in plates) {
            assertTrue(plate.source!!.startsWith("https://openstax.org/"))
            assertTrue(plate.markers.all { it.id in atlas[plate.owner!!]!!.related })
            assertEquals(plate.markers.size, plate.markers.map { it.id }.toSet().size)
            assertEquals(plate, HealthAtlasPlates.forId(plate.owner, plate.viewKey))
        }
    }

    @Test fun onlyDepictedStructuresCanUseEachView() {
        for (plate in HealthAtlasMusculoskeletalPlates.all) for (marker in plate.markers) {
            val views = HealthAtlasPlates.viewsForId(marker.id)
            assertTrue(views.any { it.viewKey == plate.viewKey && it.drawable == plate.drawable })
            assertTrue(views.all { it.owner == marker.id || it.markers.any { target -> target.id == marker.id } })
        }
        for (id in listOf("erector-spinae", "soleus", "cartilage", "ligaments", "radius",
            "cell-skeletal-myocyte", "cell-osteoblast", "cell-chondrocyte"))
            assertEquals(id, HealthAtlasPlates.forId(id)!!.owner)
        assertEquals("respiratory", HealthAtlasPlates.forId("diaphragm")!!.owner)
        assertEquals("bone-marrow", HealthAtlasPlates.forId("bone-marrow")!!.owner)
        assertEquals("atlas-detail-trapezius", HealthAtlasPlates.forId("trapezius", "muscle-anterior")!!.viewKey)
        assertEquals("muscle-posterior", HealthAtlasPlates.forId("trapezius", "muscle-posterior")!!.viewKey)
        assertEquals("skeletal-anterior", HealthAtlasPlates.forId("skeletal", "muscle-posterior")!!.viewKey)
    }

    @Test fun markersSitOnOpaqueArtworkAndEdgesRemainTransparent() {
        for (plate in HealthAtlasMusculoskeletalPlates.all) {
            val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
            try {
                assertTrue(bitmap.width >= 800 && bitmap.height >= 1500)
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                assertEquals(0, Color.alpha(bitmap.getPixel(bitmap.width - 1, bitmap.height - 1)))
                for (marker in plate.markers) assertTrue("${plate.viewKey}/${marker.id}", Color.alpha(bitmap.getPixel(
                    (marker.x * bitmap.width).toInt(), (marker.y * bitmap.height).toInt())) > 200)
            } finally { bitmap.recycle() }
        }
    }

    @Test fun viewSwitchUpdatesOnlyArtworkAndRetainsRootControls() = native { scenario ->
        scenario.onActivity {
            it.open("muscle")
            val scroll = it.view("atlas-scroll")
            val ask = it.view("atlas-ask")
            val tab = it.view("atlas-tab-1")
            it.view("atlas-view-1").performClick()
            assertSame(scroll, it.view("atlas-scroll")); assertSame(ask, it.view("atlas-ask")); assertSame(tab, it.view("atlas-tab-1"))
            assertTrue(it.view("atlas-view-1").isSelected)
            assertNotNull(it.view("atlas-hotspot-trapezius"))
            assertNull(it.window.decorView.tagged("atlas-hotspot-pectoralis-major"))
            it.view("atlas-view-0").performClick()
            assertNotNull(it.view("atlas-hotspot-pectoralis-major"))
        }
    }

    @Test fun posteriorSelectionSurvivesChildBackStackAndRecreation() = native { scenario ->
        scenario.onActivity {
            it.open("skeletal"); it.view("atlas-view-1").performClick()
            it.view("atlas-hotspot-vertebrae").performClick()
            assertTrue(it.view("atlas-view-0").isSelected)
            assertNotNull(it.view("atlas-feature-lumbar-segment-facet"))
            it.view("atlas-view-1").performClick()
            assertTrue(it.view("atlas-hotspot-vertebrae").isSelected)
        }
        scenario.recreate(); ready(scenario, "atlas-hotspot-vertebrae")
        scenario.onActivity {
            assertTrue(it.view("atlas-view-1").isSelected)
            assertTrue(it.view("atlas-hotspot-vertebrae").isSelected)
            it.view("atlas-view-0").performClick()
            assertNotNull(it.view("atlas-feature-lumbar-segment-facet"))
            it.onBackPressed(); assertTrue(it.view("atlas-view-1").isSelected)
        }
        scenario.recreate(); ready(scenario, "atlas-view-1")
        scenario.onActivity { assertTrue(it.view("atlas-view-1").isSelected) }
    }

    @Test fun systemsRememberIndependentViewsAcrossFunctionAndSimulationTabs() = native { scenario ->
        scenario.onActivity {
            it.open("muscle"); it.view("atlas-view-1").performClick()
            it.view("atlas-tab-1").performClick(); assertTrue(it.view("atlas-view-1").isSelected)
            it.view("atlas-tab-3").performClick(); it.view("atlas-process-stage-2").performClick()
            it.view("atlas-tab-0").performClick(); assertTrue(it.view("atlas-view-1").isSelected)
            it.onBackPressed(); it.open("skeletal"); assertTrue(it.view("atlas-view-0").isSelected)
            it.onBackPressed(); it.open("muscle"); assertTrue(it.view("atlas-view-1").isSelected)
        }
    }

    @Test fun returningToADedicatedCutawayRemainsSelectedAfterRecreation() = native { scenario ->
        scenario.onActivity {
            it.open("trapezius")
            assertTrue(it.view("atlas-view-0").isSelected)
            it.view("atlas-view-1").performClick()
            assertTrue(it.view("atlas-view-1").isSelected)
            it.view("atlas-view-0").performClick()
        }
        scenario.recreate(); ready(scenario, "atlas-view-0")
        scenario.onActivity { assertTrue(it.view("atlas-view-0").isSelected) }
    }

    @Test fun currentViewAndSourceAreHandedToThePublicAgentWithoutOtherViews() {
        for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            for (plate in HealthAtlasMusculoskeletalPlates.all) {
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[plate.owner!!], artworkView = plate.viewKey)
                assertTrue(prompt.contains(localized.getString(plate.viewLabel)))
                assertTrue(prompt.contains(plate.source!!))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_art_note)))
                for (other in HealthAtlasMusculoskeletalPlates.all.filter { it != plate })
                    assertFalse(prompt.contains(localized.getString(other.viewLabel)))
            }
        }
    }

    @Test fun largeLocalizedLabelsFitAndRenderOnLightAndDarkBackgrounds() = native { scenario ->
        scenario.onActivity { activity ->
            for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
                val atlas = HealthBodyAtlas.load(activity.createConfigurationContext(Configuration(activity.resources.configuration).apply { setLocale(locale) }))
                for (plate in HealthAtlasMusculoskeletalPlates.all) for (width in listOf(720, 1080, 1600)) {
                    var tapped = ""
                    val view = HealthAtlasLabeledImage(activity, plate, plate.viewKey!!, atlas, plate.owner) { tapped = it.id }
                    val labels = (0 until view.childCount).map { view.getChildAt(it) }.filterIsInstance<TextView>()
                    labels.forEach { it.textSize = 26f }
                    view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    view.layout(0, 0, width, view.measuredHeight)
                    var bottom = 0
                    for (label in labels.sortedBy { it.top }) {
                        assertTrue(label.top >= bottom && label.bottom <= view.height && label.right <= width)
                        assertTrue(label.height >= label.layout.height + label.compoundPaddingTop + label.compoundPaddingBottom)
                        bottom = label.bottom
                        label.performClick(); assertEquals(label.tag.toString().removePrefix("atlas-hotspot-"), tapped)
                    }
                    for (background in listOf(Color.WHITE, Color.rgb(18, 20, 22))) {
                        val bitmap = Bitmap.createBitmap(width, view.height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(background); view.draw(Canvas(bitmap))
                            var changed = 0
                            for (y in 0 until view.height step 12) for (x in 0 until width step 12)
                                if (bitmap.getPixel(x, y) != background) changed++
                            assertTrue(changed > 500)
                        } finally { bitmap.recycle() }
                    }
                }
            }
        }
    }

    @Test fun fourNativeViewsAndCurrentFullscreenRenderOnDevice() = native { scenario ->
        for (id in listOf("skeletal", "muscle")) {
            scenario.onActivity { it.open(id) }; capture("$id-front")
            scenario.onActivity { it.view("atlas-view-1").performClick() }; capture("$id-back")
            scenario.onActivity { it.view("atlas-fullscreen").performClick() }
            capture("$id-fullscreen")
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            instrumentation.waitForIdleSync(); SystemClock.sleep(200)
            scenario.onActivity { assertTrue(it.view("atlas-view-1").isSelected); it.onBackPressed() }
        }
    }

    @Test fun muscleToCellKeepsItsOwnMechanismAndNoMisleadingWholeBodyArt() = native { scenario ->
        scenario.onActivity {
            it.open("muscle"); it.view("atlas-hotspot-biceps-brachii").performClick()
            assertTrue(it.view("atlas-view-0").isSelected)
            it.view("atlas-view-1").performClick()
            it.view("atlas-entry-cell-skeletal-myocyte").performClick()
            assertNotNull(it.view("atlas-feature-skeletal-striations"))
            assertNull(it.window.decorView.tagged("atlas-hotspot-biceps-brachii"))
            it.view("atlas-tab-3").performClick(); assertNotNull(it.view("atlas-process-stage-0"))
            it.onBackPressed(); assertTrue(it.view("atlas-hotspot-biceps-brachii").isSelected)
            it.onBackPressed(); assertTrue(it.view("atlas-view-0").isSelected)
        }
    }
}
