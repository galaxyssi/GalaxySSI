package com.galaxyssi.chat

import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.app.Instrumentation
import android.app.Dialog
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.ScrollView
import android.widget.Button
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
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
        lateinit var dialog: Dialog
        lateinit var image: ImageView
        var centerX = 0f
        var centerY = 0f
        instrumentation.runOnMainSync {
            image = ImageView(activity).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
            }
            viewport = GalaxySSIPinchZoomViewport(activity).apply {
                attach(image)
            }
            // Keep the activity's real hierarchy intact while startup hydration is in flight.
            dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
                setContentView(viewport)
                show()
            }
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            assertTrue(viewport.width > 0 && viewport.height > 0)
            centerX = viewport.width / 2f
            centerY = viewport.height / 2f
        }

        val touch = viewportTouch(instrumentation, viewport)
        dispatchPinch(touch, centerX, centerY, engagedPinchRadius(viewport))
        instrumentation.waitForIdleSync()
        val translationBefore = image.translationX
        dispatchDrag(touch, centerX, centerY, centerX + 140f, centerY + 80f)
        instrumentation.waitForIdleSync()

        assertTrue(
            "Expected plain image preview zoom above 1.2, got ${viewport.currentZoomScale}",
            viewport.currentZoomScale > 1.2f
        )
        assertTrue(
            "Expected a single-finger drag to pan the zoomed image",
            image.translationX > translationBefore + 40f
        )
        instrumentation.runOnMainSync { dialog.dismiss(); activity.finish() }
    }

    @Test
    fun interactiveZoomTargetSeparatesLabelTapFromPan() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        lateinit var marker: Button
        lateinit var viewport: GalaxySSIPinchZoomViewport
        var dialog: Dialog? = null
        var clicks = 0
        try {
            instrumentation.runOnMainSync {
                marker = Button(activity).apply {
                    text = "Marker"
                    setOnClickListener { clicks++ }
                }
                viewport = GalaxySSIPinchZoomViewport(activity, keepZoomedTargetTaps = true).apply { attach(marker) }
                dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
                    setContentView(viewport)
                    show()
                }
            }
            instrumentation.waitForIdleSync()
            var x = 0f
            var y = 0f
            instrumentation.runOnMainSync {
                assertTrue(viewport.width > 0 && viewport.height > 0)
                x = viewport.width / 2f
                y = viewport.height / 2f
            }
            val touch = viewportTouch(instrumentation, viewport)
            dispatchPinch(touch, x, y, engagedPinchRadius(viewport))
            instrumentation.waitForIdleSync()
            assertTrue(viewport.currentZoomScale > 1.2f)
            assertEquals(0, clicks)
            dispatchDrag(touch, x, y, x + 125f, y + 54f)
            instrumentation.waitForIdleSync()
            assertTrue(marker.translationX > 20f)
            assertEquals(0, clicks)
            val down = SystemClock.uptimeMillis()
            val p = listOf(pointerProperties(0))
            val c = listOf(coords(x, y))
            touch(event(down, down, MotionEvent.ACTION_DOWN, p, c))
            touch(event(down, down + 28, MotionEvent.ACTION_UP, p, c))
            instrumentation.waitForIdleSync()
            assertEquals(1, clicks)
            instrumentation.runOnMainSync {
                viewport.resetZoom()
                assertEquals(1f, viewport.currentZoomScale, 0f)
                assertEquals(0f, marker.translationX, 0f)
            }
        } finally {
            instrumentation.runOnMainSync {
                dialog?.dismiss()
                activity.finish()
            }
        }
    }

    @Test
    fun twoFingerSpreadReachesWebContentInsideAgentOutput() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        lateinit var viewport: GalaxySSIPinchZoomViewport
        lateinit var dialog: Dialog
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
            dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
                setContentView(ScrollView(activity).apply { addView(richOutput) })
                show()
            }
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
        dispatchPinch(instrumentation::sendPointerSync, pinchCenterX, pinchCenterY, engagedPinchRadius(viewport))
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
        instrumentation.runOnMainSync { dialog.dismiss(); activity.finish() }
    }

    private fun viewportTouch(instrumentation: Instrumentation, viewport: GalaxySSIPinchZoomViewport):
        (MotionEvent) -> Unit = { motion ->
        try {
            instrumentation.runOnMainSync { viewport.dispatchTouchEvent(motion) }
        } finally {
            motion.recycle()
        }
    }

    private fun engagedPinchRadius(viewport: View): Float {
        val configuration = ViewConfiguration.get(viewport.context)
        val minimumSpan = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) configuration.scaledMinimumScalingSpan.toFloat()
            else 170f * viewport.resources.displayMetrics.density
        return minimumSpan / 2f + configuration.scaledTouchSlop + 1f
    }

    private fun dispatchPinch(touch: (MotionEvent) -> Unit, centerX: Float, centerY: Float, engaged: Float) {
        val downTime = SystemClock.uptimeMillis() - 80
        val first = pointerProperties(0)
        val second = pointerProperties(1)
        val start = .38f * engaged
        val widened = 1.5f * engaged
        touch(event(downTime, downTime, MotionEvent.ACTION_DOWN, listOf(first), listOf(coords(centerX - start, centerY))))
        touch(event(
            downTime,
            downTime + 16,
            MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(first, second),
            listOf(coords(centerX - start, centerY), coords(centerX + start, centerY))
        ))
        touch(event(
            downTime,
            downTime + 32,
            MotionEvent.ACTION_MOVE,
            listOf(first, second),
            listOf(coords(centerX - engaged, centerY), coords(centerX + engaged, centerY))
        ))
        touch(event(
            downTime,
            downTime + 48,
            MotionEvent.ACTION_MOVE,
            listOf(first, second),
            listOf(coords(centerX - widened, centerY), coords(centerX + widened, centerY))
        ))
        touch(event(
            downTime,
            downTime + 64,
            MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(first, second),
            listOf(coords(centerX - widened, centerY), coords(centerX + widened, centerY))
        ))
        touch(event(downTime, downTime + 80, MotionEvent.ACTION_UP, listOf(first), listOf(coords(centerX - widened, centerY))))
    }

    private fun dispatchDrag(
        touch: (MotionEvent) -> Unit,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float
    ) {
        val downTime = SystemClock.uptimeMillis() - 48
        val pointer = pointerProperties(0)
        touch(
            event(downTime, downTime, MotionEvent.ACTION_DOWN, listOf(pointer), listOf(coords(startX, startY)))
        )
        touch(
            event(
                downTime,
                downTime + 24,
                MotionEvent.ACTION_MOVE,
                listOf(pointer),
                listOf(coords(endX, endY))
            )
        )
        touch(
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
