package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasGuidedFunctionDeviceTest {
    private val runner get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = runner.targetContext
    private fun Activity.view(key: String): View = requireNotNull(window.decorView.findViewWithTag(key)) { key }

    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        runner.uiAutomation
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(fixture)).use { scenario ->
                val deadline = SystemClock.elapsedRealtime() + 15_000L
                var ready = false
                while (!ready && SystemClock.elapsedRealtime() < deadline) {
                    scenario.onActivity { ready = it.window.decorView.findViewWithTag<View>("atlas-whole-art") != null }
                    if (!ready) SystemClock.sleep(40)
                }
                assertTrue("Atlas did not load", ready)
                block(scenario)
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun tappingTheAnimationPausesAndResumesTheSameFiveSecondChapter() = native { scenario ->
        lateinit var player: HealthAtlasFunctionPlayer
        lateinit var art: View
        lateinit var caption: TextView
        lateinit var play: View
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.view("atlas-tab-1").performClick()
            player = it.view("atlas-function-player") as HealthAtlasFunctionPlayer
            art = it.view("atlas-function-heartbeat-art")
            caption = it.view("atlas-function-caption") as TextView
            play = it.view("atlas-function-play")
        }
        runner.waitForIdleSync()
        val length = player.story.chapters.size * 5_000L
        var started = 0L
        runner.runOnMainSync {
            started = SystemClock.uptimeMillis()
            assertTrue(art.performClick())
        }
        SystemClock.sleep(1_650)
        var paused = 0f
        var chapter = -1
        runner.runOnMainSync {
            val before = SystemClock.uptimeMillis() - started
            art.performClick()
            val after = SystemClock.uptimeMillis() - started
            paused = player.phase
            chapter = player.story.chapter(paused)
            assertTrue("Paused at a different time from the actual tap: $before..$after",
                (paused * length).toLong() in (before - 80)..(after + 80))
            assertTrue(chapter < player.story.chapters.lastIndex)
            assertEquals(player.context.getString(player.story.chapters[chapter].second), caption.text.toString())
        }
        SystemClock.sleep(5_250)
        var resumed = 0L
        runner.runOnMainSync {
            assertEquals(paused, player.phase, 0f)
            assertEquals(player.context.getString(R.string.health_body_play), play.contentDescription)
            resumed = SystemClock.uptimeMillis()
            art.performClick()
        }
        val remaining = (chapter + 1) * 5_000L - (paused * length).toLong()
        SystemClock.sleep(remaining + 300)
        runner.runOnMainSync {
            val before = SystemClock.uptimeMillis() - resumed
            art.performClick()
            val after = SystemClock.uptimeMillis() - resumed
            val advanced = ((player.phase - paused) * length).toLong()
            assertTrue("Resume did not keep the partial chapter: $advanced ms for $before..$after",
                advanced in (before - 80)..(after + 80))
            val visibleChapter = player.story.chapter(player.phase)
            assertTrue(visibleChapter > chapter)
            assertEquals(player.context.getString(player.story.chapters[visibleChapter].second), caption.text.toString())
            assertSame(caption, player.findViewWithTag<View>("atlas-function-caption"))
        }
    }

    @Test fun organAndSystemExposeFullChaptersAndKeepModelsInTheSameScroll() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            fun checkEntry() {
                assertNull(it.window.decorView.findViewWithTag<View>("atlas-tab-3"))
                it.view("atlas-tab-1").performClick()
                val player = it.view("atlas-function-player") as HealthAtlasFunctionPlayer
                val page = it.view("atlas-scroll")
                assertEquals(View.GONE, it.view("atlas-function-outline").visibility)
                it.view("atlas-function-outline-toggle").performClick()
                val outline = it.view("atlas-function-outline") as ViewGroup
                assertEquals(player.story.chapters.size, outline.childCount)
                for ((index, chapter) in player.story.chapters.withIndex()) {
                    val row = it.view("atlas-function-outline-stage-$index") as ViewGroup
                    val labels = row.getChildAt(0) as ViewGroup
                    assertEquals(it.getString(chapter.second), (labels.getChildAt(1) as TextView).text.toString())
                    row.performClick()
                    assertEquals(index, player.story.chapter(player.phase))
                    assertEquals(it.getString(chapter.second), (it.view("atlas-function-caption") as TextView).text.toString())
                }
                assertEquals(View.GONE, it.view("atlas-inline-models").visibility)
                it.view("atlas-open-simulation").performClick()
                assertTrue(it.hasOpenAtlasModels())
                assertSame(page, it.view("atlas-scroll"))
                assertSame(player, it.view("atlas-function-player"))
                it.view("atlas-open-simulation").performClick()
                assertFalse(it.hasOpenAtlasModels())
                assertSame(page, it.view("atlas-scroll"))
                assertEquals(player.story.chapters.lastIndex, player.story.chapter(player.phase))
                it.view("atlas-open-research").performClick()
                assertTrue(it.view("atlas-research-tab-drugs").isSelected)
                assertNotNull(it.view("atlas-research-tab-aging"))
                assertNull(it.window.decorView.findViewWithTag<View>("atlas-research-tab-physiology"))
                it.onBackPressed()
                assertTrue(it.view("atlas-tab-1").isSelected)
                val restored = it.view("atlas-function-player") as HealthAtlasFunctionPlayer
                assertEquals(player.phase, restored.phase, 0f)
                assertFalse(it.hasOpenAtlasModels())
            }
            checkEntry()
            it.onBackPressed()
            it.view("atlas-tab-1").performClick()
            it.view("atlas-entry-cardio").performClick()
            checkEntry()
        }
    }

    @Test fun everySystemAndOrganHasACompleteLocalizedCaptionSequence() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val targets = atlas.items.filter { it.kind == HealthAtlasKind.SYSTEM || it.kind == HealthAtlasKind.ORGAN }
            assertTrue(targets.size > 180)
            for (item in targets) {
                val choices = HealthAtlasFunctionStory.choicesForId(item.id)
                assertTrue(item.id, choices.isNotEmpty())
                for (story in choices) {
                    assertTrue(story.name, story.chapters.size >= 3)
                    for ((title, detail) in story.chapters) {
                        assertTrue(story.name, localized.getString(title).isNotBlank())
                        assertTrue(story.name, localized.getString(detail).trim().length > 8)
                    }
                }
            }
        }
    }

    @Test fun returningFromResearchKeepsTheFunctionScrollAndExpandedModel() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.openAtlasModelDetails()
        }
        runner.waitForIdleSync()
        var originalScroll = 0
        scenario.onActivity {
            val scroll = it.view("atlas-scroll") as ScrollView
            originalScroll = scroll.scrollY
            assertTrue("The inline model must be below the function lesson", originalScroll > 0)
            it.view("atlas-open-research").performClick()
            it.view("atlas-research-tab-aging").performClick()
            it.onBackPressed()
        }
        runner.waitForIdleSync()
        scenario.onActivity {
            assertTrue(it.hasOpenAtlasModels())
            assertEquals(originalScroll, (it.view("atlas-scroll") as ScrollView).scrollY)
        }
    }

    @Test fun capturesAnAnimationAndItsPrincipleTogether() = native { scenario ->
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-heart").performClick()
            activity.view("atlas-tab-1").performClick()
            repeat(3) { activity.view("atlas-function-next").performClick() }
        }
        runner.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5_000
        while (runner.uiAutomation.rootInActiveWindow?.packageName?.toString() != context.packageName &&
            SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(40)
        assertEquals(context.packageName, runner.uiAutomation.rootInActiveWindow?.packageName?.toString())
        val bitmap = requireNotNull(runner.uiAutomation.takeScreenshot())
        try {
            java.io.File(context.getExternalFilesDir(null), "body-atlas-guided-heart.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { bitmap.recycle() }
    }
}
