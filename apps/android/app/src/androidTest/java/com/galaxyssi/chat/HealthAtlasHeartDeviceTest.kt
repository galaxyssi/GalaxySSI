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
import android.widget.SeekBar
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasHeartDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun Activity.label(key: String) = (view(key) as TextView).text.toString()
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        while (SystemClock.elapsedRealtime() < deadline) {
            var found = false
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
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
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(fixture)).use { ready(it, "atlas-whole-art"); block(it) }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun heartShowsExteriorAndAnatomicalSectionWithLocalSelectionAndRestoration() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            assertTrue(it.view("atlas-view-0").isSelected)
            val scroll = it.view("atlas-scroll")
            it.view("atlas-view-1").performClick()
            assertSame(scroll, it.view("atlas-scroll"))
            for (marker in HealthAtlasHeartSection.section.markers) {
                it.view("atlas-hotspot-${marker.id}").performClick()
                assertEquals(atlas[marker.id]!!.name, it.label("health-page-title"))
                val views = HealthAtlasPlates.viewsForId(marker.id)
                val locator = views.indexOfFirst { plate ->
                    plate.drawable == HealthAtlasHeartSection.section.drawable &&
                        plate.markers == HealthAtlasHeartSection.section.markers
                }
                assertTrue("Missing heart locator for ${marker.id}", locator >= 0)
                if (locator > 0) {
                    assertTrue(it.view("atlas-view-0").isSelected)
                    val feature = views.first().features.first()
                    assertTrue(it.view("atlas-feature-${feature.marker.id}").isClickable)
                    it.view("atlas-view-$locator").performClick()
                }
                assertTrue(it.view("atlas-hotspot-${marker.id}").isSelected)
                it.onBackPressed()
                assertTrue(it.view("atlas-view-1").isSelected)
            }
        }
        scenario.recreate()
        ready(scenario, "atlas-hotspot-aorta")
        scenario.onActivity { assertTrue(it.view("atlas-view-1").isSelected) }
    }

    @Test fun valveDiagramAndAccessibleStatesFollowSelectionAndReturnToTheSamePhase() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.view("atlas-entry-heart-valves").performClick()
            it.openAtlasModelDetails()
            val scroll = it.view("atlas-scroll")
            for (stage in 0..3) {
                it.view("atlas-process-stage-$stage").performClick()
                assertSame(scroll, it.view("atlas-scroll"))
                assertEquals(stage, (it.view("atlas-valve-diagram") as HealthAtlasValvePanel.Diagram).stage)
                HealthAtlasValve.entries.forEach { valve ->
                    assertEquals(HealthAtlasValveText.label(context, atlas, valve, stage), it.label("atlas-valve-state-${valve.id}"))
                }
            }
            it.view("atlas-process-stage-2").performClick()
            it.view("atlas-valve-state-aortic-valve").performClick()
            assertTrue(it.view("atlas-view-0").isSelected)
            val direct = requireNotNull(HealthAtlasPlates.forId("aortic-valve"))
            assertEquals("aortic-valve", direct.owner)
            assertTrue(it.view("atlas-feature-${direct.features.first().marker.id}").isClickable)
            it.view("atlas-view-1").performClick()
            assertTrue(it.view("atlas-hotspot-aortic-valve").isSelected)
            it.onBackPressed()
            assertEquals(2, (it.view("atlas-valve-diagram") as HealthAtlasValvePanel.Diagram).stage)
        }
        scenario.recreate()
        ready(scenario, "atlas-valve-diagram")
        scenario.onActivity { assertEquals(2, (it.view("atlas-valve-diagram") as HealthAtlasValvePanel.Diagram).stage) }
    }

    @Test fun syntheticEjectionSlidersRestoreInTheSelectedChamberOnly() = native { scenario ->
        val kind = HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION
        val expected = HealthAtlasPhysiology(kind, listOf(90, 60))
        fun output(model: HealthAtlasPhysiology) = HealthAtlasPhysiologyText.resultNumber(model, model.result) + " %"
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.view("atlas-view-1").performClick()
            it.view("atlas-hotspot-left-ventricle").performClick()
            it.openAtlasModelDetails()
            val scroll = it.view("atlas-scroll")
            (it.view("atlas-physiology-ejection-stroke") as SeekBar).progress = 90
            assertEquals(output(expected), it.label("atlas-physiology-output"))
            assertSame(scroll, it.view("atlas-scroll"))
        }
        scenario.recreate()
        ready(scenario, "atlas-physiology-output")
        scenario.onActivity {
            assertEquals(output(expected), it.label("atlas-physiology-output"))
            it.onBackPressed()
            it.view("atlas-hotspot-right-ventricle").performClick()
            it.openAtlasModelDetails()
            assertEquals(output(HealthAtlasPhysiology(kind)), it.label("atlas-physiology-output"))
        }
    }

    @Test fun anatomyAnchorsAreVisibleAndPhaseChangesRenderAtPhoneAndTabletWidths() = native { scenario ->
        scenario.onActivity { activity ->
            val section = HealthAtlasHeartSection.section
            val bitmap = Bitmap.createBitmap(480, 460, Bitmap.Config.ARGB_8888)
            try {
                activity.getDrawable(section.drawable)!!.apply { setBounds(0, 0, 480, 460); draw(Canvas(bitmap)) }
                for (marker in section.markers + HealthAtlasHeartSection.valves.markers)
                    assertTrue(marker.id, Color.alpha(bitmap.getPixel((marker.x * 480).toInt(), (marker.y * 460).toInt())) > 180)
            } finally { bitmap.recycle() }
            val diagram = HealthAtlasValvePanel.Diagram(activity, "aortic-valve")
            for (width in listOf(540, 1080, 1600)) {
                diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                diagram.layout(0, 0, width, diagram.measuredHeight)
                fun pixels(stage: Int) = Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also {
                    diagram.stage = stage; diagram.draw(Canvas(it))
                }
                val filling = pixels(0)
                val ejection = pixels(2)
                try { assertFalse(filling.sameAs(ejection)) } finally { filling.recycle(); ejection.recycle() }
            }
        }
    }

    @Test fun localizedAgentContextNeverAddsUnrelatedModelsOrPersonalMeasures() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION)
            val preview = HealthAtlasAgentContext.prompt(localized, atlas, atlas["left-ventricle"], quantitative = model)
            assertTrue(preview.contains(HealthAtlasPhysiologyText.result(localized, model)))
            assertTrue(preview.contains(HealthAtlasHeartSection.EJECTION_SOURCE))
            assertTrue(HealthAtlasMetrics.forItem(atlas["left-ventricle"]!!).isEmpty())
            val unrelated = HealthAtlasAgentContext.prompt(localized, atlas, atlas["aorta"], quantitative = model)
            assertFalse(unrelated.contains(HealthAtlasHeartSection.EJECTION_SOURCE))
            val valve = HealthAtlasAgentContext.prompt(localized, atlas, atlas["mitral-valve"], HealthAtlasSimulation())
            assertTrue(valve.contains(HealthAtlasValveText.label(localized, atlas, HealthAtlasValve.MITRAL, 0)))
            assertFalse(valve.contains(HealthAtlasValveText.label(localized, atlas, HealthAtlasValve.AORTIC, 0)))
            assertFalse(valve.contains(HealthAtlasHeartSection.EJECTION_SOURCE))
        }
    }
}
