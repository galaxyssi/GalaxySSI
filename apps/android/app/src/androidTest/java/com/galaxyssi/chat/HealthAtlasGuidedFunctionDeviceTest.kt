package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
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
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.view("atlas-tab-1").performClick()
            player = it.view("atlas-function-player") as HealthAtlasFunctionPlayer
            art = it.view("atlas-function-heartbeat-art")
            caption = it.view("atlas-function-caption") as TextView
            art.performClick()
        }
        SystemClock.sleep(2_000)
        var paused = 0f
        scenario.onActivity {
            art.performClick()
            paused = player.phase
            assertTrue(paused > 0f)
            assertEquals(0, player.story.chapter(paused))
            assertEquals(it.getString(player.story.chapters[0].second), caption.text.toString())
        }
        SystemClock.sleep(5_250)
        scenario.onActivity {
            assertEquals(paused, player.phase, 0f)
            assertEquals(it.getString(R.string.health_body_play), it.view("atlas-function-play").contentDescription)
            art.performClick()
        }
        val remaining = 5_000L - (paused * player.story.chapters.size * 5_000L).toLong()
        SystemClock.sleep((remaining - 600).coerceAtLeast(0))
        scenario.onActivity { assertEquals(0, player.story.chapter(player.phase)) }
        SystemClock.sleep(950)
        scenario.onActivity {
            assertEquals(1, player.story.chapter(player.phase))
            assertEquals(it.getString(player.story.chapters[1].second), caption.text.toString())
            assertSame(caption, it.view("atlas-function-caption"))
            art.performClick()
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
