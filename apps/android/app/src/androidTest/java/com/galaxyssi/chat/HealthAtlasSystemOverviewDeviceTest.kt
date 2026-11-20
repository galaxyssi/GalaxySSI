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
import android.widget.SeekBar
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasSystemOverviewDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val rasterOwners = listOf("sensory", "respiratory", "digestive", "endocrine", "immune", "skin")
    private val vectorOwners = listOf("nervous", "cardio", "male", "female")
    private val owners = rasterOwners + vectorOwners
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
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-systems-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun selectedSystemsOwnDistinctPlatesWithCanonicalChildrenAndSources() {
        val atlas = HealthBodyAtlas.load(context)
        assertEquals(10, HealthAtlasSystemPlates.all.size)
        assertEquals(10, owners.map { HealthAtlasPlates.forId(it)!!.drawable }.toSet().size)
        assertEquals(14, atlas.systems.count { HealthAtlasPlates.forId(it.id)?.owner == it.id })
        for (id in owners) {
            val plate = HealthAtlasPlates.forId(id)!!
            assertEquals(id, plate.owner)
            assertTrue(plate.source!!.startsWith("https://openstax.org/books/anatomy-and-physiology-2e/pages/"))
            assertTrue(plate.markers.all { it.id in atlas[id]!!.related })
            assertEquals(plate.markers.size, plate.markers.map { it.id }.toSet().size)
            assertEquals(context.getString(plate.viewLabel), plate.caption(context, atlas, atlas[id]))
        }
    }

    @Test fun bitmapsContainOpaqueHotspotsAndTransparentCorners() {
        for (id in rasterOwners) {
            val plate = HealthAtlasPlates.forId(id)!!
            val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
            try {
                assertTrue(bitmap.width >= 1024 && bitmap.height >= 1024)
                assertTrue(Color.alpha(bitmap.getPixel(0, 0)) < 5)
                assertTrue(Color.alpha(bitmap.getPixel(bitmap.width - 1, bitmap.height - 1)) < 5)
                for (marker in plate.markers) assertTrue("$id/${marker.id}", Color.alpha(bitmap.getPixel(
                    (marker.x * bitmap.width).toInt(), (marker.y * bitmap.height).toInt())) > 200)
                var solid = 0
                for (y in 0 until bitmap.height step 12) for (x in 0 until bitmap.width step 12)
                    if (Color.alpha(bitmap.getPixel(x, y)) > 200) solid++
                assertTrue("Blank $id", solid > 500)
            } finally { bitmap.recycle() }
        }
    }

    @Test fun vectorOverviewAnchorsAreOpaqueAndAllArtworkHasClearMargins() {
        val artwork = vectorOwners.map { HealthAtlasPlates.forId(it)!! }
        assertEquals(23, artwork.sumOf { it.markers.size })
        for (plate in artwork) {
            val height = if (plate.owner == "nervous" || plate.owner == "cardio") 560 else 400
            val bitmap = Bitmap.createBitmap(420, height, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, bitmap.width, height); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                assertEquals(0, Color.alpha(bitmap.getPixel(bitmap.width - 1, height - 1)))
                for (marker in plate.markers) assertTrue("${plate.owner}/${marker.id}",
                    Color.alpha(bitmap.getPixel((marker.x * bitmap.width).toInt(), (marker.y * height).toInt())) > 200)
            } finally { bitmap.recycle() }
        }
    }

    @Test fun dedicatedOrgansKeepTheirIdentityAndUnpicturedCellsNeverInheritSystemArt() {
        val atlas = HealthBodyAtlas.load(context)
        for (id in listOf("brain", "heart", "lungs", "pancreas", "liver", "kidneys", "alveoli"))
            assertEquals(id, HealthAtlasPlates.forId(id)!!.owner)
        assertNull(HealthAtlasPlates.forId("nails"))
        assertEquals("cell-langerhans-cell", HealthAtlasPlates.forId("cell-langerhans-cell")?.owner)
        for (id in listOf("parathyroid-glands", "cell-thyroid-follicular-cell", "thyroid-gland", "pituitary-gland", "adrenal-glands"))
            assertEquals(id, HealthAtlasPlates.forId(id)?.owner)
        assertEquals("pancreatic-islets", HealthAtlasPlates.forId("pancreatic-islets")?.owner)
        assertEquals("ear", HealthAtlasPlates.forId("cochlea")!!.owner)
        assertEquals("heart", HealthAtlasPlates.forId("heart-valves")!!.owner)
        for (plate in HealthAtlasSystemPlates.all) for (marker in plate.markers) {
            val selected = HealthAtlasPlates.forId(marker.id)!!
            if (selected.owner != marker.id)
                assertTrue(selected.caption(context, atlas, atlas[marker.id]).contains(atlas[selected.owner!!]!!.name))
        }
    }

    @Test fun translatedLargeLabelsFitAndRenderAtPhoneAndTabletWidths() = native { scenario ->
        scenario.onActivity { activity ->
            for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
                val config = Configuration(activity.resources.configuration).apply { setLocale(locale) }
                val atlas = HealthBodyAtlas.load(activity.createConfigurationContext(config))
                for (plate in HealthAtlasSystemPlates.all) for (width in listOf(720, 1080, 1600)) {
                    var selected = ""
                    val view = HealthAtlasLabeledImage(activity, plate, plate.owner!!, atlas, plate.owner) { selected = it.id }
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
                        label.performClick(); assertEquals(label.tag.toString().removePrefix("atlas-hotspot-"), selected)
                    }
                    if (plate.owner in listOf("skin", "immune")) {
                        val imageBounds = android.graphics.RectF(0f, 0f, view.image.drawable.intrinsicWidth.toFloat(),
                            view.image.drawable.intrinsicHeight.toFloat())
                        view.image.imageMatrix.mapRect(imageBounds)
                        val points = plate.markers.associate { it.id to android.graphics.PointF(
                            imageBounds.left + imageBounds.width() * it.x, imageBounds.top + imageBounds.height() * it.y) }
                        for ((otherId, path) in view.leaderPaths) {
                            assertTrue("Missing leader: $otherId", path.size >= 2)
                            for ((id, point) in points.filterKeys { it != otherId }) for ((start, end) in path.zipWithNext()) {
                                val dx = end.x - start.x; val dy = end.y - start.y
                                val t = (((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)).coerceIn(0f, 1f)
                                val distance = kotlin.math.hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
                                assertTrue("$id obscured by $otherId at $width", distance > HealthCenterViews(activity).dp(5))
                            }
                        }
                    }
                    for (background in listOf(Color.WHITE, Color.rgb(18, 20, 22))) {
                        val rendered = Bitmap.createBitmap(width, view.height, Bitmap.Config.ARGB_8888)
                        try {
                            rendered.eraseColor(background); view.draw(Canvas(rendered))
                            var changed = 0
                            for (y in 0 until view.height step 12) for (x in 0 until width step 12)
                                if (rendered.getPixel(x, y) != background) changed++
                            assertTrue(changed > 500)
                        } finally { rendered.recycle() }
                    }
                }
            }
        }
    }

    @Test fun everySystemCanOpenAChildAndRestoreTheCorrectPlate() = native { scenario ->
        val pairs = listOf("sensory" to "eye", "sensory" to "ear", "respiratory" to "larynx", "digestive" to "parotid-glands",
            "endocrine" to "thyroid-gland", "immune" to "spleen", "skin" to "sweat-glands",
            "nervous" to "brain", "cardio" to "aorta", "cardio" to "lungs",
            "male" to "epididymis", "female" to "uterine-tubes")
        for ((owner, child) in pairs) {
            val dedicated = when (child) {
                "eye" -> R.string.health_atlas_view_eye_section to "atlas-hotspot-lens"
                "ear" -> R.string.health_atlas_view_ear_section to "atlas-hotspot-middle-ear"
                "brain" -> R.string.health_atlas_view_lateral to "atlas-hotspot-cerebrum"
                "lungs" -> R.string.health_atlas_view_anterior to "atlas-hotspot-bronchi"
                "thyroid-gland" -> R.string.health_atlas_endocrine_thyroid_section_view to "atlas-hotspot-cell-thyroid-follicular-cell"
                "spleen" -> R.string.health_atlas_lymph_spleen_view to "atlas-hotspot-cell-macrophage"
                "sweat-glands" -> R.string.health_atlas_context_sweat_gland_view to "atlas-hotspot-cell-sweat-gland-secretory-cell"
                else -> null
            }
            fun assertChildPlate(activity: Activity) {
                if (dedicated != null) {
                    assertEquals(context.getString(dedicated.first),
                        (activity.view("atlas-art-caption") as TextView).text.toString())
                    assertNotNull(activity.view(dedicated.second))
                    activity.window.decorView.tagged("atlas-hotspot-$child")?.let { assertTrue(it.isSelected) }
                } else assertTrue(activity.view("atlas-hotspot-$child").isSelected)
            }
            scenario.onActivity {
                it.open(owner); it.view("atlas-hotspot-$child").performClick()
                assertChildPlate(it)
            }
            scenario.recreate(); ready(scenario, dedicated?.second ?: "atlas-hotspot-$child")
            scenario.onActivity {
                assertChildPlate(it)
                it.onBackPressed(); assertFalse(it.view("atlas-hotspot-$child").isSelected)
                it.onBackPressed(); assertNotNull(it.view("atlas-search"))
            }
        }
    }

    @Test fun systemToOrganToCellBackStackDoesNotAssignACellTheSkinPlate() = native { scenario ->
        scenario.onActivity {
            it.open("skin"); it.view("atlas-hotspot-epidermis").performClick()
            it.view("atlas-entry-cell-keratinocyte").performClick()
            assertNotNull(it.view("atlas-feature-keratin-filaments"))
            assertNull(it.window.decorView.tagged("atlas-hotspot-epidermis"))
            it.view("atlas-tab-1").performClick(); it.view("atlas-tab-3").performClick()
            assertNotNull(it.view("atlas-process-stage-0"))
        }
        scenario.recreate(); ready(scenario, "atlas-process-stage-0")
        scenario.onActivity {
            it.onBackPressed(); assertTrue(it.view("atlas-hotspot-epidermis").isSelected)
            it.onBackPressed(); assertFalse(it.view("atlas-hotspot-epidermis").isSelected)
        }
    }

    @Test fun publicAgentContextCarriesOnlySelectedCompositeCaptionAndSource() {
        for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            for (plate in HealthAtlasSystemPlates.all) {
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[plate.owner!!])
                assertTrue(prompt.contains(plate.caption(localized, atlas, atlas[plate.owner])))
                assertTrue(prompt.contains(plate.source!!))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_art_note)))
                for (other in HealthAtlasSystemPlates.all.filter { it != plate })
                    assertFalse(prompt.contains(localized.getString(other.viewLabel)))
            }
        }
    }

    @Test fun systemSimulationPausesOnBackgroundAndKeepsTheSelectedStage() = native { scenario ->
        scenario.onActivity { it.open("endocrine"); it.view("atlas-tab-3").performClick(); it.view("atlas-simulation-play").performClick() }
        SystemClock.sleep(220); scenario.moveToState(Lifecycle.State.CREATED)
        var saved = -1
        scenario.onActivity { saved = (it.view("atlas-simulation-progress") as SeekBar).progress }
        SystemClock.sleep(220); scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity {
            assertEquals(saved, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(it.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
            it.view("atlas-process-stage-2").performClick()
        }
        scenario.recreate(); ready(scenario, "atlas-process-stage-2")
        scenario.onActivity { assertTrue(it.view("atlas-process-stage-2").isSelected) }
    }

    @Test fun allTenSystemScreensAndSkinFullscreenRenderOnTheDevice() = native { scenario ->
        for (id in owners) {
            scenario.onActivity {
                it.open(id)
                assertNotNull(it.view("atlas-source-structure"))
                assertEquals(it.getString(HealthAtlasPlates.forId(id)!!.viewLabel), (it.view("atlas-art-caption") as TextView).text)
            }
            capture(id)
            if (id == "skin") {
                scenario.onActivity { it.view("atlas-fullscreen").performClick() }; capture("skin-fullscreen")
                instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
                instrumentation.waitForIdleSync(); SystemClock.sleep(250)
            }
            scenario.onActivity { it.onBackPressed() }
        }
    }

    @Test fun nerveTransitRestoresInputsAndDoesNotLeakIntoSpinalCordPhysiology() = native { scenario ->
        val kind = HealthAtlasPhysiologyKind.NERVE_TRANSIT
        val transit = HealthAtlasPhysiology(kind, listOf(120, 40))
        val value = HealthAtlasPhysiologyText.resultNumber(transit, transit.result) + " ms"
        scenario.onActivity {
            it.open("nervous"); it.view("atlas-hotspot-peripheral-nerves").performClick()
            it.view("atlas-tab-3").performClick()
            val scroll = it.view("atlas-scroll")
            (it.view("atlas-physiology-nerve-distance") as SeekBar).progress = 110
            (it.view("atlas-physiology-nerve-speed") as SeekBar).progress = 39
            assertEquals(value, (it.view("atlas-physiology-output") as TextView).text.toString())
            assertSame(scroll, it.view("atlas-scroll"))
        }
        scenario.recreate(); ready(scenario, "atlas-physiology-nerve-distance")
        scenario.onActivity {
            assertEquals(value, (it.view("atlas-physiology-output") as TextView).text.toString())
            val atlas = HealthBodyAtlas.load(it)
            val prompt = HealthAtlasAgentContext.prompt(it, atlas, atlas["peripheral-nerves"], quantitative = transit)
            assertTrue(prompt.contains(HealthAtlasPhysiologyText.result(it, transit)))
            assertTrue(prompt.contains(kind.source))
            assertTrue(HealthAtlasMetrics.forItem(atlas["peripheral-nerves"]!!).isEmpty())
            it.onBackPressed(); it.view("atlas-hotspot-spinal-cord").performClick()
            it.view("atlas-tab-3").performClick()
            assertNotNull(it.view("atlas-physiology-outside"))
            assertNull(it.window.decorView.tagged("atlas-physiology-nerve-distance"))
        }
    }
}
