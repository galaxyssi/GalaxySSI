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
import android.widget.EditText
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
        var startPhase = 0f
        var started = 0L
        runner.runOnMainSync {
            assertTrue("The animation must be displayed before playing", art.isAttachedToWindow)
            startPhase = player.phase
            started = SystemClock.uptimeMillis()
            assertTrue(art.performClick())
            assertEquals(player.context.getString(R.string.health_body_pause), play.contentDescription)
        }
        scenario.onActivity {
            it.view("atlas-tab-1").performClick()
            assertSame("Retapping Function must not replace the running player", player, it.view("atlas-function-player"))
        }
        SystemClock.sleep(1_650)
        var paused = 0f
        var chapter = -1
        runner.runOnMainSync {
            assertTrue("The animation window was detached during the test", art.isAttachedToWindow)
            assertEquals("The player stopped before the pause tap",
                player.context.getString(R.string.health_body_pause), play.contentDescription)
            val before = SystemClock.uptimeMillis() - started
            assertTrue(art.performClick())
            val after = SystemClock.uptimeMillis() - started
            paused = player.phase
            chapter = player.story.chapter(paused)
            val elapsed = ((paused - startPhase) * length).toLong()
            assertTrue("Paused after $elapsed ms; the tap was at $before..$after ms",
                elapsed in (before - 80)..(after + 80))
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
                val frame = it.view("atlas-function-frame")
                val caption = it.view("atlas-function-caption") as TextView
                assertSame(frame, caption.parent.parent)
                assertNotNull(it.view("atlas-function-menu"))
                assertNull(it.window.decorView.findViewWithTag<View>("atlas-function-outline"))
                for ((index, chapter) in player.story.chapters.withIndex()) {
                    if (index > 0) it.view("atlas-function-next").performClick()
                    assertEquals(index, player.story.chapter(player.phase))
                    assertEquals(it.getString(chapter.second), caption.text.toString())
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

    @Test fun everyEntryHasACompleteLocalizedCaptionSequence() {
        for (locale in listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val targets = atlas.items
            assertTrue(targets.size > 300)
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

    @Test fun inlineModelKeepsTheChangingCaptionWithTheArtworkAndCollapsesReferences() = native { scenario ->
        scenario.onActivity {
            it.view("atlas-hotspot-heart").performClick()
            it.view("atlas-tab-1").performClick()
            it.view("atlas-open-simulation").performClick()
        }
        runner.waitForIdleSync()
        val sceneHeight = intArrayOf(0)
        scenario.onActivity { activity ->
            val frame = activity.view("atlas-simulation-frame")
            val caption = activity.view("atlas-simulation-stage") as TextView
            val references = activity.view("atlas-simulation-references")
            val diagram = activity.view("atlas-process")
            val figure = activity.view("atlas-simulation-figure")
            val legend = caption.parent as View
            assertSame(frame, figure.parent)
            assertSame(figure, legend.parent)
            assertSame(figure, diagram.parent)
            assertTrue(legend.top < diagram.bottom)
            val layout = figure as android.view.ViewGroup
            for (index in 0..3) {
                val button = activity.view("atlas-process-stage-$index")
                val bounds = Rect(0, 0, button.width, button.height)
                layout.offsetDescendantRectToMyCoords(button, bounds)
                assertFalse("Note covers stage $index", Rect.intersects(bounds,
                    Rect(legend.left, legend.top, legend.right, legend.bottom)))
            }
            assertEquals(View.GONE, references.visibility)
            assertSame(references, activity.view("atlas-source-physiology").parent)
            assertSame(references, activity.view("atlas-source-circulation").parent)
            sceneHeight[0] = frame.height
            val prior = caption.text
            activity.view("atlas-process-stage-2").performClick()
            val atlas = HealthBodyAtlas.load(activity)
            assertNotEquals(prior.toString(), caption.text.toString())
            assertTrue(caption.text.contains(atlas.mechanism(requireNotNull(atlas["heart"])).stages[2]))
        }
        runner.waitForIdleSync()
        scenario.onActivity { activity ->
            assertEquals(sceneHeight[0], activity.view("atlas-simulation-frame").height)
            val toggle = activity.view("atlas-simulation-references-toggle")
            toggle.performClick()
            assertEquals(View.VISIBLE, activity.view("atlas-simulation-references").visibility)
            toggle.performClick()
            assertEquals(View.GONE, activity.view("atlas-simulation-references").visibility)
        }
    }

    @Test fun synapticScenesRenderDifferentMechanismsAndKeepTheirCaptionsInsideTheFrame() = native { scenario ->
        scenario.onActivity { activity ->
            activity.view("atlas-tab-2").performClick()
            (activity.view("atlas-search") as EditText).setText("brain")
            activity.view("atlas-entry-brain").performClick()
            activity.view("atlas-tab-1").performClick()
        }
        runner.waitForIdleSync()
        scenario.onActivity { activity ->
            val player = activity.view("atlas-function-player") as HealthAtlasFunctionPlayer
            assertEquals(HealthAtlasFunctionStory.SYNAPTIC_SIGNAL, player.story)
            val frame = activity.view("atlas-function-frame")
            val art = activity.view("atlas-function-synaptic-signal-art") as HealthAtlasFunctionArt
            val subtitle = activity.view("atlas-function-subtitles")
            val caption = activity.view("atlas-function-caption") as TextView
            assertSame(frame, art.parent)
            assertSame(frame, subtitle.parent)
            assertTrue(subtitle.top < art.bottom)
            assertTrue(subtitle.bottom < art.bottom)
            assertTrue(subtitle.right <= frame.width)
            assertTrue("Missing animation artwork", art.width > 0 && art.height > 0)
            val size = Rect(0, 0, frame.width, frame.height)
            val hashes = mutableSetOf<Int>()
            val bitmap = Bitmap.createBitmap(size.width(), size.height(), Bitmap.Config.ARGB_8888)
            try {
                for (index in player.story.chapters.indices) {
                    if (index > 0) activity.view("atlas-function-next").performClick()
                    assertEquals(activity.getString(player.story.chapters[index].second), caption.text.toString())
                    val chapter = index.toFloat()
                    art.phase = (chapter + .56f) / player.story.chapters.size
                    bitmap.eraseColor(0)
                    frame.draw(Canvas(bitmap))
                    val point = (frame as HealthAtlasFigureFrame).annotationTarget!!
                    assertEquals(activity.getColor(R.color.health_overview_green),
                        bitmap.getPixel(point.x.toInt(), point.y.toInt()))
                    val pixels = IntArray(art.width * art.height)
                    bitmap.getPixels(pixels, 0, art.width, art.left, art.top, art.width, art.height)
                    hashes += pixels.contentHashCode()
                    java.io.File(context.getExternalFilesDir(null), "body-atlas-brain-scene-${index + 1}.png")
                        .outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                }
            } finally {
                bitmap.recycle()
            }
            assertEquals(player.story.chapters.size, hashes.size)
            assertNull(activity.window.decorView.findViewWithTag<View>("atlas-function-principle"))
        }
    }

    @Test fun captionAtNarrowWidthHasRoomForEveryLongChapterWithoutCoveringTheDrawing() = native { scenario ->
        scenario.onActivity { activity ->
            val story = HealthAtlasFunctionStory.VISION
            val player = HealthAtlasFunctionPlayer(activity, story, 0f, {})
            val caption = player.findViewWithTag<TextView>("atlas-function-caption")
            caption.textSize = 26f
            val width = (320f * activity.resources.displayMetrics.density).toInt()
            val art = player.findViewWithTag<View>("atlas-function-vision-art")
            val subtitle = player.findViewWithTag<View>("atlas-function-subtitles")
            val frame = player.findViewWithTag<View>("atlas-function-frame")
            var expectedHeight = 0
            repeat(story.chapters.size) { chapter ->
                if (chapter != 0) player.findViewWithTag<View>("atlas-function-next").performClick()
                player.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                player.layout(0, 0, width, player.measuredHeight)
                assertTrue(subtitle.top < art.bottom)
                assertTrue(subtitle.bottom < frame.height)
                assertTrue("The note must be drawn partly over the image on a phone", subtitle.bottom > art.top)
                assertTrue(caption.layout.height + caption.totalPaddingTop + caption.totalPaddingBottom <= caption.height)
                if (chapter == 0) expectedHeight = frame.height else assertEquals(expectedHeight, frame.height)
            }
        }
    }

    @Test fun tappingTheInImageNoteShowsItsFullCaptionWithoutLosingTheCurrentChapter() = native { scenario ->
        lateinit var expected: String
        var phase = 0f
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-heart").performClick()
            activity.view("atlas-tab-1").performClick()
            repeat(3) { activity.view("atlas-function-next").performClick() }
        }
        runner.waitForIdleSync()
        scenario.onActivity { activity ->
            val player = activity.view("atlas-function-player") as HealthAtlasFunctionPlayer
            val art = activity.view("atlas-function-heartbeat-art")
            val note = activity.view("atlas-function-subtitles")
            phase = player.phase
            expected = (activity.view("atlas-function-caption") as TextView).text.toString()
            val visible = Rect()
            val play = activity.view("atlas-function-play")
            assertTrue(play.getGlobalVisibleRect(visible))
            assertEquals(play.height, visible.height())
            if (activity.resources.configuration.screenWidthDp < 580) {
                assertTrue(Rect.intersects(Rect(art.left, art.top, art.right, art.bottom),
                    Rect(note.left, note.top, note.right, note.bottom)))
            }
            assertTrue(note.performClick())
        }
        runner.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5000
        fun fullCopyShown() = runner.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(expected)
            ?.any { it.isVisibleToUser && it.viewIdResourceName == "android:id/message" } == true
        while (!fullCopyShown() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(40)
        assertTrue("The note did not show the full caption in the dialog", fullCopyShown())
        runner.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        runner.waitForIdleSync()
        scenario.onActivity {
            assertEquals(phase, (it.view("atlas-function-player") as HealthAtlasFunctionPlayer).phase, 0f)
        }
    }

    @Test fun breathingShowsAMovingBarrierCloseUpWithTheSameCaptionClock() = native { scenario ->
        scenario.onActivity { activity ->
            activity.view("atlas-tab-2").performClick()
            (activity.view("atlas-search") as EditText).setText("lungs")
            activity.view("atlas-entry-lungs").performClick()
            activity.view("atlas-tab-1").performClick()
            repeat(2) { activity.view("atlas-function-next").performClick() }
        }
        runner.waitForIdleSync()
        scenario.onActivity { activity ->
            val frame = activity.view("atlas-function-frame")
            val art = activity.view("atlas-function-breathing-art") as HealthAtlasFunctionArt
            val caption = activity.view("atlas-function-caption") as TextView
            assertEquals(activity.getString(R.string.health_atlas_breathe_diffuse_caption), caption.text.toString())
            assertSame(frame, caption.parent.parent)
            val bitmap = Bitmap.createBitmap(frame.width, frame.height, Bitmap.Config.ARGB_8888)
            try {
                fun artHash(position: Float): Int {
                    art.phase = position
                    bitmap.eraseColor(0)
                    frame.draw(Canvas(bitmap))
                    val pixels = IntArray(art.width * art.height)
                    bitmap.getPixels(pixels, 0, art.width, art.left, art.top, art.width, art.height)
                    return pixels.contentHashCode()
                }
                assertNotEquals(artHash(.42f), artHash(.52f))
                java.io.File(context.getExternalFilesDir(null), "body-atlas-lung-barrier.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally { bitmap.recycle() }
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

    private data class CloseUp(
        val id: String,
        val art: String,
        val chapter: Int,
        val region: Rect,
        val file: String,
        val lesson: Int = 0,
        val late: Float = .42f,
    )

    @Test fun heartEarAndNephronRenderMovingCloseUpsAlongsideTheirCaptions() = verifyCloseUps(
        CloseUp("heart", "heartbeat", 2, Rect(5, 72, 95, 97), "heart-pressure"),
        CloseUp("ear", "hearing", 3, Rect(46, 8, 96, 88), "ear-tip-link"),
        CloseUp("nephron", "nephron", 0, Rect(3, 53, 97, 97), "nephron-filter"),
        CloseUp("nephron", "nephron", 2, Rect(3, 53, 97, 97), "nephron-loop"),
    )

    @Test fun movementAbsorptionAndSecretionRenderMovingCloseUpsAlongsideTheirCaptions() = verifyCloseUps(
        CloseUp("biceps-brachii", "muscle-motion", 2, Rect(10, 73, 64, 90), "muscle-cross-bridge"),
        CloseUp("small-intestine", "intestinal-absorption", 2, Rect(58, 25, 96, 72), "glucose-transport", lesson = 1),
        CloseUp("pancreas", "insulin-secretion", 1, Rect(10, 85, 92, 96), "beta-cell-voltage", lesson = 1),
    )

    @Test fun rodMembraneChangesFromDarkCurrentToClosedChannels() = verifyCloseUps(
        CloseUp("eye", "vision", 2, Rect(42, 33, 96, 82), "rod-ion-channel", late = .86f),
    )

    private fun verifyCloseUps(vararg closeUps: CloseUp) = native { scenario ->
        for ((id, artName, chapter, region, file, lesson, late) in closeUps) {
            scenario.onActivity { activity ->
                activity.view("atlas-tab-2").performClick()
                (activity.view("atlas-search") as EditText).setText(id)
                assertTrue("Could not select $id", activity.view("atlas-entry-$id").performClick())
                activity.view("atlas-tab-1").performClick()
                if (lesson != 0) activity.view("atlas-function-lesson-$lesson").performClick()
                assertNotNull("No player after opening $id", activity.window.decorView.findViewWithTag<View>("atlas-function-player"))
            }
            runner.waitForIdleSync()
            scenario.onActivity { activity ->
                val player = activity.view("atlas-function-player") as HealthAtlasFunctionPlayer
                val start = player.story.chapter(player.phase)
                val direction = if (chapter >= start) "next" else "previous"
                repeat(kotlin.math.abs(chapter - start)) { activity.view("atlas-function-$direction").performClick() }
                assertEquals(chapter, player.story.chapter(player.phase))
                val frame = activity.view("atlas-function-frame")
                val art = activity.view("atlas-function-$artName-art") as HealthAtlasFunctionArt
                val caption = activity.view("atlas-function-caption") as TextView
                assertSame(frame, caption.parent.parent)
                assertEquals(activity.getString(player.story.chapters[chapter].second), caption.text.toString())
                val canvas = Bitmap.createBitmap(frame.width, frame.height, Bitmap.Config.ARGB_8888)
                try {
                    val size = minOf(art.width, art.height)
                    val x = art.left + (art.width - size) / 2
                    val y = art.top + (art.height - size) / 2
                    val w = size * region.width() / 100
                    val h = size * region.height() / 100
                    assertTrue("No visible artwork for $id", w > 0 && h > 0)
                    val pixels = IntArray(w * h)
                    fun hash(fraction: Float): Int {
                        art.phase = (chapter + fraction) / player.story.chapters.size
                        canvas.eraseColor(0)
                        frame.draw(Canvas(canvas))
                        canvas.getPixels(pixels, 0, w, x + size * region.left / 100,
                            y + size * region.top / 100, w, h)
                        return pixels.contentHashCode()
                    }
                    assertNotEquals(file, hash(.18f), hash(late))
                    java.io.File(context.getExternalFilesDir(null), "body-atlas-$file.png").outputStream().use {
                        canvas.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                } finally { canvas.recycle() }
                activity.onBackPressed()
            }
        }
    }

    @Test fun capturesAnAnimationAndItsPrincipleTogether() = native { scenario ->
        lateinit var expectedCaption: String
        scenario.onActivity { activity ->
            activity.view("atlas-hotspot-heart").performClick()
            activity.view("atlas-tab-1").performClick()
            repeat(3) { activity.view("atlas-function-next").performClick() }
            val player = activity.view("atlas-function-player") as HealthAtlasFunctionPlayer
            assertEquals(HealthAtlasFunctionStory.HEARTBEAT, player.story)
            assertEquals(3, player.story.chapter(player.phase))
            expectedCaption = (activity.view("atlas-function-caption") as TextView).text.toString()
        }
        runner.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5_000
        fun captionIsOnScreen(): Boolean {
            val root = runner.uiAutomation.rootInActiveWindow ?: return false
            return root.packageName?.toString() == context.packageName &&
                root.findAccessibilityNodeInfosByText(expectedCaption).any { it.isVisibleToUser }
        }
        while (!captionIsOnScreen() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(40)
        assertTrue("The requested chapter was not visible on the device", captionIsOnScreen())
        SystemClock.sleep(150)
        val bitmap = requireNotNull(runner.uiAutomation.takeScreenshot())
        try {
            java.io.File(context.getExternalFilesDir(null), "body-atlas-guided-heart.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { bitmap.recycle() }
    }
}
