package com.galaxyssi.chat

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMermaidDiagramRenderingTest {
    @Test
    fun diagramCardFillsWidthUsesTallPreviewAndKeepsSaveBelow() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val card = AgentMermaidDiagramCard(
                    activity,
                    AgentRichBlock(
                        id = "architecture",
                        type = AgentRichBlockType.MERMAID,
                        text = "flowchart TD\nA[Request] --> B[Agent]",
                        language = "mermaid"
                    )
                )
                val width = 800
                card.measure(
                    View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(2_000, View.MeasureSpec.AT_MOST)
                )
                card.layout(0, 0, card.measuredWidth, card.measuredHeight)

                assertEquals(width, card.previewFrame.measuredWidth)
                assertEquals(960, card.previewFrame.measuredHeight)
                assertEquals(card.previewFrame.bottom, card.saveButton.parent.let { (it as View).top })
                assertTrue(card.saveButton.contentDescription.isNotBlank())
            }
        }
    }

    @Test
    fun fullscreenViewportSupportsPinchZoomAndSingleFingerPan() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        lateinit var viewport: GalaxySSIPinchZoomViewport
        lateinit var target: View
        instrumentation.runOnMainSync {
            target = View(instrumentation.targetContext)
            viewport = GalaxySSIPinchZoomViewport(instrumentation.targetContext).apply {
                attach(target)
                measure(exactly(800), exactly(1_200))
                layout(0, 0, 800, 1_200)
            }
            dispatchPinch(viewport, 400f, 600f)
        }

        val translationBefore = target.translationX
        instrumentation.runOnMainSync {
            dispatchDrag(viewport, 400f, 600f, 540f, 680f)
        }

        assertTrue(viewport.currentZoomScale > 1.2f)
        assertTrue(target.translationX > translationBefore + 40f)
    }

    private fun dispatchPinch(view: FrameLayout, centerX: Float, centerY: Float) {
        val downTime = SystemClock.uptimeMillis()
        val first = pointer(0)
        val second = pointer(1)
        view.dispatchTouchEvent(event(downTime, downTime, MotionEvent.ACTION_DOWN, listOf(first), listOf(coords(centerX - 70f, centerY))))
        view.dispatchTouchEvent(event(
            downTime,
            downTime + 16,
            MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(first, second),
            listOf(coords(centerX - 70f, centerY), coords(centerX + 70f, centerY))
        ))
        view.dispatchTouchEvent(event(
            downTime,
            downTime + 32,
            MotionEvent.ACTION_MOVE,
            listOf(first, second),
            listOf(coords(centerX - 150f, centerY), coords(centerX + 150f, centerY))
        ))
        view.dispatchTouchEvent(event(
            downTime,
            downTime + 48,
            MotionEvent.ACTION_MOVE,
            listOf(first, second),
            listOf(coords(centerX - 230f, centerY), coords(centerX + 230f, centerY))
        ))
        view.dispatchTouchEvent(event(
            downTime,
            downTime + 64,
            MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(first, second),
            listOf(coords(centerX - 230f, centerY), coords(centerX + 230f, centerY))
        ))
        view.dispatchTouchEvent(event(
            downTime,
            downTime + 80,
            MotionEvent.ACTION_UP,
            listOf(first),
            listOf(coords(centerX - 230f, centerY))
        ))
    }

    private fun dispatchDrag(view: FrameLayout, startX: Float, startY: Float, endX: Float, endY: Float) {
        val downTime = SystemClock.uptimeMillis()
        val pointer = pointer(0)
        view.dispatchTouchEvent(event(downTime, downTime, MotionEvent.ACTION_DOWN, listOf(pointer), listOf(coords(startX, startY))))
        view.dispatchTouchEvent(event(downTime, downTime + 24, MotionEvent.ACTION_MOVE, listOf(pointer), listOf(coords(endX, endY))))
        view.dispatchTouchEvent(event(downTime, downTime + 48, MotionEvent.ACTION_UP, listOf(pointer), listOf(coords(endX, endY))))
    }

    private fun pointer(id: Int) = MotionEvent.PointerProperties().apply {
        this.id = id
        toolType = MotionEvent.TOOL_TYPE_FINGER
    }

    private fun coords(x: Float, y: Float) = MotionEvent.PointerCoords().apply {
        this.x = x
        this.y = y
        pressure = 1f
        size = 1f
    }

    private fun event(
        downTime: Long,
        eventTime: Long,
        action: Int,
        properties: List<MotionEvent.PointerProperties>,
        coordinates: List<MotionEvent.PointerCoords>
    ): MotionEvent = MotionEvent.obtain(
        downTime,
        eventTime,
        action,
        properties.size,
        properties.toTypedArray(),
        coordinates.toTypedArray(),
        0,
        0,
        1f,
        1f,
        0,
        0,
        InputDevice.SOURCE_TOUCHSCREEN,
        0
    )

    private fun exactly(size: Int): Int = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
}
