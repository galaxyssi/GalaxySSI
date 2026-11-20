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
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

class HealthAtlasCellDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(value: String): View? = if (tag == value) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(value) } else null
    private fun Activity.view(tag: String) = requireNotNull(window.decorView.tagged(tag)) { tag }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario ->
                await(scenario, "atlas-whole-art"); block(scenario)
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun await(scenario: ActivityScenario<HealthBodyAtlasActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(tag) != null }
            if (!found) SystemClock.sleep(50)
        }
        assertTrue("Missing $tag", found)
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(350)
        val deadline = SystemClock.elapsedRealtime() + 5_000
        var owner = instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString()
        while (owner != context.packageName && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(50)
            owner = instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString()
        }
        assertEquals(context.packageName, owner)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-cell-$name.png").outputStream().use {
            image.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { image.recycle() }
    }
    @Test fun cellProcessesResolveInBothLocalesWithoutSharedStages() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val models = atlas.mechanisms.filter { it.kind == "cell" }
            assertEquals(105, models.size)
            assertEquals(105, models.map { it.title }.toSet().size)
            assertEquals(105, models.map { it.stages }.toSet().size)
            models.forEach {
                assertEquals(HealthAtlasKind.CELL, atlas[it.id]?.kind)
                assertEquals(it.id, atlas[it.id]?.mechanism)
                assertEquals(4, it.stages.size)
                assertTrue(it.stages.all(String::isNotBlank))
                val paper = mapOf("cell-club-cell" to "29874100", "cell-endometrial-stromal-cell" to "25141152",
                    "cell-rod-photoreceptor" to "15769618", "cell-cone-photoreceptor" to "15769618",
                    "cell-retinal-pigment-epithelial-cell" to "15987797", "cell-corneal-epithelial-cell" to "26310149",
                    "cell-pericyte" to "16166562", "cell-intestinal-stem-cell" to "23870119", "cell-cholangiocyte" to "27563020",
                    "cell-langerhans-cell" to "23246038")[it.id]
                if (paper != null) assertEquals("https://pubmed.ncbi.nlm.nih.gov/$paper/", it.source)
                else assertTrue(it.source.startsWith("https://openstax.org/books/anatomy-and-physiology-2e/pages/"))
            }
        }
    }
    @Test fun cellMechanismOwnershipIsEnforcedAtLoadTime() {
        val atlas = HealthBodyAtlas.load(context)
        val wrong = atlas.items.map { if (it.id == "cell-neutrophil") it.copy(mechanism = "cell-erythrocyte") else it }
        assertTrue(runCatching { HealthBodyAtlas(wrong, atlas.mechanisms) }.isFailure)
        assertEquals(listOf(HealthMetric.RED_BLOOD_CELLS, HealthMetric.HEMOGLOBIN, HealthMetric.HEMATOCRIT),
            HealthAtlasMetrics.forItem(atlas["cell-erythrocyte"]!!))
        assertTrue(HealthAtlasMetrics.forItem(atlas["cell-neuron"]!!).isEmpty())
    }
    @Test fun cellPlatesAreDistinctTransparentAndNotAssignedToOtherCellTypes() {
        val ids = listOf("cell-erythrocyte", "cell-neuron")
        assertEquals(2, ids.map { HealthAtlasPlates.forId(it)!!.drawable }.toSet().size)
        for (id in ids) {
            val plate = requireNotNull(HealthAtlasPlates.forId(id))
            assertEquals(id, plate.owner)
            val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
            try {
                assertTrue(bitmap.width >= 512 && bitmap.height >= 512)
                assertTrue(Color.alpha(bitmap.getPixel(0, 0)) <= 5)
                var solid = 0
                var transparent = 0
                for (y in 0 until bitmap.height step 8) for (x in 0 until bitmap.width step 8) {
                    val alpha = Color.alpha(bitmap.getPixel(x, y))
                    if (alpha > 200) solid++
                    if (alpha < 5) transparent++
                }
                assertTrue("Blank plate: $id", solid > 500)
                assertTrue("Missing transparency: $id", transparent > 500)
            } finally { bitmap.recycle() }
        }
        assertNull(HealthAtlasPlates.forId("cell-oligodendrocyte"))
        assertEquals("cell-neutrophil", HealthAtlasPlates.forId("cell-neutrophil")!!.owner)
    }
    @Test fun allThirtyCoreCellsOwnDistinctArtAndEveryNewAnchorIsOnItsFigure() {
        val atlas = HealthBodyAtlas.load(context)
        val ids = listOf("erythrocyte", "neutrophil", "eosinophil", "basophil", "monocyte", "macrophage", "t-cell",
            "b-cell", "plasma-cell", "natural-killer-cell", "neuron", "astrocyte", "schwann-cell", "skeletal-myocyte",
            "cardiomyocyte", "smooth-muscle-cell", "keratinocyte", "melanocyte", "fibroblast", "adipocyte",
            "osteoblast", "osteocyte", "osteoclast", "chondrocyte", "vascular-endothelial-cell", "hepatocyte",
            "pancreatic-beta-cell", "enterocyte", "spermatozoon", "oocyte-or-ovum").map { "cell-$it" }
        val images = ids.map { id ->
            assertEquals(HealthAtlasKind.CELL, atlas[id]?.kind)
            requireNotNull(HealthAtlasPlates.forId(id)).also { assertEquals(id, it.owner) }
        }
        assertEquals(30, images.map { it.drawable }.toSet().size)
        assertEquals(18, HealthAtlasCoreCellPlates.all.size)
        assertEquals(39, HealthAtlasCoreCellPlates.all.sumOf { it.features.size })
        for (plate in HealthAtlasCoreCellPlates.all) {
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0,0)))
                for (feature in plate.features) {
                    val m = feature.marker
                    assertTrue("${plate.owner}/${m.id}",
                        Color.alpha(bitmap.getPixel((360 * m.x).toInt(), (280 * m.y).toInt())) > 180)
                }
            } finally { bitmap.recycle() }
        }
    }

    @Test fun transportCellArtHasItsOwnLandmarksAndTranslatedDescriptions() {
        val plates = HealthAtlasTransportCellPlates.all
        assertEquals(12, plates.size)
        assertEquals(25, plates.sumOf { it.features.size })
        assertEquals(12, plates.map { it.drawable }.toSet().size)
        val chinese = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocale(Locale.SIMPLIFIED_CHINESE)
        })
        val english = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocale(Locale.ENGLISH)
        })
        val atlas = HealthBodyAtlas.load(english)
        for (plate in plates) {
            assertEquals(HealthAtlasKind.CELL, atlas[requireNotNull(plate.owner)]?.kind)
            assertSame(plate, HealthAtlasPlates.forId(plate.owner))
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, 360, 280); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0, 0)))
                for (feature in plate.features) {
                    val m = feature.marker
                    // Vector edges can antialias differently on the device and reference renderer.
                    val x = (360 * m.x).roundToInt().coerceIn(1, 358)
                    val y = (280 * m.y).roundToInt().coerceIn(1, 278)
                    assertTrue("${plate.owner}/${m.id}",
                        (-1..1).any { dx -> (-1..1).any { dy ->
                            Color.alpha(bitmap.getPixel(x + dx, y + dy)) > 180
                        } })
                    for (key in listOf(feature.title, feature.explanation)) {
                        assertTrue(chinese.getString(key).any { it in '\u4e00'..'\u9fff' })
                        assertNotEquals(english.getString(key), chinese.getString(key))
                    }
                }
            } finally { bitmap.recycle() }
        }
    }

    private fun Activity.openTransportCell(id: String) {
        view("atlas-tab-3").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }

    @Test fun typeIIPneumocytePressureRespondsLocallyAndSurvivesRecreation() = native { scenario ->
        val typeII = "cell-type-ii-pneumocyte"
        scenario.onActivity {
            it.openTransportCell(typeII)
            assertNotNull(it.view("atlas-feature-lamellar-body"))
            it.view("atlas-tab-3").performClick()
            val scroll = it.view("atlas-scroll")
            val diagram = it.view("atlas-alveolar-surface-diagram") as HealthAtlasAlveolarSurfaceView
            assertEquals(300.0, diagram.model.result, 1e-9)
            (it.view("atlas-physiology-alveolar-radius") as SeekBar).progress = 150
            assertEquals(150.0, diagram.model.result, 1e-9)
            assertEquals(75.0, diagram.model.companionValue, 1e-9)
            assertSame(scroll, it.view("atlas-scroll"))
            assertTrue(diagram.contentDescription.contains("75 Pa"))
            val control = it.view("atlas-physiology-alveolar-radius")
            val panel = control.parent as ViewGroup
            assertTrue(panel.indexOfChild(control) < panel.indexOfChild(it.view("atlas-physiology-chart")))
        }
        capture("pneumocyte-ii-surface")
        scenario.recreate(); await(scenario, "atlas-alveolar-surface-diagram")
        scenario.onActivity {
            val diagram = it.view("atlas-alveolar-surface-diagram") as HealthAtlasAlveolarSurfaceView
            assertEquals(150.0, diagram.model.result, 1e-9)
            val atlas = HealthBodyAtlas.load(it)
            val scope = it.getString(R.string.health_atlas_alveolar_surface_scope)
            assertTrue(HealthAtlasAgentContext.prompt(it, atlas, atlas[typeII], quantitative = diagram.model).contains(scope))
            val typeI = "cell-type-i-pneumocyte"
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas[typeI], quantitative = diagram.model).contains(scope))
            it.onBackPressed(); it.openTransportCell(typeI)
            it.view("atlas-tab-3").performClick()
            assertNull(it.window.decorView.tagged("atlas-alveolar-surface-diagram"))
        }
    }

    @Test fun podocyteFiltrationTracksStageWithoutLeakingToMesangium() = native { scenario ->
        val id = HealthAtlasPodocyteView.OWNER
        val neighbor = "cell-mesangial-cell"
        scenario.onActivity {
            it.openTransportCell(id)
            assertNotNull(it.view("atlas-feature-podocyte-foot"))
            it.view("atlas-tab-3").performClick()
            val diagram = it.view("atlas-podocyte-diagram") as HealthAtlasPodocyteView
            val atlas = HealthBodyAtlas.load(it)
            val mechanism = atlas.mechanism(requireNotNull(atlas[id]))
            val scope = it.getString(R.string.health_atlas_podocyte_scope)
            for (stage in 0..3) {
                it.view("atlas-process-stage-$stage").performClick()
                assertEquals(stage, diagram.stage)
                assertTrue(diagram.contentDescription.startsWith(mechanism.stages[stage]))
            }
            val simulation = HealthAtlasSimulation(phase = .75f)
            assertTrue(HealthAtlasAgentContext.prompt(it, atlas, atlas[id], simulation = simulation).contains(scope))
            assertFalse(HealthAtlasAgentContext.prompt(it, atlas, atlas[neighbor], simulation = simulation).contains(scope))
        }
        capture("podocyte-filtration")
        scenario.recreate(); await(scenario, "atlas-podocyte-diagram")
        scenario.onActivity {
            assertEquals(3, (it.view("atlas-podocyte-diagram") as HealthAtlasPodocyteView).stage)
            it.onBackPressed(); it.openTransportCell(neighbor)
            it.view("atlas-tab-3").performClick()
            assertNull(it.window.decorView.tagged("atlas-podocyte-diagram"))
        }
    }

    @Test fun sarcomereUsesTheCurrentSkeletalMyocyteStageAndRestoresItsRelativeLength() = native { scenario ->
        fun Activity.openCell(id: String) {
            view("atlas-tab-3").performClick()
            (view("atlas-search") as EditText).setText(id)
            view("atlas-entry-$id").performClick()
        }
        scenario.onActivity {
            it.openCell("cell-astrocyte")
            assertNotNull(it.view("atlas-feature-astrocyte-endfoot"))
        }
        capture("astrocyte")
        scenario.onActivity {
            it.onBackPressed(); it.openCell(HealthAtlasSarcomere.OWNER)
            it.view("atlas-tab-3").performClick()
            val scroll = it.view("atlas-scroll")
            val diagram = it.view("atlas-sarcomere-diagram") as HealthAtlasSarcomerePanel.Diagram
            for (stage in 0..3) {
                it.view("atlas-process-stage-$stage").performClick()
                assertEquals(HealthAtlasSarcomere(stage), diagram.model)
                assertSame(scroll, it.view("atlas-scroll"))
                assertTrue(diagram.contentDescription.contains((it.view("atlas-sarcomere-ratio") as TextView).text))
            }
            it.view("atlas-process-stage-2").performClick()
        }
        capture("sarcomere")
        scenario.recreate(); await(scenario, "atlas-sarcomere-diagram")
        scenario.onActivity {
            assertEquals(180, (it.view("atlas-sarcomere-diagram") as HealthAtlasSarcomerePanel.Diagram).model.zDistance)
            it.onBackPressed(); it.openCell("cell-cardiomyocyte"); it.view("atlas-tab-3").performClick()
            assertNull(it.window.decorView.tagged("atlas-sarcomere-diagram"))
        }
    }

    @Test fun sarcomereFramesAndTranslatedContextStayScopedToSkeletalMuscle() = native { scenario ->
        scenario.onActivity { activity ->
            for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
                val localized = activity.createConfigurationContext(Configuration(activity.resources.configuration).apply { setLocale(locale) })
                val atlas = HealthBodyAtlas.load(localized)
                val ratio = localized.getString(R.string.health_atlas_sarcomere_ratio, 72)
                assertTrue(HealthAtlasAgentContext.prompt(localized, atlas, atlas[HealthAtlasSarcomere.OWNER],
                    simulation = HealthAtlasSimulation(phase = .5f)).contains(ratio))
                for (id in listOf("cell-cardiomyocyte", "cell-smooth-muscle-cell", "muscle"))
                    assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas[id],
                        simulation = HealthAtlasSimulation(phase = .5f)).contains(ratio))
            }
            for (night in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                val themed = activity.createConfigurationContext(Configuration(activity.resources.configuration).apply {
                    uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or night
                })
                val diagram = HealthAtlasSarcomerePanel.Diagram(themed)
                for (width in listOf(540, 1080, 1600)) {
                    diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    diagram.layout(0, 0, width, diagram.measuredHeight)
                    fun draw(stage: Int) = Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also {
                        diagram.model = HealthAtlasSarcomere(stage); diagram.draw(Canvas(it))
                    }
                    val relaxed = draw(3); val shortened = draw(2)
                    try {
                        assertFalse(relaxed.sameAs(shortened))
                        assertTrue(Color.alpha(shortened.getPixel(width / 2, diagram.height / 2)) > 180)
                    } finally { relaxed.recycle(); shortened.recycle() }
                }
            }
        }
    }
    @Test fun everyCellStageIsFocusableAndFitsLargeText() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            for (model in atlas.mechanisms.filter { it.kind in setOf("cell", "fragment") }) {
                var selected = -1
                val process = HealthAtlasProcessView(activity, model) { selected = it }
                (0 until process.childCount).forEach { (process.getChildAt(it) as TextView).textSize = 26f }
                process.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                process.layout(0, 0, process.measuredWidth, process.measuredHeight)
                for (index in 0..3) {
                    val stage = process.getChildAt(index) as TextView
                    assertTrue(stage.isFocusable && stage.isClickable)
                    assertEquals("android.widget.Button", stage.accessibilityClassName)
                    assertTrue(stage.width >= HealthCenterViews(activity).dp(48))
                    assertTrue(stage.height >= stage.layout.height + stage.paddingTop + stage.paddingBottom)
                    assertTrue(stage.bottom <= process.height)
                    stage.performClick()
                    assertEquals(index, selected)
                    assertEquals(index / 4f, process.phase, 0f)
                    assertTrue(stage.isSelected)
                    assertEquals(1, (0 until process.childCount).count { process.getChildAt(it).isSelected })
                }
            }
        }
    }
    @Test fun cellScreensRenderAndSelectionRestoresAfterRecreation() = native { scenario ->
        for (id in listOf("cell-erythrocyte", "cell-neuron", "cell-neutrophil")) {
            scenario.onActivity {
                it.view("atlas-tab-3").performClick()
                (it.view("atlas-search") as EditText).setText(id)
                it.view("atlas-entry-$id").performClick()
                assertNotNull(it.view("atlas-art-image"))
            }
            capture("$id-structure")
            scenario.onActivity {
                it.view("atlas-tab-3").performClick()
                it.view("atlas-process-stage-2").performClick()
                assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
                val atlas = HealthBodyAtlas.load(it)
                assertTrue((it.view("atlas-simulation-stage") as TextView).text.contains(atlas.mechanism(atlas[id]!!).stages[2]))
            }
            instrumentation.waitForIdleSync()
            scenario.onActivity {
                val scroll = it.view("atlas-scroll") as android.widget.ScrollView
                val diagram = it.view("atlas-process")
                val bounds = android.graphics.Rect(0, 0, diagram.width, diagram.height)
                scroll.offsetDescendantRectToMyCoords(diagram, bounds)
                scroll.scrollTo(0, bounds.top + scroll.scrollY)
            }
            capture("$id-process")
            scenario.recreate()
            await(scenario, "atlas-simulation-progress")
            scenario.onActivity {
                assertEquals(500, (it.view("atlas-simulation-progress") as SeekBar).progress)
                assertTrue(it.view("atlas-process-stage-2").isSelected)
                it.onBackPressed()
            }
        }
    }
    @Test fun stageTapPausesPlaybackWithoutChangingOtherInputs() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick(); it.view("atlas-tab-3").performClick()
            (it.view("atlas-parameter-first") as SeekBar).progress = 60
            it.view("atlas-simulation-play").performClick()
        }
        SystemClock.sleep(150)
        scenario.onActivity { it.view("atlas-process-stage-1").performClick() }
        SystemClock.sleep(250)
        scenario.onActivity {
            assertEquals(250, (it.view("atlas-simulation-progress") as SeekBar).progress)
            assertEquals(60, (it.view("atlas-parameter-first") as SeekBar).progress)
            assertEquals(context.getString(R.string.health_body_play), it.view("atlas-simulation-play").contentDescription)
        }
    }
}
