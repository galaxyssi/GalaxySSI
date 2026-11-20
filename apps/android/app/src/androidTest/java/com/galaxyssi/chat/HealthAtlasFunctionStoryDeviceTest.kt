package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.widget.EditText
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasFunctionStoryDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun bothLessonsAnimateWithinEveryChapterAtPhoneAndTabletWidths() {
        instrumentation.runOnMainSync {
            for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
                val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
                for (story in HealthAtlasFunctionStory.entries) {
                    val art = story.createArt(localized)
                    for (size in listOf(480, 1080, 1600)) {
                        art.measure(View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                        art.layout(0, 0, size, art.measuredHeight)
                        fun render(phase: Float): Bitmap {
                            art.phase = phase
                            return Bitmap.createBitmap(size, art.height, Bitmap.Config.ARGB_8888).also { art.draw(Canvas(it)) }
                        }
                        val first = render(0f)
                        try {
                            assertTrue(Color.alpha(first.getPixel(size / 2, first.height / 2)) > 200)
                            story.chapters.forEachIndexed { index, (_, caption) ->
                                val start = story.startOf(index)
                                val early = render(start + .05f)
                                val late = render(start + .13f)
                                try {
                                    assertFalse("$story chapter ${index + 1} at $size did not move", early.sameAs(late))
                                    assertEquals(localized.getString(caption), art.contentDescription)
                                } finally { early.recycle(); late.recycle() }
                            }
                            val rewind = render(0f)
                            try { assertTrue(first.sameAs(rewind)) } finally { rewind.recycle() }
                        } finally { first.recycle() }
                    }
                }
            }
        }
    }

    @Test fun heartAndValveKeepIndependentPositionsAndLeaveMeasurementsUntouched() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    activity.find<View>("atlas-hotspot-heart").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    activity.find<HealthAtlasHeartbeatView>("atlas-function-heartbeat-art")
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    val text = activity.find<TextView>("atlas-function-caption").text
                    assertEquals(activity.getString(R.string.health_atlas_beat_eject_caption), text)
                    activity.find<View>("atlas-tab-2").performClick()
                    assertNull(activity.window.decorView.findViewWithTag<View>("atlas-function-player"))
                    activity.find<View>("atlas-tab-0").performClick()
                    activity.find<View>("atlas-entry-heart-valves").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    activity.find<View>("atlas-function-next").performClick()
                    activity.onBackPressed()
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.6f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun functionPlayerRestoresPausedWithoutChangingTheSimulationOrBetaCell() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    openCell(activity, "cell-adipocyte")
                    val player = activity.find<HealthAtlasFunctionPlayer>("atlas-function-player")
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(.6f, player.phase, .001f)
                    assertEquals(activity.getString(R.string.health_atlas_uptake_fuse_caption), activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-function-play").performClick()
                }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.moveToState(Lifecycle.State.RESUMED)
                var saved = 0f
                scenario.onActivity { activity ->
                    assertEquals(activity.getString(R.string.health_body_play), activity.find<View>("atlas-function-play").contentDescription)
                    saved = activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase
                }
                scenario.recreate()
                waitFor(scenario, "atlas-function-player")
                scenario.onActivity { activity ->
                    assertEquals(saved, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, .001f)
                    activity.find<View>("atlas-tab-3").performClick()
                    assertNull(activity.window.decorView.findViewWithTag<View>("atlas-function-player"))
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(saved, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, .001f)
                    activity.onBackPressed()
                    openCell(activity, "cell-pancreatic-beta-cell")
                    assertNull(activity.window.decorView.findViewWithTag<View>("atlas-function-player"))
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun agentContextOnlyReceivesTheActivePublicChapter() {
        val atlas = HealthBodyAtlas.load(context)
        val adipocyte = requireNotNull(atlas["cell-adipocyte"])
        val beta = requireNotNull(atlas["cell-pancreatic-beta-cell"])
        val heart = requireNotNull(atlas["heart"])
        val glucoseSource = HealthAtlasFunctionStory.GLUCOSE.references.first().second
        val prompt = HealthAtlasAgentContext.prompt(context, atlas, adipocyte, functionPhase = .91f)
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_uptake_transport_caption)))
        assertTrue(prompt.contains(glucoseSource))
        assertFalse(prompt.contains(context.getString(R.string.health_atlas_uptake_bind_caption)))
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, beta, functionPhase = .91f).contains(glucoseSource))
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, adipocyte, topic = HealthAtlasResearchTopic.DRUGS,
            functionPhase = .91f).contains(glucoseSource))
        val beat = HealthAtlasAgentContext.prompt(context, atlas, heart, functionPhase = .67f)
        assertTrue(beat.contains(context.getString(R.string.health_atlas_beat_eject_caption)))
        assertFalse(beat.contains(context.getString(R.string.health_atlas_beat_fill_caption)))
        assertFalse(beat.contains(glucoseSource))
    }

    private fun openCell(activity: HealthBodyAtlasActivity, id: String) {
        activity.find<View>("atlas-tab-3").performClick()
        activity.find<EditText>("atlas-search").setText(id)
        activity.find<View>("atlas-entry-$id").performClick()
        activity.find<View>("atlas-tab-1").performClick()
    }

    private fun <T : View> HealthBodyAtlasActivity.find(tag: String): T =
        requireNotNull(window.decorView.findViewWithTag<T>(tag)) { tag }

    private fun waitFor(scenario: ActivityScenario<HealthBodyAtlasActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000L
        do {
            var ready = false
            scenario.onActivity { ready = it.window.decorView.findViewWithTag<View>(tag) != null }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail(tag)
    }
}
