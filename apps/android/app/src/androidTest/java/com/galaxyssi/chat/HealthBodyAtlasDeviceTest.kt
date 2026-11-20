package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
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

class HealthBodyAtlasDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun View.tagged(value: String): View? = if (tag == value) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(value) } else null
    private fun Activity.view(tag: String): View = requireNotNull(window.decorView.tagged(tag)) { tag }
    private fun native(names: HealthOverviewDatabases = HealthOverviewDatabases(java.util.UUID.randomUUID().toString()),
        block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        try { ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(names)).use { scenario ->
            val until = SystemClock.elapsedRealtime() + 15_000
            var loaded = false
            while (!loaded && SystemClock.elapsedRealtime() < until) {
                scenario.onActivity { loaded = it.window.decorView.tagged("atlas-whole-art") != null }
                if (!loaded) SystemClock.sleep(40)
            }
            assertTrue("Atlas did not load", loaded); block(scenario)
        } } finally { clearHealthOverviewFixture(context, names) }
    }
    @Test fun completeCatalogueHasCanonicalStructuresAndSeparatePlateletFragments() {
        val data = HealthBodyAtlas.load(context)
        assertEquals(14, data.systems.size)
        assertEquals(177, data.items.count { it.kind == HealthAtlasKind.ORGAN })
        assertEquals(14, data.tissues.size)
        assertEquals(105, data.items.count { it.kind == HealthAtlasKind.CELL })
        assertEquals(1, data.items.count { it.kind == HealthAtlasKind.FRAGMENT })
        assertEquals(HealthAtlasKind.SYSTEM, data["skin"]!!.kind)
        assertEquals(HealthAtlasKind.ORGAN, data["skin-organ"]!!.kind)
        assertTrue(data.children(data["skin"]!!).any { it.id == "skin-organ" })
        assertEquals(setOf("digestive", "endocrine"), data["pancreas"]!!.systems.toSet())
        assertTrue(data.cells(data["pancreatic-islets"]!!).any { it.id == "cell-pancreatic-beta-cell" })
        assertTrue(data.items.all { data.mechanism(it).stages.size == 4 })
        assertTrue(data.search("beta", HealthAtlasKind.CELL).any { it.id == "cell-pancreatic-beta-cell" })
        assertTrue(data.search("heart", HealthAtlasKind.ORGAN).any { it.id == "heart" })
        assertFalse(data.search("nonexistent-structure", null).isNotEmpty())
    }
    @Test fun platesHaveCanonicalVisibleMarkersAndDoNotInventHiddenStructures() {
        val data = HealthBodyAtlas.load(context)
        assertEquals(87, HealthAtlasPlates.all.size)
        assertEquals(87, HealthAtlasPlates.all.map { it.drawable }.toSet().size)
        assertEquals(HealthAtlasHeartSection.valves, HealthAtlasPlates.forId("heart-valves"))
        assertEquals("nephron", HealthAtlasPlates.forId("glomerulus")!!.owner)
        assertEquals("cell-podocyte", HealthAtlasPlates.forId("cell-podocyte")?.owner)
        HealthAtlasPlates.all.forEach { plate ->
            assertEquals(plate.markers.size, plate.markers.map { it.id }.toSet().size)
            plate.markers.forEach { assertNotNull(data[it.id]) }
        }
        for (id in listOf("brain", "lungs", "liver", "kidneys")) {
            val plate = requireNotNull(HealthAtlasPlates.forId(id))
            val image = android.graphics.BitmapFactory.decodeResource(context.resources, plate.drawable)
            try {
                assertTrue(image.width >= 512 && image.height >= 512)
                assertEquals(0, android.graphics.Color.alpha(image.getPixel(0, 0)))
                plate.markers.forEach { marker ->
                    assertTrue("Marker outside depicted anatomy: ${marker.id}", android.graphics.Color.alpha(
                        image.getPixel((marker.x * image.width).toInt(), (marker.y * image.height).toInt())) > 200)
                }
            } finally { image.recycle() }
        }
        for (id in listOf("renal-cortex", "renal-medulla", "renal-pelvis")) {
            assertTrue(data.children(data["kidneys"]!!).contains(data[id]))
            assertTrue(HealthAtlasMetrics.forItem(data[id]!!).contains(HealthMetric.CREATININE))
        }
    }
    @Test fun organPlateLabelsStaySeparatedWithLargeTextAndDispatchCanonicalIds() = native { scenario ->
        scenario.onActivity { activity ->
            val data = HealthBodyAtlas.load(activity)
            HealthAtlasPlates.all.filter { it.markers.isNotEmpty() }.forEach { plate ->
                val selectedId = plate.markers.first().id
                var tapped: String? = null
                val view = HealthAtlasLabeledImage(activity, plate, "Test", data, selectedId) { tapped = it.id }
                val labels = (0 until view.childCount).map { view.getChildAt(it) }.filterIsInstance<TextView>()
                labels.forEach { it.textSize = 26f }
                view.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(2400, View.MeasureSpec.AT_MOST))
                view.layout(0, 0, view.measuredWidth, view.measuredHeight)
                var bottom = 0
                labels.sortedBy { it.top }.forEach { label ->
                    assertTrue("Clipped or overlapping label: ${label.text}, ${label.top}..${label.bottom} in ${view.height}",
                        label.top >= bottom && label.bottom <= view.height)
                    assertTrue(label.height >= label.layout.height + label.compoundPaddingTop + label.compoundPaddingBottom)
                    bottom = label.bottom
                    if (label.isSelected) { assertFalse(label.performClick()); assertNull(tapped) }
                    else { label.performClick(); assertEquals(label.tag.toString().removePrefix("atlas-hotspot-"), tapped); tapped = null }
                }
                if (plate.owner == null) assertTrue(bottom <= view.height - HealthCenterViews(activity).dp(144))
            }
        }
    }
    @Test fun organPlatesRenderAndSharedViewsKeepTheirContextOnBack() = native { scenario ->
        fun capture(name: String) {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync(); SystemClock.sleep(150)
            val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            try { java.io.File(context.getExternalFilesDir(null), "body-atlas-plate-$name.png").outputStream().use {
                image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            } } finally { image.recycle() }
        }
        for ((id, child) in listOf("brain" to "cerebellum", "lungs" to "bronchi", "liver" to "gallbladder", "kidneys" to "renal-pelvis")) {
            scenario.onActivity { activity ->
                activity.view("atlas-tab-2").performClick()
                (activity.view("atlas-search") as EditText).setText(id)
                activity.view("atlas-entry-$id").performClick()
            }
            capture(id)
            scenario.onActivity { activity ->
                activity.view("atlas-hotspot-$child").performClick()
                assertTrue(activity.view("atlas-hotspot-$child").isSelected)
                assertFalse(activity.view("atlas-hotspot-$child").performClick())
                val data = HealthBodyAtlas.load(activity)
                assertTrue((activity.view("atlas-art-caption") as TextView).text.contains(data[id]!!.name))
                activity.view("atlas-art-reset").performClick()
            }
            if (id == "kidneys") capture("renal-pelvis")
            scenario.onActivity { activity ->
                activity.onBackPressed()
                assertFalse(activity.view("atlas-hotspot-$child").isSelected)
                activity.onBackPressed()
                assertNotNull(activity.view("atlas-search"))
            }
        }
    }
    @Test fun artworkResetAndFullscreenKeepTheSameAnatomicalContext() = native { scenario ->
        scenario.onActivity { activity ->
            val data = HealthBodyAtlas.load(activity)
            val item = data["renal-pelvis"]!!
            var openedResource = 0
            var openedTitle = ""
            val art = HealthAtlasArtwork(activity, data, item, {}, zoom = { resource, title ->
                openedResource = resource; openedTitle = title
            })
            val picture = requireNotNull(art.tagged("atlas-art-image"))
            val target = picture.parent as HealthAtlasLabeledImage
            target.scaleX = 2f; target.scaleY = 2f; target.translationX = 30f
            art.tagged("atlas-art-reset")!!.performClick()
            assertEquals(1f, target.scaleX, 0f); assertEquals(1f, target.scaleY, 0f)
            assertEquals(0f, target.translationX, 0f)
            assertEquals(1f, (target.parent as GalaxySSIPinchZoomViewport).currentZoomScale, 0f)
            art.tagged("atlas-fullscreen")!!.performClick()
            assertEquals(R.drawable.health_atlas_kidney, openedResource)
            assertTrue(openedTitle.contains(item.name) && openedTitle.contains(data["kidneys"]!!.name))
        }
    }
    @Test fun wholeBodyToolsDoNotCoverLabelsAtNarrowWidths() = native { scenario ->
        scenario.onActivity { activity ->
            val data = HealthBodyAtlas.load(activity)
            for (width in listOf(720, 1080)) {
                val art = HealthAtlasArtwork(activity, data, null, {}, { _, _ -> })
                HealthAtlasPlates.whole.markers.forEach { (art.tagged("atlas-hotspot-${it.id}") as TextView).textSize = 26f }
                art.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                art.layout(0, 0, art.measuredWidth, art.measuredHeight)
                val controls = art.tagged("atlas-layers")!!.parent as View
                HealthAtlasPlates.whole.markers.forEach {
                    val label = art.tagged("atlas-hotspot-${it.id}")!!
                    assertTrue("Tools obscure ${it.id}", label.bottom <= controls.top)
                    assertTrue(label.top >= 0)
                }
            }
        }
    }
    @Test fun fullscreenShowsThePlateAndReturnsToTheSelectedStructure() = native { scenario ->
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        var description = ""
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-brain").performClick()
            description = activity.view("atlas-art-image").contentDescription.toString()
            activity.view("atlas-fullscreen").performClick()
        }
        instrumentation.waitForIdleSync()
        fun imageIn(node: android.view.accessibility.AccessibilityNodeInfo?): Boolean {
            if (node == null) return false
            if (node.className == "android.widget.ImageView" && node.contentDescription?.toString() == description) return true
            return (0 until node.childCount).any { imageIn(node.getChild(it)) }
        }
        val shownBy = SystemClock.elapsedRealtime() + 5_000
        var active = instrumentation.uiAutomation.rootInActiveWindow
        while (active?.findAccessibilityNodeInfosByText(description).isNullOrEmpty() && SystemClock.elapsedRealtime() < shownBy) {
            SystemClock.sleep(50); active = instrumentation.uiAutomation.rootInActiveWindow
        }
        val root = requireNotNull(active)
        assertEquals(context.packageName, root.packageName.toString())
        assertTrue(imageIn(root))
        assertTrue(root.findAccessibilityNodeInfosByText(description).isNotEmpty())
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-plate-fullscreen.png").outputStream().use {
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        instrumentation.waitForIdleSync()
        val focusedBy = SystemClock.elapsedRealtime() + 5_000
        var focused = false
        while (!focused && SystemClock.elapsedRealtime() < focusedBy) {
            scenario.onActivity { focused = it.hasWindowFocus() }
            if (!focused) SystemClock.sleep(50)
        }
        scenario.onActivity {
            assertEquals(description, it.view("atlas-art-image").contentDescription.toString())
            assertTrue(it.view("atlas-tab-0").isSelected)
            assertTrue(it.hasWindowFocus())
        }
    }
    @Test fun teachingEquationsDoNotDependOnHealthRecords() {
        assertEquals(4.9, HealthAtlasSimulation().cardiacOutput(), 0.0001)
        assertEquals(7.0, HealthAtlasSimulation(100,70).cardiacOutput(), 0.0001)
        assertEquals(6.0, HealthAtlasSimulation.initial("lungs").minuteVentilation(), 0.0001)
        assertTrue(runCatching { HealthAtlasSimulation(0,70).cardiacOutput() }.isFailure)
        assertEquals(3, HealthAtlasSimulation(phase = 1f).stage)
        val data = HealthBodyAtlas.load(context)
        assertEquals(listOf(HealthMetric.GLUCOSE, HealthMetric.HBA1C), HealthAtlasMetrics.forItem(data["cell-pancreatic-beta-cell"]!!))
        assertTrue(HealthAtlasMetrics.forItem(data["cell-neuron"]!!).isEmpty())
    }
    @Test fun catalogueIconsHaveVisibleDistinctGeometry() {
        val data = HealthBodyAtlas.load(context)
        val hashes = hashSetOf<Int>()
        (data.systems + data["cell-neuron"]!!).forEach { item ->
            val bitmap = android.graphics.Bitmap.createBitmap(64, 64, android.graphics.Bitmap.Config.ARGB_8888)
            try {
                requireNotNull(context.getDrawable(HealthAtlasUi.icon(item))).apply {
                    setBounds(0, 0, 64, 64); draw(android.graphics.Canvas(bitmap))
                }
                val pixels = IntArray(64 * 64); bitmap.getPixels(pixels, 0, 64, 0, 0, 64, 64)
                assertTrue("Blank icon: ${item.id}", pixels.count { android.graphics.Color.alpha(it) > 32 } > 60)
                assertTrue("Repeated category icon: ${item.id}", hashes.add(java.util.Arrays.hashCode(pixels)))
            } finally { bitmap.recycle() }
        }
    }
    @Test fun searchAndDrilldownRemainNativeAndRestoreSelection() = native { scenario ->
        scenario.onActivity { activity ->
            activity.view("atlas-tab-3").performClick()
            (activity.view("atlas-search") as EditText).setText("beta")
            activity.view("atlas-entry-cell-pancreatic-beta-cell").performClick()
            activity.view("atlas-tab-1").performClick()
            assertTrue(activity.view("atlas-tab-1").isSelected)
        }
        scenario.recreate()
        val until = SystemClock.elapsedRealtime() + 10_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < until) {
            scenario.onActivity { found = it.window.decorView.tagged("atlas-tab-1")?.isSelected == true }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue(found)
        scenario.onActivity { it.onBackPressed(); assertNotNull(it.view("atlas-search")) }
    }
    @Test fun simulationInputsResetAndAnimationStopsInBackground() = native { scenario ->
        var phase = 0
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-heart").performClick(); activity.view("atlas-tab-3").performClick()
            (activity.view("atlas-parameter-first") as SeekBar).progress = 60
            assertTrue((activity.view("atlas-simulation-output") as TextView).text.toString().contains("7"))
            activity.view("atlas-simulation-reset").performClick()
            assertEquals(30, (activity.view("atlas-parameter-first") as SeekBar).progress)
            activity.view("atlas-simulation-play").performClick()
        }
        SystemClock.sleep(250)
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { phase = (it.view("atlas-simulation-progress") as SeekBar).progress }
        SystemClock.sleep(200)
        scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity { assertEquals(phase, (it.view("atlas-simulation-progress") as SeekBar).progress) }
    }
    @Test fun simulationChangesPixelsAndRestoresItsOwnParameters() = native { scenario ->
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-heart").performClick(); activity.view("atlas-tab-3").performClick()
            (activity.view("atlas-parameter-first") as SeekBar).progress = 60
        }
        scenario.recreate()
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var restored = false
        while (!restored && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { restored = it.window.decorView.tagged("atlas-parameter-first") != null }
            if (!restored) SystemClock.sleep(40)
        }
        assertTrue(restored)
        scenario.onActivity { activity ->
            assertEquals(60, (activity.view("atlas-parameter-first") as SeekBar).progress)
            val diagram = activity.view("atlas-process") as HealthAtlasCirculationView
            fun draw() = android.graphics.Bitmap.createBitmap(diagram.width, diagram.height, android.graphics.Bitmap.Config.ARGB_8888)
                .also { diagram.draw(android.graphics.Canvas(it)) }
            diagram.phase = 0f; val first = draw()
            diagram.phase = .6f; val second = draw()
            try { assertFalse("Process must visibly advance", first.sameAs(second)) } finally { first.recycle(); second.recycle() }
        }
    }
    @Test fun personalValuesUseOnlyTheScopedFixtureAndClearTheirChartOnBackground() {
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        HealthRecordStore(context, names.records).use { store ->
            assertTrue(store.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "121", "diastolic" to "79"),
                "mmHg", System.currentTimeMillis())) is HealthSaveResult.Saved)
        }
        native(names) { scenario ->
            scenario.onActivity { it.view("atlas-hotspot-heart").performClick(); it.view("atlas-tab-2").performClick() }
            scenario.onActivity { it.view("atlas-period-0").performClick() }
            val deadline = SystemClock.elapsedRealtime() + 15_000
            var chart: HealthTrendChart? = null
            while (chart == null && SystemClock.elapsedRealtime() < deadline) {
                scenario.onActivity { chart = it.window.decorView.tagged("atlas-personal-chart") as? HealthTrendChart }
                if (chart == null) SystemClock.sleep(50)
            }
            val observed = requireNotNull(chart)
            assertTrue(observed.isEnabled)
            scenario.moveToState(Lifecycle.State.CREATED)
            assertEquals("", observed.contentDescription.toString())
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { assertTrue(it.view("atlas-period-0").isSelected) }
        }
    }
    @Test fun publicTeachingScreensRenderArtworkAndNativeControls() = native { scenario ->
        fun capture(name: String) {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync(); SystemClock.sleep(180)
            val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            try {
                assertTrue(bitmap.width > 300 && bitmap.height > 500)
                java.io.File(context.getExternalFilesDir(null), "body-atlas-$name.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally { bitmap.recycle() }
        }
        capture("whole")
        scenario.onActivity { it.view("atlas-hotspot-heart").performClick() }; capture("heart")
        scenario.onActivity { it.view("atlas-tab-3").performClick() }; capture("simulation")
        scenario.onActivity { it.onBackPressed(); it.view("atlas-tab-1").performClick() }; capture("systems")
        scenario.onActivity {
            it.view("atlas-tab-3").performClick(); (it.view("atlas-search") as EditText).setText("beta")
            it.view("atlas-entry-cell-pancreatic-beta-cell").performClick()
        }; capture("beta")
    }
    @Test fun researchTabsAndParametersSurviveRecreationAndStructureDrilldown() = native { scenario ->
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-heart").performClick(); activity.view("atlas-tab-1").performClick()
            activity.view("atlas-open-research").performClick()
            activity.view("atlas-research-tab-1").performClick()
            (activity.view("atlas-elimination-half-life") as SeekBar).progress = 7
            (activity.view("atlas-elimination-elapsed") as SeekBar).progress = 16
            assertTrue((activity.view("atlas-elimination-output") as TextView).text.toString().contains("25"))
            activity.view("atlas-adme-liver").performClick()
        }
        scenario.recreate()
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var loaded = false
        while (!loaded && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { loaded = it.window.decorView.tagged("atlas-tab-0") != null }
            if (!loaded) SystemClock.sleep(40)
        }
        assertTrue(loaded)
        scenario.onActivity { activity ->
            activity.onBackPressed()
            assertTrue(activity.view("atlas-research-tab-1").isSelected)
            assertEquals(7, (activity.view("atlas-elimination-half-life") as SeekBar).progress)
            assertEquals(16, (activity.view("atlas-elimination-elapsed") as SeekBar).progress)
            activity.view("atlas-research-tab-2").performClick()
            assertNotNull(activity.view("atlas-source-aging"))
            activity.view("atlas-research-tab-1").performClick()
            assertEquals(7, (activity.view("atlas-elimination-half-life") as SeekBar).progress)
            activity.view("atlas-elimination-reset").performClick()
            assertEquals(3, (activity.view("atlas-elimination-half-life") as SeekBar).progress)
            activity.onBackPressed(); assertTrue(activity.view("atlas-tab-1").isSelected)
        }
    }
    @Test fun researchChartsChangeWithInputsWithoutAnyHealthRecords() = native { scenario ->
        scenario.onActivity { activity ->
            val chart = HealthAtlasEliminationChart(activity)
            chart.measure(View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            chart.layout(0, 0, chart.measuredWidth, chart.measuredHeight)
            fun draw() = android.graphics.Bitmap.createBitmap(chart.width, chart.height, android.graphics.Bitmap.Config.ARGB_8888)
                .also { chart.draw(android.graphics.Canvas(it)) }
            val before = draw(); chart.model = HealthAtlasElimination(12, 24); val after = draw()
            try { assertFalse(before.sameAs(after)); assertTrue(chart.contentDescription.toString().contains("25")) }
            finally { before.recycle(); after.recycle() }
        }
    }
    @Test fun longProcessLabelsExpandInsteadOfBeingTruncated() = native { scenario ->
        scenario.onActivity { activity ->
            fun measured(text: String): Int {
                val view = HealthAtlasProcessView(activity, HealthAtlasMechanism("test", "teaching", "Test", List(4) { text }, "test"))
                view.measure(View.MeasureSpec.makeMeasureSpec(420, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                return view.measuredHeight
            }
            assertTrue(measured("Regulation of nutrient absorption and distribution across several interacting tissues ".repeat(3)) > measured("Absorb"))
        }
    }
    @Test fun researchSourcesAreExplicitForEveryCatalogueEntry() {
        val atlas = HealthBodyAtlas.load(context)
        atlas.items.forEach { item -> HealthAtlasResearchTopic.entries.forEach { topic ->
            val sources = HealthAtlasResearchSources.forTopic(topic, atlas.mechanism(item))
            assertTrue(sources.isNotEmpty() && sources.all { it.startsWith("https://") })
            if (topic == HealthAtlasResearchTopic.AGING) assertTrue(sources.contains(HealthAtlasResearchSources.AGING))
        } }
    }
    @Test fun researchScreensRenderTheSelectedStructureAndEvidence() = native { scenario ->
        fun capture(name: String) {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync(); SystemClock.sleep(150)
            val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            try { java.io.File(context.getExternalFilesDir(null), "body-atlas-research-$name.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            } } finally { bitmap.recycle() }
        }
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick(); it.view("atlas-tab-1").performClick(); it.view("atlas-open-research").performClick()
        }
        for ((index, name) in listOf("physiology", "drugs", "aging").withIndex()) {
            scenario.onActivity { it.view("atlas-research-tab-$index").performClick() }
            capture(name)
            if (index == 1) {
                scenario.onActivity { activity ->
                    val output = activity.view("atlas-elimination-output")
                    (activity.view("atlas-scroll") as android.widget.ScrollView).scrollTo(0, output.top)
                }
                capture("model")
            }
        }
    }
}
