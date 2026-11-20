package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasAgingDeviceTest {
    private val instrument get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrument.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(tag) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue(tag, found)
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrument.uiAutomation
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(fixture)).use { ready(it, "atlas-whole-art"); block(it) }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }
    private fun Activity.openResearch() {
        view("atlas-tab-1").performClick()
        view("atlas-open-research").performClick()
        view("atlas-research-tab-2").performClick()
    }
    private fun nodes(text: String): List<AccessibilityNodeInfo> {
        instrument.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 6000
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrument.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName) {
                val matches = root.findAccessibilityNodeInfosByText(text)
                if (matches.isNotEmpty()) return matches
            }
            SystemClock.sleep(40)
        }
        error("Missing accessibility text: $text")
    }
    private fun selectTopic(scenario: ActivityScenario<HealthBodyAtlasActivity>, topic: HealthAtlasAgingTopic) {
        scenario.onActivity { it.view("atlas-aging-picker").performClick() }
        val title = context.getString(topic.title)
        assertTrue(nodes(title).filter { it.text?.toString() == title }.any { label ->
            generateSequence(label) { it.parent }.firstOrNull { it.isClickable }
                ?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
        })
        instrument.waitForIdleSync()
    }

    @Test fun allTwelveTopicsHaveDistinctLocalizedMechanismsAndValidLinks() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val entries = HealthAtlasAgingTopic.entries
            assertEquals(12, entries.map { localized.getString(it.title) }.toSet().size)
            assertEquals(12, entries.map { localized.getString(it.explanation) }.toSet().size)
            entries.forEach { topic ->
                assertNotNull(atlas[topic.exampleId])
                assertEquals(4, topic.steps(localized).filter { it.isNotBlank() }.toSet().size)
                val selection = HealthAtlasAgingSelection(topic, 2)
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas["heart"], topic = HealthAtlasResearchTopic.AGING, aging = selection)
                assertTrue(prompt.contains(selection.stageLabel(localized)))
                assertTrue(prompt.contains(HealthAtlasResearchSources.AGING))
                topic.study?.let { assertTrue(prompt.contains(it.source) && prompt.contains(localized.getString(it.limits))) }
                for (other in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.PHYSIOLOGY, null)) {
                    val unrelated = HealthAtlasAgentContext.prompt(localized, atlas, atlas["heart"], topic = other, aging = selection)
                    assertFalse(unrelated.contains(localized.getString(topic.explanation)))
                    topic.study?.let { assertFalse(unrelated.contains(it.source)) }
                }
            }
        }
    }

    @Test fun pickerUpdatesLocallyAndSelectionSurvivesDrilldownRecreationAndTabChanges() = native { scenario ->
        var scroll: View? = null
        var ask: View? = null
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick(); it.openResearch()
            scroll = it.view("atlas-scroll"); ask = it.view("atlas-ask")
            assertNull(it.window.decorView.tagged("atlas-aging-study"))
        }
        selectTopic(scenario, HealthAtlasAgingTopic.TELOMERES)
        scenario.onActivity {
            assertSame(scroll, it.view("atlas-scroll")); assertSame(ask, it.view("atlas-ask"))
            assertNotNull(it.view("atlas-aging-study"))
            it.view("atlas-process-stage-2").performClick()
            it.view("atlas-aging-related").performClick()
            assertEquals(HealthBodyAtlas.load(it)["skin-organ"]!!.name, (it.view("health-page-title") as TextView).text.toString())
            it.openResearch()
            assertTrue(it.view("atlas-process-stage-0").isSelected)
        }
        scenario.recreate(); ready(scenario, "atlas-aging-stage")
        scenario.onActivity {
            it.onBackPressed(); it.onBackPressed()
            assertTrue(it.view("atlas-research-tab-2").isSelected)
            assertTrue(it.view("atlas-process-stage-2").isSelected)
            it.view("atlas-research-tab-1").performClick()
            assertNull(it.window.decorView.tagged("atlas-aging-study"))
            it.view("atlas-research-tab-2").performClick()
            assertTrue(it.view("atlas-process-stage-2").isSelected)
        }
    }

    @Test fun sourcedStudyAndStageReachActualAgentPreviewWithoutSubmitting() = native { scenario ->
        val study = HealthAtlasAgingStudy.TELOMERES
        scenario.onActivity { it.view("atlas-hotspot-heart").performClick(); it.openResearch() }
        selectTopic(scenario, HealthAtlasAgingTopic.TELOMERES)
        scenario.onActivity { it.view("atlas-process-stage-1").performClick(); it.view("atlas-ask").performClick() }
        val expected = HealthAtlasAgingSelection(HealthAtlasAgingTopic.TELOMERES, 1)
        assertTrue(nodes(study.source).any { it.text?.contains(expected.publicContext(context)) == true })
        assertTrue(nodes(context.getString(android.R.string.cancel)).any { it.performAction(AccessibilityNodeInfo.ACTION_CLICK) })
        instrument.waitForIdleSync()
        scenario.onActivity { assertTrue(it.view("atlas-process-stage-1").isSelected) }
    }

    @Test fun mechanismPixelsChangeAndPublicSourceButtonsUseTheMatchingPaper() = native { scenario ->
        scenario.onActivity { activity ->
            val atlas = HealthBodyAtlas.load(activity)
            for (topic in HealthAtlasAgingTopic.entries) {
                val content = HealthCenterViews(activity).column()
                var opened = ""
                HealthAtlasAgingPanel(activity, content, atlas, atlas["heart"]!!, HealthAtlasAgingSelection(topic), {}, { opened = it })
                val diagram = requireNotNull(content.tagged("atlas-process"))
                for (width in listOf(720, 1080, 1600)) {
                    val children = diagram as ViewGroup
                    for (index in 0 until children.childCount) (children.getChildAt(index) as TextView).textSize = 23f
                    diagram.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    diagram.layout(0, 0, width, diagram.measuredHeight)
                    for (index in 0 until children.childCount) {
                        val label = children.getChildAt(index) as TextView
                        assertTrue(label.left >= 0 && label.right <= width && label.bottom <= diagram.height)
                        assertTrue(label.height >= label.layout.height + label.compoundPaddingTop + label.compoundPaddingBottom)
                    }
                    fun draw() = Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also { diagram.draw(Canvas(it)) }
                    children.getChildAt(0).performClick()
                    val before = draw()
                    children.getChildAt(3).performClick()
                    val after = draw()
                    try { assertFalse(before.sameAs(after)); assertTrue(children.getChildAt(3).isSelected) }
                    finally { before.recycle(); after.recycle() }
                }
                content.tagged("atlas-source-aging")!!.performClick()
                assertEquals(HealthAtlasResearchSources.AGING, opened)
                val study = topic.study
                val studyLink = content.tagged("atlas-source-aging-study")
                if (study == null) assertNull(studyLink) else {
                    studyLink!!.performClick(); assertEquals(study.source, opened)
                }
            }
        }
    }

    @Test fun capturesMechanismAndPublishedEvidenceOnDevice() = native { scenario ->
        fun capture(name: String, expected: String) {
            nodes(expected); SystemClock.sleep(350)
            val image = requireNotNull(instrument.uiAutomation.takeScreenshot())
            try {
                File(context.getExternalFilesDir(null), "body-atlas-aging-$name.png").outputStream().use {
                    image.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally { image.recycle() }
        }
        scenario.onActivity { it.view("atlas-hotspot-heart").performClick(); it.openResearch() }
        selectTopic(scenario, HealthAtlasAgingTopic.TELOMERES)
        capture("path", context.getString(HealthAtlasAgingTopic.TELOMERES.title))
        scenario.onActivity {
            val evidence = it.view("atlas-source-aging-study")
            evidence.requestRectangleOnScreen(Rect(0, 0, evidence.width, evidence.height), true)
        }
        capture("evidence", context.getString(HealthAtlasAgingStudy.TELOMERES.sample))
    }
}
