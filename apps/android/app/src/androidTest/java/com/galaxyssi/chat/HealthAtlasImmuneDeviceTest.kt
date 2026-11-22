package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Bundle
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

class HealthAtlasImmuneDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

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
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { ready(it, "atlas-whole-art"); block(it) }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }
    private fun Activity.open(id: String) {
        view("atlas-tab-3").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick()
    }
    private fun nodes(text: String): List<AccessibilityNodeInfo> {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 6500
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName) {
                val matched = root.findAccessibilityNodeInfosByText(text)
                if (matched.isNotEmpty()) return matched
            }
            SystemClock.sleep(40)
        }
        error("Missing accessibility text: $text")
    }
    private fun capture(name: String, title: String) {
        nodes(title)
        SystemClock.sleep(250)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(context.getExternalFilesDir(null), "body-atlas-immune-$name.png").outputStream().use {
                image.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { image.recycle() }
    }

    @Test fun allTwelvePlatesHaveVisibleDistinctFeaturesAndCorrectOwners() {
        val atlas = HealthBodyAtlas.load(context)
        val plates = HealthAtlasImmunePlates.all
        val scenes = HealthAtlasGranulocyte.entries.map { it.owner } + HealthAtlasImmuneLink.entries.map { it.owner } +
            HealthAtlasBloodDefense.entries.map { it.owner } + HealthAtlasPhagocytosisView.OWNER
        assertEquals(12, plates.size)
        assertEquals(12, plates.map { it.drawable }.toSet().size)
        assertEquals(25, plates.sumOf { it.features.size })
        assertEquals(plates.map { it.owner }.toSet(), scenes.toSet())
        assertEquals(12, scenes.size)
        for (plate in plates) {
            val item = atlas[plate.owner!!]!!
            assertEquals(plate, HealthAtlasPlates.forId(item.id))
            assertEquals(if (item.id == "fragment-platelet") HealthAtlasKind.FRAGMENT else HealthAtlasKind.CELL, item.kind)
            assertTrue(plate.markers.isEmpty())
            assertEquals(plate.features.size, plate.features.map { it.marker.id }.toSet().size)
            val bitmap = Bitmap.createBitmap(360, 280, Bitmap.Config.ARGB_8888)
            try {
                context.getDrawable(plate.drawable)!!.apply { setBounds(0, 0, bitmap.width, bitmap.height); draw(Canvas(bitmap)) }
                assertEquals(0, Color.alpha(bitmap.getPixel(0,0)))
                for (feature in plate.features) {
                    val loc = feature.marker
                    assertTrue("${item.id}/${loc.id}", Color.alpha(bitmap.getPixel((loc.x * 360).toInt(), (loc.y * 280).toInt())) > 180)
                }
            } finally { bitmap.recycle() }
        }
        assertEquals("cell-oligodendrocyte", HealthAtlasPlates.forId("cell-oligodendrocyte")?.owner)
    }

    @Test fun annotationOpensLocalExplanationWithoutChangingTheSelectedEntry() = native { scenario ->
        lateinit var scroll: View
        val feature = HealthAtlasImmunePlates.forId("cell-neutrophil")!!.features.first()
        val atlas = HealthBodyAtlas.load(context)
        scenario.onActivity {
            it.open("cell-neutrophil")
            scroll = it.view("atlas-scroll")
            it.view("atlas-feature-lobulated").performClick()
        }
        assertTrue(nodes(context.getString(feature.explanation)).any { it.isVisibleToUser })
        assertTrue(nodes(context.getString(android.R.string.ok)).any { it.performAction(AccessibilityNodeInfo.ACTION_CLICK) })
        ready(scenario, "atlas-feature-lobulated")
        scenario.onActivity {
            assertSame(scroll, it.view("atlas-scroll"))
            assertEquals(atlas["cell-neutrophil"]!!.name, (it.view("health-page-title") as TextView).text.toString())
        }
        capture("neutrophil", atlas["cell-neutrophil"]!!.name)
    }

    @Test fun localizedFeatureLabelsRemainFocusableAndDoNotOverlapAtLargeType() = native { scenario ->
        scenario.onActivity { activity ->
            for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
                val localized = activity.createConfigurationContext(Configuration(activity.resources.configuration).apply { setLocale(locale) })
                val atlas = HealthBodyAtlas.load(localized)
                for (plate in HealthAtlasImmunePlates.all) {
                    val view = HealthAtlasLabeledImage(activity, plate, "Cell", atlas, plate.owner) { fail("Unexpected navigation") }
                    val labels = (0 until view.childCount).map { view.getChildAt(it) }.filterIsInstance<TextView>()
                    assertEquals(plate.features.size, labels.size)
                    labels.forEach { label ->
                        val feature = plate.features.single { label.tag == "atlas-feature-${it.marker.id}" }
                        label.text = localized.getString(feature.title)
                        label.textSize = 26f
                    }
                    view.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    view.layout(0, 0, view.measuredWidth, view.measuredHeight)
                    var bottom = 0
                    for (label in labels.sortedBy { it.top }) {
                        assertTrue(label.isClickable && label.isFocusable)
                        assertTrue(label.top >= bottom && label.bottom <= view.height)
                        assertTrue(label.height >= label.layout.height + label.compoundPaddingTop + label.compoundPaddingBottom)
                        bottom = label.bottom
                    }
                }
            }
        }
    }

    @Test fun macrophageFramesFollowTheSelectedStageAndRestoreWithoutLeaking() = native { scenario ->
        val plate = HealthAtlasImmunePlates.forId("cell-macrophage")!!
        val atlas = HealthBodyAtlas.load(context)
        val item = atlas[plate.owner!!]!!
        scenario.onActivity {
            it.open(item.id); it.openAtlasModelDetails()
            val scroll = it.view("atlas-scroll")
            val diagram = it.view("atlas-phagocytosis-diagram") as HealthAtlasPhagocytosisView
            for (stage in 0..3) {
                it.view("atlas-process-stage-$stage").performClick()
                assertSame(scroll, it.view("atlas-scroll"))
                assertEquals(stage, diagram.stage)
                assertTrue(diagram.contentDescription.contains(atlas.mechanism(item).stages[stage]))
            }
            it.view("atlas-process-stage-2").performClick()
        }
        capture("macrophage-digesting", item.name)
        scenario.recreate(); ready(scenario, "atlas-phagocytosis-diagram")
        scenario.onActivity {
            assertEquals(2, (it.view("atlas-phagocytosis-diagram") as HealthAtlasPhagocytosisView).stage)
            it.onBackPressed(); it.open("cell-monocyte"); it.openAtlasModelDetails()
            assertNull(it.find("atlas-phagocytosis-diagram"))
        }
    }

    @Test fun eachMacrophageStageDrawsDifferentPixelsAtPhoneAndTabletWidths() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            val diagram = HealthAtlasPhagocytosisView(activity, atlas.mechanism(atlas["cell-macrophage"]!!))
            for (width in listOf(540, 1080, 1600)) {
                diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                diagram.layout(0, 0, width, diagram.measuredHeight)
                fun frame(phase: Float) = Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also {
                    diagram.phase = phase
                    diagram.draw(Canvas(it))
                }
                val frames = listOf(0f, .125f, .25f, .375f, .50f, .75f, 1f).map(::frame)
                val rewind = frame(0f)
                try {
                    for (i in frames.indices) for (j in 0 until i) assertFalse(frames[i].sameAs(frames[j]))
                    frames.forEach { assertTrue(Color.alpha(it.getPixel(it.width / 2, it.height / 2)) > 200) }
                    assertTrue(frames.first().sameAs(rewind))
                    assertEquals(0, diagram.stage)
                } finally { frames.forEach { it.recycle() }; rewind.recycle() }
            }
        }
    }

    @Test fun agentContextUsesTheSelectedMorphologyAndQualitativeStageOnly() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val item = atlas["cell-macrophage"]!!
            val prompt = HealthAtlasAgentContext.prompt(localized, atlas, item, simulation = HealthAtlasSimulation(phase = .5f))
            assertTrue(prompt.contains(atlas.mechanism(item).stages[2]))
            assertTrue(prompt.contains(localized.getString(R.string.health_atlas_feature_vesicle)))
            assertTrue(prompt.contains(localized.getString(R.string.health_atlas_phagocytosis_scope)))
            assertTrue(prompt.contains(HealthAtlasImmunePlates.INNATE))
            assertFalse(prompt.contains(localized.getString(R.string.health_atlas_feature_t_receptor)))
            val other = HealthAtlasAgentContext.prompt(localized, atlas, atlas["cell-monocyte"], simulation = HealthAtlasSimulation())
            assertFalse(other.contains(localized.getString(R.string.health_atlas_phagocytosis_scope)))
            for (lesson in HealthAtlasGranulocyte.entries) {
                val scope = localized.getString(lesson.scope)
                val selected = requireNotNull(atlas[lesson.owner])
                val lessonPrompt = HealthAtlasAgentContext.prompt(localized, atlas, selected,
                    simulation = HealthAtlasSimulation(phase = .75f))
                assertTrue(lessonPrompt.contains(atlas.mechanism(selected).stages[3]))
                assertTrue(lessonPrompt.contains(scope))
                assertFalse(other.contains(scope))
                assertFalse(lessonPrompt.contains(localized.getString(R.string.health_atlas_phagocytosis_scope)))
            }
            for (lesson in HealthAtlasImmuneLink.entries) {
                val scope = localized.getString(lesson.scope)
                val selected = requireNotNull(atlas[lesson.owner])
                val lessonPrompt = HealthAtlasAgentContext.prompt(localized, atlas, selected,
                    simulation = HealthAtlasSimulation(phase = .5f))
                assertTrue(lessonPrompt.contains(atlas.mechanism(selected).stages[2]))
                assertTrue(lessonPrompt.contains(scope))
                assertFalse(prompt.contains(scope))
            }
        }
    }

    @Test fun granulocyteScenesFollowTheLocalPlayheadAndDoNotAppearOnOtherCells() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        for (lesson in HealthAtlasGranulocyte.entries) {
            val item = requireNotNull(atlas[lesson.owner])
            val mechanism = atlas.mechanism(item)
            scenario.onActivity {
                it.open(lesson.owner)
                it.openAtlasModelDetails()
                val scroll = it.view("atlas-scroll")
                val diagram = it.view("atlas-granulocyte-diagram") as HealthAtlasGranulocyteView
                assertEquals(lesson, diagram.lesson)
                assertNull(it.find("atlas-simulation-art"))
                for (stage in mechanism.stages.indices) {
                    it.view("atlas-process-stage-$stage").performClick()
                    assertSame(scroll, it.view("atlas-scroll"))
                    assertSame(diagram, it.view("atlas-granulocyte-diagram"))
                    assertEquals(stage, diagram.stage)
                    assertTrue(diagram.contentDescription.contains(mechanism.stages[stage]))
                }
            }
            scenario.recreate()
            ready(scenario, "atlas-granulocyte-diagram")
            scenario.onActivity {
                assertEquals(3, (it.view("atlas-granulocyte-diagram") as HealthAtlasGranulocyteView).stage)
                it.onBackPressed()
            }
            ready(scenario, "atlas-search")
        }
        scenario.onActivity {
            it.open("cell-monocyte")
            it.openAtlasModelDetails()
            assertNull(it.find("atlas-granulocyte-diagram"))
        }
    }

    @Test fun representativeGranulocyteFramesAdvanceAndRewindAtDifferentWidths() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        scenario.onActivity { activity ->
            for (lesson in HealthAtlasGranulocyte.entries) {
                val diagram = HealthAtlasGranulocyteView(activity, lesson, atlas.mechanism(requireNotNull(atlas[lesson.owner])))
                for (width in listOf(540, 1080, 1600)) {
                    diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    diagram.layout(0, 0, width, diagram.measuredHeight)
                    fun frame(phase: Float) = Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also {
                        diagram.phase = phase
                        diagram.draw(Canvas(it))
                    }
                    val frames = listOf(0f, .125f, .25f, .375f, .5f, .625f, .75f, .875f, 1f).map(::frame)
                    val rewind = frame(0f)
                    try {
                        for (i in 1 until frames.size) assertFalse("$lesson/$width/$i", frames[i].sameAs(frames[i - 1]))
                        assertTrue(rewind.sameAs(frames.first()))
                    } finally { frames.forEach { it.recycle() }; rewind.recycle() }
                }
            }
        }
    }

    @Test fun immuneSceneLinksOpenCanonicalCellsAndRestoreTheOriginalPlayhead() = native { scenario ->
        val atlas = HealthBodyAtlas.load(context)
        for (lesson in HealthAtlasImmuneLink.entries) {
            val item = requireNotNull(atlas[lesson.owner])
            val target = requireNotNull(atlas[lesson.relatedId])
            scenario.onActivity { activity ->
                activity.open(item.id)
                activity.openAtlasModelDetails()
                val row = activity.view("atlas-immune-related-${target.id}")
                val diagram = activity.view("atlas-immune-link-diagram") as HealthAtlasImmuneLinkView
                assertEquals(lesson, diagram.lesson)
                val progress = activity.view("atlas-simulation-progress") as SeekBar
                val seek = Bundle().apply { putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, 830f) }
                assertTrue(progress.performAccessibilityAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.id, seek))
                assertEquals(3, diagram.stage)
                assertEquals(.83f, diagram.phase, .001f)
                assertTrue(diagram.contentDescription.contains(atlas.mechanism(item).stages[3]))
                assertTrue(row.performClick())
                assertEquals(target.name, (activity.view("health-page-title") as TextView).text.toString())
                activity.onBackPressed()
            }
            ready(scenario, "atlas-immune-link-diagram")
            scenario.onActivity { activity ->
                val restored = activity.view("atlas-immune-link-diagram") as HealthAtlasImmuneLinkView
                assertEquals(lesson, restored.lesson)
                assertEquals(.83f, restored.phase, .001f)
                activity.onBackPressed()
            }
            ready(scenario, "atlas-search")
        }
    }

    @Test fun plateletAndPrecursorOpenSeparateLessonsAndKeepTheirOwnPlayheads() = native { scenario ->
        scenario.onActivity { activity ->
            activity.open("cell-megakaryocyte")
            activity.openAtlasModelDetails()
            val precursor = activity.view("atlas-blood-defense-diagram") as HealthAtlasBloodDefenseView
            assertEquals(HealthAtlasBloodDefense.MEGAKARYOCYTE, precursor.lesson)
            activity.view("atlas-process-stage-3").performClick()
            activity.view("atlas-immune-related-fragment-platelet").performClick()
            activity.openAtlasModelDetails()
            val platelet = activity.view("atlas-blood-defense-diagram") as HealthAtlasBloodDefenseView
            assertEquals(HealthAtlasBloodDefense.PLATELET, platelet.lesson)
            assertEquals(0, platelet.stage)
            activity.view("atlas-process-stage-2").performClick()
            activity.onBackPressed()
        }
        ready(scenario, "atlas-blood-defense-diagram")
        scenario.onActivity {
            val restored = it.view("atlas-blood-defense-diagram") as HealthAtlasBloodDefenseView
            assertEquals(HealthAtlasBloodDefense.MEGAKARYOCYTE, restored.lesson)
            assertEquals(3, restored.stage)
        }
    }
}
