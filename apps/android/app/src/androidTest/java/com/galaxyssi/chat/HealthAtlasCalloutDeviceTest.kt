package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class HealthAtlasCalloutDeviceTest {
    private fun runWithAtlas(block: (HealthBodyAtlasActivity) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixture = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val intent = Intent(context, HealthBodyAtlasActivity::class.java).putHealthNavigationFixture(fixture)
            ActivityScenario.launch<HealthBodyAtlasActivity>(intent).use { it.onActivity(block) }
        } finally { clearHealthOverviewFixture(context, fixture) }
    }

    @Test fun everyCatalogueIllustrationAndAlternateViewPointsAtTheArt() = runWithAtlas { activity ->
        val data = HealthBodyAtlas.load(activity)
        val viewport = HealthCenterViews(activity)
        var plates = 0
        for (item in listOf(null) + data.items) {
            val views = HealthAtlasPlates.viewsForId(item?.id).map { it.viewKey }.ifEmpty { listOf(null) }
            views.forEach { key ->
                val art = HealthAtlasArtwork(activity, data, item, {}, { _, _ -> }, {}, initialView = key)
                val figure = requireNotNull(art.findViewWithTag<HealthAtlasFigureFrame>("atlas-structure-figure"))
                for (width in listOf(280, 380)) {
                    layout(art, viewport.dp(width))
                    if (item != null) {
                        val copy = requireNotNull(figure.findViewWithTag<TextView>("atlas-art-explanation"))
                        assertEquals(item.id, item.description, copy.text.toString())
                        assertTrue(item.id, copy.layout.height + copy.totalPaddingTop + copy.totalPaddingBottom <= copy.height)
                    }
                    assertCallout(activity, figure, item?.id ?: "whole")
                    assertLabelsClear(figure, item?.id ?: "whole")
                }
                plates++
            }
        }
        assertTrue(plates >= data.items.size + 1)
    }

    @Test fun everyChapterKeepsItsReadableAnnotationAndSameSceneSize() = runWithAtlas { activity ->
        val viewport = HealthCenterViews(activity)
        for (story in HealthAtlasFunctionStory.entries) {
            val player = HealthAtlasFunctionPlayer(activity, story, 0f, {})
            val frame = player.findViewWithTag<HealthAtlasFigureFrame>("atlas-function-frame")
            val copy = player.findViewWithTag<TextView>("atlas-function-caption")
            val next = player.findViewWithTag<View>("atlas-function-next")
            val previous = player.findViewWithTag<View>("atlas-function-previous")
            for (dp in listOf(280, 380, 720)) {
                repeat(story.chapters.size) { previous.performClick() }
                var height = 0
                story.chapters.forEachIndexed { index, chapter ->
                    if (index > 0) next.performClick()
                    layout(player, viewport.dp(dp))
                    assertEquals("$story $index", activity.getString(chapter.second), copy.text.toString())
                    assertTrue("$story $index at $dp", copy.layout.height + copy.totalPaddingTop + copy.totalPaddingBottom <= copy.height)
                    if (index == 0) {
                        height = frame.height
                        assertCallout(activity, frame, "$story at $dp")
                    } else assertEquals("$story shifted when changing chapter", height, frame.height)
                }
            }
        }
    }

    private fun layout(view: View, width: Int) {
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        view.layout(0, 0, view.measuredWidth, view.measuredHeight)
    }

    private fun assertLabelsClear(figure: HealthAtlasFigureFrame, id: String) {
        val note = figure.legend
        val bounds = Rect(note.left, note.top, note.right, note.bottom)
        fun visit(view: View) {
            val tag = view.tag?.toString().orEmpty()
            if (tag.startsWith("atlas-hotspot-") || tag.startsWith("atlas-feature-")) {
                val label = Rect(0, 0, view.width, view.height)
                figure.offsetDescendantRectToMyCoords(view, label)
                assertFalse("$id $tag is covered by the note", Rect.intersects(bounds, label))
            }
            if (view is ViewGroup) for (i in 0 until view.childCount) visit(view.getChildAt(i))
        }
        visit(figure)
    }

    private fun assertCallout(activity: Activity, figure: HealthAtlasFigureFrame, id: String) {
        val note = figure.legend
        val picture = figure.getChildAt(figure.indexOfChild(note) - 1)
        assertTrue(id, note.top < picture.bottom)
        assertTrue("$id no longer has its note to the left", note.right < picture.left)
        assertTrue(id, note.bottom > picture.top)
        assertTrue(id, note.bottom <= figure.height && note.right <= figure.width)
        val sample = Bitmap.createBitmap(3, 3, Bitmap.Config.ARGB_8888)
        try {
            figure.draw(Canvas(sample))
            val target = requireNotNull(figure.annotationTarget) { id }
            assertTrue(id, target.x >= picture.left && target.x < picture.right)
            assertTrue(id, target.y >= picture.top && target.y < picture.bottom)
            figure.draw(Canvas(sample).apply { translate(1 - target.x, 1 - target.y) })
            assertEquals(id, activity.getColor(R.color.health_overview_green), sample.getPixel(1, 1))
        } finally { sample.recycle() }
    }
}
