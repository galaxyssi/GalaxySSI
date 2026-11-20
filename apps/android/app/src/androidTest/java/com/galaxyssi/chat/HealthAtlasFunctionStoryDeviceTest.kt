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

    @Test fun fiveChaptersShowMovingStructureAndCanRewindAtPhoneAndTabletWidths() {
        instrumentation.runOnMainSync {
            for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
                val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
                val art = HealthAtlasUptakeView(localized)
                for (size in listOf(480, 1080, 1600)) {
                    art.measure(View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    art.layout(0, 0, size, art.measuredHeight)
                    fun render(phase: Float): Bitmap {
                        art.phase = phase
                        return Bitmap.createBitmap(size, art.height, Bitmap.Config.ARGB_8888).also { art.draw(Canvas(it)) }
                    }
                    val first = render(0f)
                    var previous = first
                    try {
                        assertTrue(Color.alpha(first.getPixel(size / 2, first.height / 2)) > 200)
                        HealthAtlasFunctionStory.chapters.forEachIndexed { index, (_, caption) ->
                            val next = render(HealthAtlasFunctionStory.startOf(index) + .1f)
                            val changed = !previous.sameAs(next)
                            if (previous !== first) previous.recycle()
                            previous = next
                            assertTrue("Scene ${index + 1} at $size did not move", changed)
                            assertEquals(localized.getString(caption), art.contentDescription)
                        }
                        val rewind = render(0f)
                        try { assertTrue(first.sameAs(rewind)) } finally { rewind.recycle() }
                    } finally { first.recycle(); previous.recycle() }
                }
            }
        }
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
        val prompt = HealthAtlasAgentContext.prompt(context, atlas, adipocyte, functionPhase = .91f)
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_uptake_transport_caption)))
        assertTrue(prompt.contains(HealthAtlasFunctionStory.SOURCE))
        assertFalse(prompt.contains(context.getString(R.string.health_atlas_uptake_bind_caption)))
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, beta, functionPhase = .91f).contains(HealthAtlasFunctionStory.SOURCE))
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, adipocyte, topic = HealthAtlasResearchTopic.DRUGS,
            functionPhase = .91f).contains(HealthAtlasFunctionStory.SOURCE))
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
