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
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasSystemPlateDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val owners = listOf("urinary", "gut", "pancreas")
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue("Missing $key", found)
    }
    private fun Activity.open(id: String) {
        view(if (id in listOf("gut", "urinary")) "atlas-tab-1" else "atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }
    private fun activeWindow(text: String? = null): android.view.accessibility.AccessibilityNodeInfo {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName &&
                (text == null || root.findAccessibilityNodeInfosByText(text).isNotEmpty())) return root
            SystemClock.sleep(50)
        }
        error("Atlas window did not become accessible")
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(250); activeWindow()
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-system-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun platesHaveVisibleCanonicalMarkersAndTransparentBackgrounds() {
        val atlas = HealthBodyAtlas.load(context)
        assertEquals(3, owners.map { HealthAtlasPlates.forId(it)!!.drawable }.toSet().size)
        for (id in owners) {
            val plate = requireNotNull(HealthAtlasPlates.forId(id))
            assertEquals(id, plate.owner)
            assertTrue(plate.source!!.startsWith("https://openstax.org/books/anatomy-and-physiology-2e/pages/"))
            val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
            try {
                assertTrue(bitmap.width >= 1024 && bitmap.height >= 1024)
                for ((x, y) in listOf(0 to 0, bitmap.width - 1 to 0, 0 to bitmap.height - 1, bitmap.width - 1 to bitmap.height - 1))
                    assertTrue(Color.alpha(bitmap.getPixel(x, y)) < 10)
                var opaque = 0
                var transparent = 0
                for (y in 0 until bitmap.height step 8) for (x in 0 until bitmap.width step 8) {
                    val alpha = Color.alpha(bitmap.getPixel(x, y))
                    if (alpha > 200) opaque++
                    if (alpha < 10) transparent++
                }
                assertTrue(opaque > 1000 && transparent > 1000)
                for (marker in plate.markers) {
                    assertNotNull(atlas[marker.id])
                    assertTrue("Marker outside visible tissue: ${marker.id}", Color.alpha(bitmap.getPixel(
                        (marker.x * bitmap.width).toInt(), (marker.y * bitmap.height).toInt())) > 200)
                }
            } finally { bitmap.recycle() }
        }
        assertNull(HealthAtlasPlates.forId("pancreatic-islets"))
        assertNull(HealthAtlasPlates.forId("cell-pancreatic-acinar-cell"))
        assertNull(HealthAtlasPlates.forId("cell-podocyte"))
    }

    @Test fun newPlateLabelsFitPhoneAndTabletWidthsAndRemainClickable() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            for (id in owners) for (width in listOf(720, 1080, 1600)) {
                val plate = HealthAtlasPlates.forId(id)!!
                var selected = ""
                val view = HealthAtlasLabeledImage(activity, plate, id, atlas, id) { selected = it.id }
                val labels = (0 until view.childCount).map { view.getChildAt(it) }.filterIsInstance<TextView>()
                labels.forEach { it.textSize = 26f }
                view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                view.layout(0, 0, view.measuredWidth, view.measuredHeight)
                var bottom = 0
                for (label in labels.sortedBy { it.top }) {
                    assertTrue(label.top >= bottom && label.bottom <= view.height && label.right <= width)
                    assertTrue(label.height >= label.layout.height + label.compoundPaddingTop + label.compoundPaddingBottom)
                    bottom = label.bottom
                    if (!label.isSelected) { label.performClick(); assertEquals(label.tag.toString().removePrefix("atlas-hotspot-"), selected) }
                }
                for (background in listOf(Color.WHITE, Color.rgb(18, 20, 22))) {
                    val rendered = Bitmap.createBitmap(width, view.height, Bitmap.Config.ARGB_8888)
                    try {
                        rendered.eraseColor(background); view.draw(Canvas(rendered))
                        var changed = 0
                        for (y in 0 until view.height step 8) for (x in 0 until width step 8)
                            if (rendered.getPixel(x, y) != background) changed++
                        assertTrue("Blank image: $id/$width", changed > 500)
                    } finally { rendered.recycle() }
                }
            }
        }
    }

    @Test fun sharedPlateSelectionRestoresAcrossRecreationAndBack() = native { scenario ->
        for ((owner, child) in listOf("urinary" to "bladder", "gut" to "stomach", "pancreas" to "pancreatic-duct")) {
            scenario.onActivity {
                it.open(owner); assertNotNull(it.view("atlas-source-structure"))
                it.view("atlas-hotspot-$child").performClick()
                assertTrue(it.view("atlas-hotspot-$child").isSelected)
                val atlas = HealthBodyAtlas.load(it)
                assertEquals(HealthAtlasPlates.forId(child)!!.caption(it, atlas, atlas[child]),
                    (it.view("atlas-art-caption") as TextView).text.toString())
            }
            scenario.recreate(); ready(scenario, "atlas-hotspot-$child")
            scenario.onActivity {
                assertTrue(it.view("atlas-hotspot-$child").isSelected)
                assertFalse(it.view("atlas-hotspot-$child").performClick())
                it.onBackPressed()
                assertFalse(it.view("atlas-hotspot-$child").isSelected)
                it.onBackPressed(); assertNotNull(it.view("atlas-search"))
            }
        }
    }

    @Test fun urinaryOverviewOpensTheKidneySectionWithoutReplacingItsIdentity() = native { scenario ->
        scenario.onActivity {
            it.open("urinary"); it.view("atlas-hotspot-kidneys").performClick()
            assertNotNull(it.view("atlas-hotspot-renal-cortex"))
            assertEquals(it.getString(R.string.health_atlas_view_coronal), (it.view("atlas-art-caption") as TextView).text)
            it.view("atlas-hotspot-ureters").performClick()
            assertTrue(it.view("atlas-hotspot-ureters").isSelected)
            assertNotNull(it.view("atlas-hotspot-bladder"))
            it.onBackPressed(); assertNotNull(it.view("atlas-hotspot-renal-cortex"))
            it.onBackPressed(); assertNotNull(it.view("atlas-hotspot-bladder"))
        }
    }

    @Test fun contextualArtworkAndSourcesCarryIntoPublicAgentPreview() = native { scenario ->
        scenario.onActivity { it.open("pancreatic-duct"); it.view("atlas-ask").performClick() }
        val plate = HealthAtlasPlates.forId("pancreatic-duct")!!
        val root = activeWindow(plate.source)
        val atlas = HealthBodyAtlas.load(context)
        val prompt = HealthAtlasAgentContext.prompt(context, atlas, atlas["pancreatic-duct"])
        assertTrue(prompt.contains(plate.caption(context, atlas, atlas["pancreatic-duct"])))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_art_note)))
        assertTrue(root.findAccessibilityNodeInfosByText(plate.source).any { it.text?.contains(prompt) == true })
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
        assertTrue(HealthAtlasMetrics.forItem(atlas["pancreatic-duct"]!!).isEmpty())
        assertFalse(HealthAtlasMetrics.forItem(atlas["pancreas"]!!).isEmpty())
    }

    @Test fun systemAndOrganScreensRenderTheirOwnIllustrations() = native { scenario ->
        for (id in owners) {
            scenario.onActivity { it.open(id) }
            capture(id)
            var description = ""
            scenario.onActivity {
                description = it.view("atlas-art-image").contentDescription.toString()
                it.view("atlas-fullscreen").performClick()
            }
            fun imageIn(node: android.view.accessibility.AccessibilityNodeInfo?): Boolean {
                if (node == null) return false
                if (node.className == "android.widget.ImageView" && node.contentDescription?.toString() == description) return true
                return (0 until node.childCount).any { imageIn(node.getChild(it)) }
            }
            assertTrue(imageIn(activeWindow(description)))
            capture("$id-fullscreen")
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            instrumentation.waitForIdleSync()
            val deadline = SystemClock.elapsedRealtime() + 5000
            var focused = false
            while (!focused && SystemClock.elapsedRealtime() < deadline) {
                scenario.onActivity { focused = it.hasWindowFocus() }
                if (!focused) SystemClock.sleep(50)
            }
            assertTrue(focused)
            scenario.onActivity {
                assertEquals(description, it.view("atlas-art-image").contentDescription.toString())
                it.onBackPressed()
            }
        }
    }
}
