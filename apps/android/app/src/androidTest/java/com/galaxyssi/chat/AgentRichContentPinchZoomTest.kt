package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.app.Instrumentation
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.ScrollView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRichContentPinchZoomTest {
    @Test
    fun plainImageTargetSupportsPinchZoomAndSingleFingerPan() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        lateinit var viewport: GalaxySSIPinchZoomViewport
        lateinit var image: ImageView
        val location = IntArray(2)
        var centerX = 0f
        var centerY = 0f
        instrumentation.runOnMainSync {
            image = ImageView(activity).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
            }
            viewport = GalaxySSIPinchZoomViewport(activity).apply {
                attach(image)
            }
            activity.setContentView(viewport)
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            viewport.getLocationOnScreen(location)
            centerX = location[0] + viewport.width / 2f
            centerY = location[1] + viewport.height / 2f
        }

        dispatchPinch(instrumentation, centerX, centerY)
        instrumentation.waitForIdleSync()
        val translationBefore = image.translationX
        dispatchDrag(instrumentation, centerX, centerY, centerX + 140f, centerY + 80f)
        instrumentation.waitForIdleSync()

        assertTrue(
            "Expected plain image preview zoom above 1.2, got ${viewport.currentZoomScale}",
            viewport.currentZoomScale > 1.2f
        )
        assertTrue(
            "Expected a single-finger drag to pan the zoomed image",
            image.translationX > translationBefore + 40f
        )
        instrumentation.runOnMainSync { activity.finish() }
    }

    @Test
    fun twoFingerSpreadReachesWebContentInsideAgentOutput() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        lateinit var viewport: GalaxySSIPinchZoomViewport
        lateinit var richOutput: View
        val webLocation = IntArray(2)
        var pinchCenterX = 0f
        var pinchCenterY = 0f
        instrumentation.runOnMainSync {
            richOutput = AgentRichContentView(activity, {}, {}, { _, _ -> }).create(
                AgentTranscriptEntry(
                    id = "pinch-integration",
                    role = AgentTranscriptRole.ASSISTANT,
                    text = "Web preview",
                    timestampMillis = System.currentTimeMillis(),
                    richOutputJson = AgentRichContentCodec.encode(listOf(AgentRichBlock(
                        id = "page",
                        type = AgentRichBlockType.WEBPAGE,
                        title = "Web preview",
                        uri = "https://example.com"
                    )))
                )
            )
            activity.setContentView(ScrollView(activity).apply { addView(richOutput) })
            viewport = requireNotNull(findZoomViewport(richOutput))
        }
        instrumentation.waitForIdleSync()
        SystemClock.sleep(1_000)
        var initialPageScale = 0f
        var finalPageScale = 0f
        instrumentation.runOnMainSync {
            @Suppress("DEPRECATION")
            initialPageScale = viewport.getChildAt(0).scaleX
            viewport.getLocationOnScreen(webLocation)
            pinchCenterX = webLocation[0] + viewport.width / 2f
            pinchCenterY = webLocation[1] + viewport.height / 2f
        }
        dispatchPinch(instrumentation, pinchCenterX, pinchCenterY)
        instrumentation.waitForIdleSync()
        SystemClock.sleep(250)
        instrumentation.runOnMainSync {
            @Suppress("DEPRECATION")
            finalPageScale = viewport.getChildAt(0).scaleX
        }

        assertTrue(
            "Expected integrated web preview zoom above 1.2, got ${viewport.currentZoomScale}",
            viewport.currentZoomScale > 1.2f
        )
        assertTrue(
            "Expected WebView page scale to grow from $initialPageScale, got $finalPageScale",
            finalPageScale > initialPageScale * 1.2f
        )
        instrumentation.runOnMainSync { activity.finish() }
    }

    private fun dispatchPinch(instrumentation: Instrumentation, centerX: Float, centerY: Float) {
        val downTime = SystemClock.uptimeMillis()
        val first = pointerProperties(0)
        val second = pointerProperties(1)
        instrumentation.sendPointerSync(event(downTime, downTime, MotionEvent.ACTION_DOWN, listOf(first), listOf(coords(centerX - 70f, centerY))))
        instrumentation.sendPointerSync(event(
            downTime,
            downTime + 16,
            MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(first, second),
            listOf(coords(centerX - 70f, centerY), coords(centerX + 70f, centerY))
        ))
        instrumentation.sendPointerSync(event(
            downTime,
            downTime + 32,
            MotionEvent.ACTION_MOVE,
            listOf(first, second),
            listOf(coords(centerX - 150f, centerY), coords(centerX + 150f, centerY))
        ))
        instrumentation.sendPointerSync(event(
            downTime,
            downTime + 48,
            MotionEvent.ACTION_MOVE,
            listOf(first, second),
            listOf(coords(centerX - 230f, centerY), coords(centerX + 230f, centerY))
        ))
        instrumentation.sendPointerSync(event(
            downTime,
            downTime + 64,
            MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(first, second),
            listOf(coords(centerX - 230f, centerY), coords(centerX + 230f, centerY))
        ))
        instrumentation.sendPointerSync(event(downTime, downTime + 80, MotionEvent.ACTION_UP, listOf(first), listOf(coords(centerX - 230f, centerY))))
    }

    private fun dispatchDrag(
        instrumentation: Instrumentation,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float
    ) {
        val downTime = SystemClock.uptimeMillis()
        val pointer = pointerProperties(0)
        instrumentation.sendPointerSync(
            event(downTime, downTime, MotionEvent.ACTION_DOWN, listOf(pointer), listOf(coords(startX, startY)))
        )
        instrumentation.sendPointerSync(
            event(
                downTime,
                downTime + 24,
                MotionEvent.ACTION_MOVE,
                listOf(pointer),
                listOf(coords(endX, endY))
            )
        )
        instrumentation.sendPointerSync(
            event(
                downTime,
                downTime + 48,
                MotionEvent.ACTION_UP,
                listOf(pointer),
                listOf(coords(endX, endY))
            )
        )
    }

    private fun findZoomViewport(view: View): GalaxySSIPinchZoomViewport? {
        if (view is GalaxySSIPinchZoomViewport && view.visibility == View.VISIBLE) return view
        if (view !is ViewGroup) return null
        for (index in 0 until view.childCount) {
            findZoomViewport(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    private fun pointerProperties(id: Int) = MotionEvent.PointerProperties().apply {
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
}
