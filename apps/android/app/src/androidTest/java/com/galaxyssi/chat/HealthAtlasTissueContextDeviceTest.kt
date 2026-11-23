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
        assertEquals(74, plates.size)
        assertEquals(256, plates.sumOf { it.features.size })
        assertEquals(41, plates.sumOf { it.markers.size })
        val tenocyteSection = HealthAtlasTenocyteTendonMatrixPlate.plate
        assertEquals(2, HealthAtlasPlates.viewsForId("cell-tenocyte").size)
        for (plate in plates + tenocyteSection) {
            val owner = requireNotNull(plate.owner)
            assertNotNull(atlas[owner])
            assertSame(plate, HealthAtlasPlates.forId(owner, plate.viewKey))
            assertNotNull(plate.source)
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals("$owner has artwork in the transparent corner", 0, Color.alpha(bitmap.getPixel(0, 0)))
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

    @Test fun sinusCutawayAndDrainagePlayWithoutReplacingEachOther() = native { scenario ->
        scenario.onActivity {
            it.open("paranasal-sinuses")
            for (feature in listOf("frontal", "ethmoid", "maxillary", "nasal-cavity", "inferior-conchae"))
                assertNotNull(it.view("atlas-feature-sinus-$feature"))
        }
        capture("sinus-coronal", scenario.localized(R.string.health_atlas_sinus_plate_caption))
        scenario.onActivity {
            it.view("atlas-tab-1").performClick()
            assertNotNull(it.view("atlas-function-sinus-drainage-art"))
            it.view("atlas-tab-0").performClick()
            assertNotNull(it.view("atlas-feature-sinus-maxillary"))
        }
    }

    @Test fun tasteBudShowsItsPoreAndLinksToSensoryCells() = native { scenario ->
        scenario.onActivity {
            it.open("taste-buds")
            assertNotNull(it.view("atlas-feature-taste-pore"))
            assertNotNull(it.view("atlas-feature-taste-afferent-contact"))
        }
        capture("taste-bud-cutaway", scenario.localized(R.string.health_atlas_taste_buds_plate_caption))
        scenario.onActivity {
            it.view("atlas-hotspot-cell-taste-receptor-cell").performClick()
            assertNotNull(it.view("atlas-tab-1"))
            it.onBackPressed()
            assertNotNull(it.view("atlas-feature-taste-pore"))
        }
    }

    @Test fun pleuraCutawayExplainsTheFluidFilmAndReturnsFromTheLung() = native { scenario ->
        scenario.onActivity {
            it.open("pleura")
            assertNotNull(it.view("atlas-feature-visceral-pleura"))
            assertNotNull(it.view("atlas-feature-parietal-pleura"))
            it.view("atlas-feature-pleural-fluid-film").performClick()
        }
        awaitVisibleText(scenario.localized(R.string.health_atlas_pleura_section_fluid_detail))
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        instrumentation.waitForIdleSync()
        capture("pleura-cutaway", scenario.localized(R.string.health_atlas_pleura_section_view))
        scenario.onActivity {
            it.view("atlas-hotspot-lungs").performClick()
            it.onBackPressed()
            assertNotNull(it.view("atlas-feature-pleural-fluid-film"))
        }
    }

    @Test fun bronchioleCutawayAndClubCellLessonAreBothReachable() = native { scenario ->
        scenario.onActivity {
            it.open("bronchioles")
            for (feature in listOf("terminal-branch", "epithelium", "lumen", "elastic-fibers", "smooth-muscle"))
                assertNotNull(it.view("atlas-feature-bronchioles-$feature"))
        }
        capture("terminal-bronchiole", scenario.localized(R.string.health_atlas_bronchioles_plate_caption))
        scenario.onActivity {
            it.view("atlas-tab-1").performClick()
        }
        scenario.openAtlasRelatedLesson("cell-club-cell")
        scenario.onActivity {
            assertNotNull(it.view("atlas-function-club-cell-airway-art"))
            it.onBackPressed()
            assertNotNull(it.view("atlas-function-menu"))
        }
    }

    @Test fun hypothalamusCutawayLinksToThePituitary() = native { scenario ->
        scenario.onActivity {
            it.open("hypothalamus")
            assertNotNull(it.view("atlas-feature-hypothalamus-region"))
            assertNotNull(it.view("atlas-feature-hypothalamus-infundibulum"))
        }
        capture("hypothalamus-midsagittal", scenario.localized(R.string.health_atlas_hypothalamus_plate_scope))
        scenario.onActivity {
            it.view("atlas-hotspot-pituitary-gland").performClick()
            assertEquals(it.getString(R.string.health_atlas_pituitary_gland_name),
                (it.view("health-page-title") as TextView).text)
            it.onBackPressed()
            assertNotNull(it.view("atlas-feature-hypothalamus-region"))
        }
    }

    @Test fun newRegionalCutawaysLeadToTheirOwnPlayback() = native { scenario ->
        val direct = listOf(
            Triple("placenta", "placenta-terminal-villus", "placental-exchange"),
            Triple("ligaments", "ligaments-acl-tibial-footprint", "ligament-guidance"),
            Triple("appendix", "appendix-lymphoid-follicle", "gut-lymphoid-sampling"),
            Triple("rectus-abdominis", "rectus-linea-alba", "rectus-trunk-flexion"),
            Triple("oblique-abdominal-muscles", "oblique-internal", "oblique-rotation"),
            Triple("erector-spinae", "erector-spinae-midline", "erector-support"),
        )
        for ((owner, feature, animation) in direct) scenario.onActivity { activity ->
            activity.open(owner)
            assertNotNull(activity.view("atlas-feature-$feature"))
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-$animation-art"))
            activity.onBackPressed()
        }
        scenario.onActivity { activity ->
            activity.open("autonomic-nerves")
            assertNotNull(activity.view("atlas-feature-autonomic-sympathetic-chain"))
            activity.view("atlas-tab-1").performClick()
            activity.view("atlas-function-lesson-1").performClick()
            assertEquals(activity.getString(R.string.health_atlas_ganglion_relay_autonomic_caption),
                (activity.view("atlas-function-caption") as TextView).text)
        }
    }

    @Test fun regionalCutawaysHaveTheirOwnArtworkAndPreserveTheOriginalLocator() {
        val en = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.ENGLISH) })
        val zh = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) })
        val atlas = HealthBodyAtlas.load(en)
        val details = HealthAtlasRegionalDetailPlates.all
        assertEquals(details.size, details.map { it.owner }.toSet().size)
        assertEquals(details.size, details.map { it.drawable }.toSet().size)
        val offArtwork = mutableListOf<String>()
        for (detail in details) {
            val owner = requireNotNull(detail.owner)
            assertNotNull(atlas[owner])
            assertTrue(requireNotNull(detail.source).startsWith("https://"))
            val selector = requireNotNull(detail.selectorLabel)
            assertNotEquals(en.getString(selector), zh.getString(selector))
            assertTrue("$owner needs at least three feature callouts", detail.features.size >= 3)
            val labels = detail.markers + detail.features.map { it.marker }
            assertEquals("$owner has duplicate labels", labels.map { it.id }.distinct().size, labels.size)
            assertTrue("$owner links to an unknown structure", detail.markers.all { atlas[it.id] != null })
            val views = HealthAtlasPlates.viewsForId(owner)
            assertSame(detail, views.first())
            val locator = views.getOrNull(1)
            assertNotNull("$owner has no matching locator", locator)
            assertNotEquals(detail.drawable, locator!!.drawable)
            assertNotNull(locator.viewKey)
            assertEquals(locator, HealthAtlasPlates.forId(owner, locator.viewKey))
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(detail.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals("$owner has an opaque background", 0, Color.alpha(bitmap.getPixel(0, 0)))
                for (marker in labels) {
                    val x = (marker.x * 360).roundToInt().coerceIn(1, 358)
                    val y = (marker.y * 280).roundToInt().coerceIn(1, 278)
                    val onArtwork = (-1..1).any { dx -> (-1..1).any { dy ->
                        Color.alpha(bitmap.getPixel(x + dx, y + dy)) > 180
                    } }
                    if (!onArtwork) offArtwork += "$owner/${marker.id}"
                }
                for (key in detail.features.flatMap { listOf(it.title, it.explanation) }) {
                    assertNotEquals(en.getString(key), zh.getString(key))
                    assertTrue(zh.getString(key).any { it in '\u4e00'..'\u9fff' })
                }
            } finally { bitmap.recycle() }
        }
        assertTrue("Callouts outside their artwork: ${offArtwork.joinToString()}", offArtwork.isEmpty())
    }

    @Test fun fullscreenAnatomyKeepsLabelsAndSelectionWhileAllowingAnUnlabeledView() = native { scenario ->
        scenario.onActivity { activity ->
            val data = HealthBodyAtlas.load(activity)
            val plate = requireNotNull(HealthAtlasPlates.forId("pelvis"))
            var selection = ""
            val zoom = HealthAtlasAnatomyDialog(activity, data, "pelvis", plate, "Pelvis") { selection = it.id }
            try {
                zoom.show()
                val root = requireNotNull(zoom.window).decorView
                val marker = requireNotNull(root.tagged("atlas-hotspot-femur"))
                val toggle = requireNotNull(root.tagged("atlas-fullscreen-labels"))
                assertTrue(marker.isClickable)
                assertEquals(View.VISIBLE, marker.visibility)
                assertEquals(activity.getString(R.string.health_atlas_hide_labels), toggle.contentDescription)
                assertNotNull(root.tagged("atlas-fullscreen-image"))
                toggle.performClick()
                assertEquals(View.GONE, marker.visibility)
                assertEquals(activity.getString(R.string.health_atlas_show_labels), toggle.contentDescription)
                toggle.performClick()
                assertEquals(View.VISIBLE, marker.visibility)
                assertNotNull(root.tagged("atlas-fullscreen-reset"))
                marker.performClick()
                assertEquals("femur", selection)
                assertFalse(zoom.isShowing)
            } finally { zoom.dismiss() }
        }
    }

    @Test fun skinCutawayLinksToTwoIndependentLayerViewsWithoutReplacingTheirFunctions() = native { scenario ->
        scenario.onActivity { it.open("skin-organ") }
        capture("skin-layer-cutaway", scenario.localized(R.string.health_atlas_skin_cross_section))
        scenario.onActivity { activity ->
            val marker = activity.view("atlas-hotspot-epidermis")
            assertNotNull(activity.view("atlas-feature-skin-layers-follicle"))
            marker.performClick()
            assertNotNull(activity.view("atlas-feature-skin-layers-corneum"))
            assertNotNull(activity.view("atlas-feature-skin-layers-basale"))
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-epidermal-barrier-art"))
            activity.onBackPressed()
            activity.view("atlas-hotspot-dermis").performClick()
            assertNotNull(activity.view("atlas-feature-skin-layers-papillary"))
            assertNotNull(activity.view("atlas-feature-skin-layers-reticular"))
        }
        scenario.recreate()
        ready(scenario, "atlas-feature-skin-layers-reticular")
        scenario.onActivity { activity ->
            assertTrue(activity.view("atlas-view-0").isSelected)
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-feature-skin-layers-follicle"))
        }
    }

    @Test fun pelvisAndSubcutaneousSectionsOpenTheirOwnFunctions() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("pelvis")
            assertNotNull(activity.view("atlas-feature-pelvic-ring-sacroiliac"))
            assertNotNull(activity.view("atlas-hotspot-femur"))
        }
        capture("pelvic-ring", scenario.localized(R.string.health_atlas_pelvic_ring_view))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-pelvic-ring-art"))
            activity.onBackPressed()
            activity.open("subcutaneous-tissue")
            assertNotNull(activity.view("atlas-feature-subcutaneous-septum"))
            assertNotNull(activity.view("atlas-hotspot-cell-adipocyte"))
        }
        capture("subcutaneous-section", scenario.localized(R.string.health_atlas_subcutaneous_view))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-subcutaneous-cushion-art"))
        }
    }

    @Test fun clavicleAndFibulaHaveDedicatedLandmarksAndRelatedMotion() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("clavicle")
            assertNotNull(activity.view("atlas-feature-clavicle-acromial"))
            activity.view("atlas-tab-1").performClick()
            assertEquals(activity.getString(R.string.health_atlas_scapular_rotation_story_clavicle_caption),
                (activity.view("atlas-function-caption") as TextView).text)
            activity.onBackPressed()
            activity.open("fibula")
            assertNotNull(activity.view("atlas-feature-fibula-malleolus"))
        }
        capture("fibula-section", scenario.localized(R.string.health_atlas_fibula_section_view))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-ankle-mortise-art"))
        }
        scenario.openAtlasRelatedLesson("tibia")
        scenario.onActivity { activity ->
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-function-ankle-mortise-art"))
        }
    }

    @Test fun glandAndDeepCalfCutawaysKeepTheirOriginalFunctionLessons() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("mammary-glands")
            assertNotNull(activity.view("atlas-feature-mammary-duct"))
        }
        capture("mammary-gland-section", scenario.localized(R.string.health_atlas_mammary_section_view))
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-cell-mammary-luminal-cell").performClick()
            assertEquals(activity.getString(R.string.health_atlas_cell_mammary_luminal_cell_name),
                (activity.view("health-page-title") as TextView).text)
            activity.onBackPressed()
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-player"))
            activity.onBackPressed()
            activity.open("soleus")
            assertNotNull(activity.view("atlas-feature-soleus-calcaneus"))
        }
        capture("deep-calf-soleus", scenario.localized(R.string.health_atlas_soleus_section_view))
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-tendons").performClick()
            activity.onBackPressed()
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-player"))
        }
    }

    @Test fun hairShaftCutawayKeepsTheFollicleAsItsOwnPage() = native { scenario ->
        scenario.onActivity { it.open("hair") }
        capture("hair-shaft", scenario.localized(R.string.health_atlas_hair_shaft_view))
        scenario.onActivity { activity ->
            assertNotNull(activity.view("atlas-feature-hair-shaft-medulla"))
            activity.view("atlas-hotspot-hair-follicles").performClick()
            assertNotNull(activity.view("atlas-feature-hair-section-papilla"))
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-feature-hair-shaft-cuticle"))
        }
    }

    @Test fun limbBonesOpenUpperAndLowerLimbPagesAndReturnToTheOverview() = native { scenario ->
        scenario.onActivity { it.open("limb-bones") }
        capture("limb-bones-overview", scenario.localized(R.string.health_atlas_limb_bones_overview_view))
        scenario.onActivity { activity ->
            for (id in listOf("radius", "tibia", "foot-bones")) {
                activity.view("atlas-hotspot-$id").performClick()
                assertNotEquals(activity.getString(R.string.health_atlas_limb_bones_name),
                    (activity.view("health-page-title") as TextView).text)
                activity.onBackPressed()
                assertEquals(activity.getString(R.string.health_atlas_limb_bones_name),
                    (activity.view("health-page-title") as TextView).text)
            }
        }
    }

    @Test fun sternumAndHandLandmarksLinkToRealNeighboringBones() = native { scenario ->
        scenario.onActivity {
            it.open("sternum")
            assertNotNull(it.view("atlas-feature-sternum-angle"))
            it.view("atlas-hotspot-clavicle").performClick()
            assertNotNull(it.view("atlas-feature-clavicle-acromial"))
            it.onBackPressed()
            assertNotNull(it.view("atlas-feature-sternum-xiphoid"))
            it.onBackPressed()
            it.open("hand-bones")
        }
        capture("hand-bones-palmar", scenario.localized(R.string.health_atlas_hand_palmar_detail))
        scenario.onActivity {
            assertNotNull(it.view("atlas-feature-hand-bones-carpals"))
            it.view("atlas-hotspot-radius").performClick()
            assertNotNull(it.view("atlas-feature-radius-wrist"))
            it.onBackPressed()
            assertNotNull(it.view("atlas-feature-hand-bones-pisiform"))
            it.view("atlas-tab-1").performClick()
            assertNotNull(it.view("atlas-function-player"))
        }
    }

    @Test fun cranialNerveMapAndReflexPlaybackRemainSeparate() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("cranial-nerves")
            for (part in listOf("olfactory", "optic", "midbrain", "trigeminal", "pontomedullary",
                "medullary", "accessory", "hypoglossal"))
                assertNotNull(activity.view("atlas-feature-cranial-$part-attachment"))
        }
        capture("cranial-nerve-map", scenario.localized(R.string.health_atlas_cranial_attach_view))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-cranial-reflex-art"))
            activity.view("atlas-tab-0").performClick()
            assertNotNull(activity.view("atlas-feature-cranial-accessory-attachment"))
        }
    }

    @Test fun radiusAndOlfactorySectionsOpenTheirOwnNeighboringStructures() = native { scenario ->
        val cases = listOf(
            Triple("radius", "ulna", "radius-wrist"),
            Triple("olfactory-mucosa", "cell-olfactory-receptor-neuron", "olfactory-gland"),
        )
        for ((owner, target, feature) in cases) scenario.onActivity { activity ->
            activity.open(owner)
            assertNotNull(activity.view("atlas-feature-$feature"))
            activity.view("atlas-hotspot-$target").performClick()
            assertNull(activity.window.decorView.tagged("atlas-feature-$feature"))
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-feature-$feature"))
            activity.onBackPressed()
        }
    }

    @Test fun ribsDefaultToTheDetailAndRetainTheSkeletonContext() = native { scenario ->
        assertEquals(listOf("ribs", "skeletal"), HealthAtlasPlates.viewsForId("ribs").map { it.owner })
        scenario.onActivity { activity ->
            activity.open("ribs")
            assertNotNull(activity.view("atlas-feature-ribs-posterior-joint"))
            assertNotNull(activity.view("atlas-feature-ribs-floating-tip"))
        }
        capture("rib-attachments", scenario.localized(R.string.health_atlas_ribs_attachments_plate_caption))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-thoracic-frame-art"))
        }
        scenario.openAtlasRelatedLesson("lungs")
        scenario.onActivity { activity ->
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-function-thoracic-frame-art"))
        }
    }

    @Test fun pinealCutawayAndNightSignalDoNotReplaceTheHypothalamusPage() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("pineal-gland")
            assertNotNull(activity.view("atlas-feature-pineal-plate-body"))
            assertNotNull(activity.view("atlas-feature-pineal-third-ventricle"))
            assertNull(activity.window.decorView.tagged("atlas-feature-hypothalamus-region"))
        }
        capture("pineal-sagittal", scenario.localized(R.string.health_atlas_pineal_plate_caption))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            assertNotNull(activity.view("atlas-function-pineal-dark-signal-art"))
        }
    }

    @Test fun cartilageAndJointUseDistinctCutawaysAndCartilageSimulatesCompression() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("cartilage")
            assertNotNull(activity.view("atlas-feature-cartilage-articular-surface"))
            assertNotNull(activity.view("atlas-hotspot-cell-chondrocyte"))
        }
        capture("cartilage-overview", scenario.localized(R.string.health_atlas_cartilage_overview_plate_caption))
        scenario.onActivity { activity ->
            activity.openAtlasModelDetails()
            assertNotNull(activity.view("atlas-cartilage-compression"))
            activity.onBackPressed()
            activity.open("joints")
            assertNotNull(activity.view("atlas-feature-synovial-joint-cavity"))
            assertNotNull(activity.view("atlas-hotspot-tissue-hyaline-cartilage"))
        }
        capture("synovial-joint", scenario.localized(R.string.health_atlas_synovial_joint_plate_caption))
    }

    @Test fun biliaryPlateAndCellPlaybackAreAvailableFromTheSameEntry() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("biliary-tract")
            assertNotNull(activity.view("atlas-feature-biliary-common-bile-duct"))
            assertNotNull(activity.view("atlas-feature-biliary-major-papilla"))
        }
        capture("biliary-tract", scenario.localized(R.string.health_atlas_biliary_tract_plate_caption))
        scenario.onActivity { activity ->
            activity.view("atlas-tab-1").performClick()
            activity.view("atlas-function-lesson-1").performClick()
            assertNotNull(activity.view("atlas-function-cholangiocyte-bile-art"))
        }
    }

    @Test fun vesselComparisonLinksToAnArteryWithItsOwnWallLayers() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("blood-vessels")
            assertNotNull(activity.view("atlas-hotspot-veins"))
            assertNotNull(activity.view("atlas-hotspot-capillaries"))
        }
        capture("vessel-comparison", scenario.localized(R.string.health_atlas_vessel_comparison_caption))
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-arteries").performClick()
            for (id in listOf("outer-layer", "middle-layer", "inner-layer", "lumen"))
                assertNotNull(activity.view("atlas-feature-artery-$id"))
        }
        capture("artery-wall", scenario.localized(R.string.health_atlas_artery_layers_caption))
        scenario.onActivity { activity ->
            activity.onBackPressed()
            assertNotNull(activity.view("atlas-hotspot-arteries"))
        }
    }

    @Test fun wholeBloodShowsPlasmaAndLinksTheRepresentedBloodComponents() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("blood")
            activity.view("atlas-feature-whole-blood-plasma").performClick()
        }
        awaitVisibleText(scenario.localized(R.string.health_atlas_whole_blood_plasma_detail))
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        instrumentation.waitForIdleSync()
        capture("whole-blood-suspension", scenario.localized(R.string.health_atlas_whole_blood_caption))
        scenario.onActivity { activity ->
            val parts = listOf(
                "cell-erythrocyte" to R.string.health_atlas_cell_erythrocyte_name,
                "cell-neutrophil" to R.string.health_atlas_cell_neutrophil_name,
                "fragment-platelet" to R.string.health_atlas_fragment_platelet_name,
            )
            for ((id, label) in parts) {
                activity.view("atlas-hotspot-$id").performClick()
                assertEquals(activity.getString(label), (activity.view("health-page-title") as TextView).text)
                activity.onBackPressed()
                assertNotNull(activity.view("atlas-feature-whole-blood-plasma"))
            }
        }
    }

    @Test fun sweatAnimationAndHeatModelRestoreIndependentlyOfTheCell() = native { scenario ->
        scenario.onActivity {
            it.open("sweat-glands")
            assertNotNull(it.view("atlas-feature-sweat-pore"))
            it.view("atlas-hotspot-cell-sweat-gland-secretory-cell").performClick()
            assertNotNull(it.view("atlas-feature-eccrine-secretory-apex"))
            it.openAtlasModelDetails()
            assertNull(it.window.decorView.tagged("atlas-physiology-sweat-evaporated"))
            it.onBackPressed()
            it.openAtlasModelDetails()
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
            it.onBackPressed(); it.openAtlasModelDetails()
            it.view("atlas-process-stage-2").performClick()
            val stage = (it.view("atlas-simulation-stage") as TextView).text
            assertTrue(stage.contains(it.getString(R.string.health_atlas_context_hair_stage_2)))
            assertNull(it.window.decorView.tagged("atlas-sweat-diagram"))
        }
    }
}
