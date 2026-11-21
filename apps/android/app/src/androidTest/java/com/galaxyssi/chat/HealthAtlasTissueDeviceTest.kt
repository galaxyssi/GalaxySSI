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
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasTissueDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val cardiac = "tissue-cardiac-muscle"
    private val myocyte = "cell-cardiomyocyte"

    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.find(key: String) = window.decorView.tagged(key)
    private fun Activity.view(key: String) = requireNotNull(find(key)) { key }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        while (SystemClock.elapsedRealtime() < deadline) {
            var found = false
            scenario.onActivity { found = it.find(key) != null }
            if (found) return
            SystemClock.sleep(40)
        }
        fail(key)
    }

    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use {
                ready(it, "atlas-whole-art")
                block(it)
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun heartLayerSwapsLocallyAndDrillsThroughTissueToTheNamedCell() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            val scroll = it.view("atlas-scroll")
            val agent = it.view("atlas-ask")
            it.view("atlas-structure-layer-1").performClick()
            assertSame(scroll, it.view("atlas-scroll"))
            assertSame(agent, it.view("atlas-ask"))
            assertNull(it.find("atlas-entry-tissue-skeletal-muscle"))
            it.view("atlas-entry-$cardiac").performClick()
            assertNotNull(it.find("atlas-art-caption"))
            assertNotNull(it.find("atlas-entry-heart"))
            assertNotNull(it.find("atlas-entry-$myocyte"))
            it.view("atlas-hotspot-$myocyte").performClick()
            it.onBackPressed()
            assertNotNull(it.find("atlas-hotspot-$myocyte"))
            it.onBackPressed()
            assertTrue(it.view("atlas-structure-layer-1").isSelected)
        }
        scenario.recreate()
        ready(scenario, "atlas-entry-$cardiac")
        scenario.onActivity {
            it.view("atlas-structure-layer-2").performClick()
            assertNotNull(it.find("atlas-entry-$myocyte"))
            assertNull(it.find("atlas-entry-$cardiac"))
        }
    }

    @Test fun catalogueSearchStaysMountedAndSelectionSurvivesRecreation() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-tab-2").performClick()
            val search = it.view("atlas-search") as EditText
            search.setText(cardiac)
            assertNull(it.find("atlas-entry-$cardiac"))
            it.view("atlas-catalogue-layer-1").performClick()
            assertSame(search, it.view("atlas-search"))
            assertNotNull(it.find("atlas-entry-$cardiac"))
            assertNull(it.find("atlas-entry-heart"))
        }
        scenario.recreate()
        ready(scenario, "atlas-entry-$cardiac")
        scenario.onActivity {
            assertEquals(cardiac, (it.view("atlas-search") as EditText).text.toString())
            assertTrue(it.view("atlas-catalogue-layer-1").isSelected)
            it.view("atlas-catalogue-layer-0").performClick()
            (it.view("atlas-search") as EditText).setText("lens")
            it.view("atlas-entry-lens").performClick()
            it.view("atlas-structure-layer-1").performClick()
            assertNull(it.find("atlas-entry-$cardiac"))
            assertNull(it.find("atlas-entry-tissue-epidermal"))
        }
    }

    @Test fun tissueSelectsOwnTeachingStagesAndRestoresThem() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        val stage = atlas.mechanism(atlas[cardiac]!!).stages[2]
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.view("atlas-structure-layer-1").performClick()
            it.view("atlas-entry-$cardiac").performClick()
            it.view("atlas-tab-3").performClick()
            it.view("atlas-process-stage-2").performClick()
            assertTrue((it.view("atlas-simulation-stage") as TextView).text.contains(stage))
        }
        scenario.recreate()
        ready(scenario, "atlas-simulation-stage")
        scenario.onActivity { assertTrue((it.view("atlas-simulation-stage") as TextView).text.contains(stage)) }
    }

    @Test fun localizedTissuesOnlyUseExplicitExamplesAndPublicAgentContext() {
        val examples = mapOf(
            "tissue-epidermal" to HealthAtlasPhysiologyKind.SKIN_WATER_BARRIER,
            "tissue-respiratory-epithelium" to HealthAtlasPhysiologyKind.AIRWAY_CILIARY_CLEARANCE,
            "tissue-alveolar-epithelium" to HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION,
            "tissue-vascular-endothelium" to HealthAtlasPhysiologyKind.CAPILLARY_EXCHANGE,
            "tissue-skeletal-muscle" to HealthAtlasPhysiologyKind.MUSCLE_SHORTENING,
            "tissue-cardiac-muscle" to HealthAtlasPhysiologyKind.CARDIAC_PHASE_TIME,
            "tissue-smooth-muscle" to HealthAtlasPhysiologyKind.PERISTALTIC_TRAVEL,
            "tissue-dense-regular-connective" to HealthAtlasPhysiologyKind.TENDON_ELONGATION,
            "tissue-compact-bone" to HealthAtlasPhysiologyKind.BONE_SECTION,
            "tissue-hyaline-cartilage" to HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION,
            "tissue-central-nervous" to HealthAtlasPhysiologyKind.NEURAL_RELAY_DELAYS,
            "tissue-white-adipose" to HealthAtlasPhysiologyKind.ADIPOSE_VOLUME_SHARE,
        )
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            assertEquals(14, atlas.tissues.size)
            assertEquals(atlas.tissues.map { it.id }.toSet(), HealthAtlasTissuePlates.all.map { it.owner }.toSet())
            for (item in atlas.tissues) {
                val plate = HealthAtlasTissuePlates.forId(item.id)!!
                assertTrue(plate.markers.all { it.id in item.related })
                assertEquals(item.related, atlas.cells(item).map { it.id })
                assertTrue(item.locatedIn.all { item in atlas.tissues(atlas[it]!!) })
                assertTrue(HealthAtlasMetrics.forItem(item).isEmpty())
                assertEquals(item.id, examples[item.id], HealthAtlasPhysiologyKind.forItem(item.id))
                assertTrue(item.related.all { HealthAtlasTissuePlates.forId(it) == null })
            }
            val item = atlas[cardiac]!!
            val mechanism = atlas.mechanism(item)
            val prompt = HealthAtlasAgentContext.prompt(localized, atlas, item, HealthAtlasSimulation(phase = 0.6f))
            assertTrue(prompt.contains(mechanism.stages[2]))
            assertTrue(prompt.contains(mechanism.source))
            assertTrue(prompt.contains(atlas[myocyte]!!.name))
            assertFalse(prompt.contains(atlas["tissue-hyaline-cartilage"]!!.name))
            assertFalse(prompt.contains("L/min"))
        }
    }

    @Test fun allTissueVectorsRenderTheirClickableTargetsOnArtwork() {
        assertEquals(14, HealthAtlasTissuePlates.all.map { it.drawable }.toSet().size)
        for (plate in HealthAtlasTissuePlates.all) {
            val bitmap = Bitmap.createBitmap(420, 200, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, bitmap.width, bitmap.height); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                for (marker in plate.markers) {
                    val alpha = Color.alpha(bitmap.getPixel((marker.x * bitmap.width).toInt(), (marker.y * bitmap.height).toInt()))
                    assertTrue("${plate.owner}: ${marker.id} alpha=$alpha", alpha > 180)
                }
            } finally { bitmap.recycle() }
        }
    }
}
