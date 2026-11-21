package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
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

    @Test fun allLessonsAnimateWithinEveryChapterAtPhoneAndTabletWidths() {
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

    @Test fun lymphAndAntibodyStoriesRetainTheDedicatedAnatomyAndSimulations() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    activity.find<View>("atlas-tab-2").performClick()
                    activity.find<EditText>("atlas-search").setText("lymphatic-vessels")
                    activity.find<View>("atlas-entry-lymphatic-vessels").performClick()
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<android.widget.SeekBar>("atlas-physiology-lymph-pressure").progress = 70
                    activity.find<View>("atlas-tab-1").performClick()
                    activity.find<View>("atlas-function-lymph-return-art")
                    activity.find<View>("atlas-feature-vessel-0")
                    repeat(2) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_lymph_flow_pump_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    assertEquals(70, activity.find<android.widget.SeekBar>("atlas-physiology-lymph-pressure").progress)
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.4f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    activity.onBackPressed()

                    openCell(activity, "cell-plasma-cell")
                    activity.find<View>("atlas-function-antibody-response-art")
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    repeat(4) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_antibody_story_release_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<View>("atlas-immune-link-diagram")
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.8f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun elbowMotionAndBoneRemodelingKeepIndependentPlaybackAndSimulation() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        fun openBiceps(activity: HealthBodyAtlasActivity) {
            activity.find<View>("atlas-tab-2").performClick()
            activity.find<EditText>("atlas-search").setText("biceps-brachii")
            activity.find<View>("atlas-entry-biceps-brachii").performClick()
        }
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    openBiceps(activity)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<HealthAtlasElbowView>("atlas-elbow-balance")
                    activity.find<android.widget.SeekBar>("atlas-physiology-elbow-load").progress = 71
                    activity.find<View>("atlas-tab-1").performClick()
                    activity.find<View>("atlas-function-muscle-motion-art")
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_motion_pull_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    assertEquals(71, activity.find<android.widget.SeekBar>("atlas-physiology-elbow-load").progress)
                    activity.onBackPressed()
                    openCell(activity, "cell-osteoclast")
                    activity.find<View>("atlas-function-bone-remodeling-art")
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_bone_fill_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.onBackPressed()
                    openBiceps(activity)
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.6f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun opticsSimulationAndDarkAdaptationDoNotShareTheVisionPlayhead() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        fun openEye(activity: HealthBodyAtlasActivity) {
            activity.find<View>("atlas-tab-2").performClick()
            activity.find<EditText>("atlas-search").setText("eye")
            activity.find<View>("atlas-entry-eye").performClick()
            activity.find<View>("atlas-tab-1").performClick()
        }
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    openEye(activity)
                    activity.find<View>("atlas-function-vision-art")
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_vision_story_relay_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<View>("atlas-eye-optics")
                    activity.onBackPressed()
                    openCell(activity, "cell-rod-photoreceptor")
                    activity.find<View>("atlas-function-light-adaptation-art")
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    activity.find<View>("atlas-function-next").performClick()
                    assertEquals(activity.getString(R.string.health_atlas_vision_story_rod_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.onBackPressed()
                    openEye(activity)
                    assertEquals(.6f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun mealAndColonKeepIndependentProgressAndVillusSimulation() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        fun open(activity: HealthBodyAtlasActivity, id: String) {
            activity.find<View>("atlas-tab-2").performClick()
            activity.find<EditText>("atlas-search").setText(id)
            activity.find<View>("atlas-entry-$id").performClick()
            activity.find<View>("atlas-tab-1").performClick()
        }
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    open(activity, "jejunum")
                    activity.find<HealthAtlasDigestiveStoryView>("atlas-function-meal-art")
                    repeat(4) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_meal_villus_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<View>("atlas-villus-geometry")
                    activity.onBackPressed()
                    open(activity, "colon")
                    activity.find<HealthAtlasDigestiveStoryView>("atlas-function-colon-art")
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    repeat(2) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_colon_story_water_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.onBackPressed()
                    open(activity, "jejunum")
                    assertEquals(.8f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun nephronOpensWithPlaybackControlsVisibleBeforeTheArtwork() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    activity.find<View>("atlas-tab-2").performClick()
                    activity.find<EditText>("atlas-search").setText("kidneys")
                    activity.find<View>("atlas-entry-kidneys").performClick()
                    activity.find<View>("atlas-entry-nephron").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val art = activity.find<View>("atlas-function-nephron-art")
                    val play = activity.find<View>("atlas-function-play")
                    val seeker = activity.find<View>("atlas-function-position")
                    val visible = Rect()
                    assertTrue(play.getGlobalVisibleRect(visible))
                    assertEquals(play.height, visible.height())
                    assertTrue(seeker.getGlobalVisibleRect(visible))
                    assertEquals(seeker.height, visible.height())
                    assertTrue(seeker.bottom < art.top)
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_nephron_story_distal_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<View>("atlas-physiology-reabsorbed")
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.6f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun hearingAndBalanceOpenDifferentFunctionsAndTheMiddleEarSimulationStillWorks() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    activity.find<View>("atlas-tab-2").performClick()
                    activity.find<EditText>("atlas-search").setText("ear")
                    activity.find<View>("atlas-entry-ear").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    activity.find<HealthAtlasHearingStoryView>("atlas-function-hearing-art")
                    repeat(4) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_hear_nerve_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<View>("atlas-middle-ear-model")
                    activity.find<View>("atlas-tab-0").performClick()
                    activity.find<View>("atlas-hotspot-vestibular-apparatus").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    assertNull(activity.window.decorView.findViewWithTag<View>("atlas-function-player"))
                    activity.onBackPressed()
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.8f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun lungAndAlveolusOpenTheLessonWithoutChangingTheExistingGasSimulation() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    activity.find<View>("atlas-hotspot-lungs").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    activity.find<HealthAtlasBreathingView>("atlas-function-breathing-art")
                    activity.find<View>("atlas-function-next").performClick()
                    activity.find<View>("atlas-tab-0").performClick()
                    activity.find<View>("atlas-entry-alveoli").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    repeat(2) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_breathe_diffuse_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                    activity.find<View>("atlas-tab-3").performClick()
                    activity.find<View>("atlas-gas-arrow-OXYGEN")
                    activity.find<View>("atlas-gas-arrow-CARBON_DIOXIDE")
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.4f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    activity.onBackPressed()
                    activity.find<View>("atlas-tab-1").performClick()
                    assertEquals(.2f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
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

    @Test fun uptakeRestoresPausedAndDoesNotReplaceTheBetaCellLesson() {
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
                    activity.find<View>("atlas-function-insulin-secretion-art")
                    assertNull(activity.window.decorView.findViewWithTag<View>("atlas-function-uptake-art"))
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun twoLessonsSwitchInPlaceAndKeepTheirOwnProgressAfterRecreationAndRelatedNavigation() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { scenario ->
                waitFor(scenario, "atlas-whole-art")
                scenario.onActivity { activity ->
                    activity.find<View>("atlas-tab-2").performClick()
                    activity.find<EditText>("atlas-search").setText("pancreas")
                    activity.find<View>("atlas-entry-pancreas").performClick()
                    activity.find<View>("atlas-tab-1").performClick()
                    val scroller = activity.find<View>("atlas-scroll")
                    assertEquals(HealthAtlasFunctionStory.DIGESTION,
                        activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").story)
                    activity.find<View>("atlas-function-next").performClick()
                    activity.find<View>("atlas-function-lesson-1").performClick()
                    assertSame(scroller, activity.find<View>("atlas-scroll"))
                    activity.find<View>("atlas-function-insulin-secretion-art")
                    assertEquals(0f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    repeat(3) { activity.find<View>("atlas-function-next").performClick() }
                    assertEquals(activity.getString(R.string.health_atlas_insulin_story_fusion_caption),
                        activity.find<TextView>("atlas-function-caption").text)
                }
                scenario.recreate()
                waitFor(scenario, "atlas-function-insulin-secretion-art")
                scenario.onActivity { activity ->
                    assertEquals(.6f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    activity.find<View>("atlas-function-lesson-0").performClick()
                    assertEquals(.2f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                    activity.find<View>("atlas-function-lesson-1").performClick()
                    activity.find<View>("atlas-related-lesson-tissue-skeletal-muscle").performClick()
                    activity.find<View>("atlas-function-uptake-art")
                    activity.find<View>("atlas-function-lesson-1").performClick()
                    activity.find<View>("atlas-function-muscle-motion-art")
                    activity.onBackPressed()
                    assertEquals(HealthAtlasFunctionStory.INSULIN_SECRETION,
                        activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").story)
                    assertEquals(.6f, activity.find<HealthAtlasFunctionPlayer>("atlas-function-player").phase, 0f)
                }
            }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun legacyPlayheadIsRestoredOnlyIntoTheDefaultLesson() {
        val old = android.os.Bundle().apply { putFloat("pancreas", .44f) }
        val first = HealthAtlasFunctionState().apply { restore(null, old) }
        val digestive = HealthAtlasFunctionStory.DIGESTION
        val insulin = HealthAtlasFunctionStory.INSULIN_SECRETION
        assertEquals(.44f, first.loadPhase("pancreas", digestive), 0f)
        assertEquals(0f, first.loadPhase("pancreas", insulin), 0f)
        first.choose("pancreas", insulin)
        first.savePhase("pancreas", insulin, .8f)
        val restored = HealthAtlasFunctionState().apply { restore(first.snapshot(), null) }
        assertEquals(insulin, restored.current("pancreas"))
        assertEquals(.44f, restored.loadPhase("pancreas", digestive), 0f)
        assertEquals(.8f, restored.loadPhase("pancreas", insulin), 0f)
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
        val pancreas = requireNotNull(atlas["pancreas"])
        val secretion = HealthAtlasAgentContext.prompt(context, atlas, pancreas, functionPhase = .64f,
            functionStory = HealthAtlasFunctionStory.INSULIN_SECRETION)
        assertTrue(secretion.contains(context.getString(R.string.health_atlas_insulin_story_fusion_caption)))
        assertFalse(secretion.contains(context.getString(R.string.health_atlas_meal_duodenum_caption)))
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, beta, functionPhase = .91f,
            functionStory = HealthAtlasFunctionStory.GLUCOSE).contains(glucoseSource))
        assertFalse(HealthAtlasAgentContext.prompt(context, atlas, adipocyte, topic = HealthAtlasResearchTopic.DRUGS,
            functionPhase = .91f).contains(glucoseSource))
        val beat = HealthAtlasAgentContext.prompt(context, atlas, heart, functionPhase = .67f)
        assertTrue(beat.contains(context.getString(R.string.health_atlas_beat_eject_caption)))
        assertFalse(beat.contains(context.getString(R.string.health_atlas_beat_fill_caption)))
        assertFalse(beat.contains(glucoseSource))
        val alveoli = requireNotNull(atlas["alveoli"])
        val breathing = HealthAtlasAgentContext.prompt(context, atlas, alveoli, functionPhase = .47f)
        assertTrue(breathing.contains(context.getString(R.string.health_atlas_breathe_diffuse_caption)))
        assertFalse(breathing.contains(context.getString(R.string.health_atlas_breathe_exhale_caption)))
        assertFalse(breathing.contains(context.getString(R.string.health_atlas_beat_eject_caption)))
        val hairCell = requireNotNull(atlas["cell-inner-ear-hair-cell"])
        val hearing = HealthAtlasAgentContext.prompt(context, atlas, hairCell, functionPhase = .65f)
        assertTrue(hearing.contains(context.getString(R.string.health_atlas_hear_hair_caption)))
        assertFalse(hearing.contains(context.getString(R.string.health_atlas_hear_nerve_caption)))
        assertFalse(hearing.contains(context.getString(R.string.health_atlas_breathe_diffuse_caption)))
        val nephron = requireNotNull(atlas["nephron"])
        val renal = HealthAtlasAgentContext.prompt(context, atlas, nephron, functionPhase = .31f)
        assertTrue(renal.contains(context.getString(R.string.health_atlas_nephron_story_prox_caption)))
        assertFalse(renal.contains(context.getString(R.string.health_atlas_nephron_story_distal_caption)))
        assertFalse(renal.contains(context.getString(R.string.health_atlas_hear_hair_caption)))
        val meal = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["jejunum"]), functionPhase = .85f)
        val colon = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["colon"]), functionPhase = .44f)
        assertTrue(meal.contains(context.getString(R.string.health_atlas_meal_villus_caption)))
        assertFalse(colon.contains(context.getString(R.string.health_atlas_meal_villus_caption)))
        assertTrue(colon.contains(context.getString(R.string.health_atlas_colon_story_water_caption)))
        assertFalse(meal.contains(context.getString(R.string.health_atlas_colon_story_water_caption)))
        val vision = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["eye"]), functionPhase = .46f)
        val adaptation = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["cell-rod-photoreceptor"]),
            functionPhase = .25f)
        assertTrue(vision.contains(context.getString(R.string.health_atlas_vision_story_capture_caption)))
        assertTrue(adaptation.contains(context.getString(R.string.health_atlas_vision_story_rod_caption)))
        assertFalse(adaptation.contains(context.getString(R.string.health_atlas_vision_story_capture_caption)))
        val motion = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["biceps-brachii"]), functionPhase = .66f)
        val bone = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["cell-osteoclast"]), functionPhase = .29f)
        assertTrue(motion.contains(context.getString(R.string.health_atlas_motion_pull_caption)))
        assertTrue(bone.contains(context.getString(R.string.health_atlas_bone_remove_caption)))
        assertFalse(bone.contains(context.getString(R.string.health_atlas_motion_pull_caption)))
        val lymph = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["lymph-nodes"]), functionPhase = .63f)
        val antibody = HealthAtlasAgentContext.prompt(context, atlas, requireNotNull(atlas["cell-plasma-cell"]), functionPhase = .84f)
        assertTrue(lymph.contains(context.getString(R.string.health_atlas_lymph_flow_node_caption)))
        assertTrue(antibody.contains(context.getString(R.string.health_atlas_antibody_story_release_caption)))
        assertFalse(antibody.contains(context.getString(R.string.health_atlas_lymph_flow_node_caption)))
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
