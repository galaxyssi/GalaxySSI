package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Rect
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
    private fun await(scenario: ActivityScenario<HealthBodyAtlasActivity>, reason: String,
        predicate: (HealthBodyAtlasActivity) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < until) {
            scenario.onActivity { ready = predicate(it) }
            if (!ready) SystemClock.sleep(40)
        }
        assertTrue(reason, ready)
    }

    private fun native(names: HealthOverviewDatabases = HealthOverviewDatabases(java.util.UUID.randomUUID().toString()),
        block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        try { ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(names)).use { scenario ->
            await(scenario, "Atlas did not load") { it.window.decorView.tagged("atlas-whole-art") != null }
            block(scenario)
        } } finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun wholeBodyPanelKeepsTheSelectedOrganAndOpensItsScopedTrend() {
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        native(names) { scenario ->
            scenario.onActivity { activity ->
                assertNotNull(activity.view("atlas-whole-structure-heart"))
                activity.view("atlas-whole-action-structure").performClick()
                assertTrue(activity.view("atlas-tab-0").isSelected)
                activity.onBackPressed()
                activity.view("atlas-whole-action-metrics").performClick()
                assertTrue(activity.view("atlas-tab-2").isSelected)
                assertNotNull(activity.view("atlas-metric-BLOOD_PRESSURE"))
                activity.onBackPressed()
                activity.view("atlas-hotspot-liver").performClick()
                activity.onBackPressed()
                assertNotNull(activity.view("atlas-whole-structure-liver"))
            }
            scenario.recreate()
            await(scenario, "Whole-body organ selection was lost") {
                it.window.decorView.tagged("atlas-whole-structure-liver") != null
            }
            scenario.onActivity { it.view("atlas-whole-action-trend").performClick() }
            await(scenario, "Trend shortcut did not reveal the chart") { activity ->
                val chart = activity.window.decorView.tagged("atlas-personal-chart")
                val visible = Rect()
                chart != null && chart.height > 0 && chart.getLocalVisibleRect(visible) && visible.height() == chart.height
            }
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                assertTrue(privacy.page().entries.any {
                    it.scope.purpose == HealthAccessPurpose.TREND && it.scope.metrics == setOf(HealthMetric.ALT)
                })
            }
            scenario.onActivity {
                it.onBackPressed()
                it.view("atlas-hotspot-brain").performClick()
                it.onBackPressed()
                assertFalse(it.view("atlas-whole-action-trend").isEnabled)
            }
        }
    }

    @Test fun wholeBodyTrendShortcutRespectsDeniedMetricAccess() {
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        native(names) { scenario ->
            HealthPrivacyStore(context, names.privacy).use {
                it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
            }
            scenario.onActivity { it.view("atlas-whole-action-trend").performClick() }
            await(scenario, "Trend permission denial was not surfaced") {
                it.window.decorView.tagged("atlas-personal-blocked") != null
            }
            scenario.onActivity {
                assertNull(it.window.decorView.tagged("atlas-personal-chart"))
                assertNull(it.window.decorView.tagged("atlas-metric-reading-BLOOD_PRESSURE"))
                assertFalse(it.view("atlas-ask").isEnabled)
            }
        }
    }

    @Test fun wholeBodyQuickActionsFitLargeLabelsAtPhoneWidth() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            val panel = HealthAtlasUi.wholeBodyActions(activity, atlas, requireNotNull(atlas["heart"]), {}, {}, {})
            val row = panel.tagged("atlas-whole-actions") as ViewGroup
            val ui = HealthCenterViews(activity)
            val width = ui.dp(300)
            val buttons = (0 until row.childCount).map { row.getChildAt(it) as TextView }
            buttons.forEach { it.textSize = 26f }
            panel.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            panel.layout(0, 0, width, panel.measuredHeight)
            assertEquals(3, buttons.size)
            for (button in buttons) {
                assertTrue(button.left >= 0 && button.right <= row.width)
                assertTrue(button.height >= ui.dp(48))
                assertTrue(button.layout.height + button.compoundPaddingTop + button.compoundPaddingBottom <= button.height)
            }
            assertTrue(buttons.zipWithNext().all { (left, right) -> left.right <= right.left })
        }
    }

    @Test fun relatedMeasurementsShowOnlyMappedLatestReadingsAndKeepTrendsScopedToTheirOwnPeriod() {
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        val now = System.currentTimeMillis()
        val pressure = HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "119", "diastolic" to "77"), "mmHg", now)
        val ldl = HealthDraft(HealthMetric.LDL, mapOf("ldl" to "2.7"), "mmol/L", now - 45L * 24 * 60 * 60 * 1_000)
        val unrelated = HealthDraft(HealthMetric.ALT, mapOf("alt" to "55"), "U/L", now)
        HealthRecordStore(context, names.records).use { store ->
            listOf(pressure, ldl, unrelated).forEach { assertTrue(store.save(it) is HealthSaveResult.Saved) }
        }
        native(names) { scenario ->
            scenario.onActivity { it.view("atlas-whole-action-metrics").performClick() }
            await(scenario, "Latest real readings were not shown together") { activity ->
                val decor = activity.window.decorView
                (decor.tagged("atlas-metric-reading-BLOOD_PRESSURE") as? TextView)?.text == healthDisplayValue(pressure) &&
                    (decor.tagged("atlas-metric-reading-LDL") as? TextView)?.text == healthDisplayValue(ldl)
            }
            scenario.onActivity { activity ->
                assertNull(activity.window.decorView.tagged("atlas-metric-ALT"))
                val row = activity.view("atlas-metric-LDL") as ViewGroup
                val details = (row.getChildAt(0) as ViewGroup).getChildAt(1) as TextView
                assertTrue(details.text.contains(activity.getString(healthRecordSourceResource("manual"))))
                row.performClick()
            }
            await(scenario, "Selected LDL trend did not load") { activity ->
                activity.view("atlas-metric-LDL").isSelected &&
                    activity.window.decorView.tagged("atlas-personal-chart") != null
            }
            scenario.onActivity { activity ->
                assertFalse(activity.view("atlas-ask").isEnabled)
                assertEquals(activity.getString(R.string.health_atlas_metric_trend_title, activity.getString(HealthMetric.LDL.titleResource())),
                    (activity.view("atlas-personal-trend-title") as TextView).text)
                activity.view("atlas-period-2").performClick()
            }
            await(scenario, "Yearly LDL trend did not include the older reading") { it.view("atlas-ask").isEnabled }
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                val events = privacy.page().entries
                assertTrue(events.any { it.scope.purpose == HealthAccessPurpose.TREND && it.scope.metrics == setOf(HealthMetric.LDL) })
                assertTrue(events.filter { it.scope.purpose == HealthAccessPurpose.OVERVIEW }.all { HealthMetric.ALT !in it.scope.metrics })
            }
        }
    }
    @Test fun completeCatalogueHasCanonicalStructuresAndSeparatePlateletFragments() {
        val data = HealthBodyAtlas.load(context)
        assertEquals(14, data.systems.size)
        assertEquals(177, data.items.count { it.kind == HealthAtlasKind.ORGAN })
        assertEquals(14, data.tissues.size)
        assertEquals(107, data.items.count { it.kind == HealthAtlasKind.CELL })
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
        val plates = HealthAtlasPlates.all
        assertEquals(plates.size, plates.map { it.drawable }.toSet().size)
        data.items.forEach { assertEquals("Missing dedicated artwork for ${it.id}", it.id, HealthAtlasPlates.forId(it.id)?.owner) }
        val valveLocator = HealthAtlasPlates.viewsForId("heart-valves").single { it.owner == "heart" }
        assertEquals(HealthAtlasHeartSection.valves.drawable, valveLocator.drawable)
        assertEquals(HealthAtlasHeartSection.valves.markers, valveLocator.markers)
        assertTrue(HealthAtlasPlates.viewsForId("glomerulus").any { it.owner == "nephron" })
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
                val bottoms = mutableMapOf<Int, Int>()
                labels.sortedBy { it.top }.forEach { label ->
                    assertTrue("Clipped or overlapping label: ${label.text}, ${label.top}..${label.bottom} in ${view.height}",
                        label.top >= (bottoms[label.left] ?: 0) && label.bottom <= view.height)
                    assertTrue(label.height >= label.layout.height + label.compoundPaddingTop + label.compoundPaddingBottom)
                    bottoms[label.left] = label.bottom
                    val key = label.tag.toString()
                    if (key.startsWith("atlas-feature-")) assertTrue(label.isClickable && label.isFocusable)
                    else if (label.isSelected) { assertFalse(label.performClick()); assertNull(tapped) }
                    else {
                        assertTrue(key.startsWith("atlas-hotspot-"))
                        assertTrue(label.performClick())
                        assertEquals(key.removePrefix("atlas-hotspot-"), tapped)
                        tapped = null
                    }
                }
                if (plate.owner == null) assertTrue((bottoms.values.maxOrNull() ?: 0) <= view.height - HealthCenterViews(activity).dp(144))
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
                val direct = requireNotNull(HealthAtlasRegionalDetailPlates.forId(child))
                assertTrue(activity.view("atlas-view-0").isSelected)
                assertTrue(activity.view("atlas-feature-${direct.features.first().marker.id}").isClickable)
                activity.view("atlas-view-1").performClick()
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
            val views = HealthAtlasPlates.viewsForId(item.id)
            assertEquals(listOf("renal-pelvis", "kidneys"), views.map { it.owner })
            for (expected in views) {
                var openedPlate: HealthAtlasPlate? = null
                var openedTitle = ""
                val art = HealthAtlasArtwork(activity, data, item, {}, zoom = { plate, title ->
                    openedPlate = plate; openedTitle = title
                }, initialView = expected.viewKey)
                val picture = requireNotNull(art.tagged("atlas-art-image"))
                val target = picture.parent as HealthAtlasLabeledImage
                target.scaleX = 2f; target.scaleY = 2f; target.translationX = 30f
                art.tagged("atlas-art-reset")!!.performClick()
                assertEquals(1f, target.scaleX, 0f); assertEquals(1f, target.scaleY, 0f)
                assertEquals(0f, target.translationX, 0f)
                assertEquals(1f, (target.parent as GalaxySSIPinchZoomViewport).currentZoomScale, 0f)
                art.tagged("atlas-fullscreen")!!.performClick()
                assertEquals(expected, openedPlate)
                assertEquals("${item.name} · ${expected.caption(activity, data, item)}", openedTitle)
            }
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
            activity.view("atlas-hotspot-heart").performClick(); activity.openAtlasModelDetails()
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
            activity.view("atlas-hotspot-heart").performClick(); activity.openAtlasModelDetails()
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
        scenario.onActivity { it.openAtlasModelDetails() }; capture("simulation")
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
