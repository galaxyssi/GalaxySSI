package com.galaxyssi.glasses

import org.junit.Assert.assertEquals
import org.junit.Test

class TouchpadGestureClassifierTest {
    private fun classify(pointers: Int, duration: Long, x: Float, y: Float) =
        TouchpadGestureClassifier.classify(pointers, duration, x, y, tapSlop = 24f, swipeThreshold = 72f)

    @Test fun singleTapActivatesAndTwoFingerTapReturns() {
        assertEquals(TouchpadAction.ACTIVATE, classify(1, 180, 5f, 3f))
        assertEquals(TouchpadAction.BACK, classify(2, 250, 8f, -4f))
    }

    @Test fun horizontalSwipesMoveInContentOrder() {
        assertEquals(TouchpadAction.NEXT, classify(1, 400, -100f, 8f))
        assertEquals(TouchpadAction.PREVIOUS, classify(1, 400, 100f, -8f))
        assertEquals(TouchpadAction.NEXT, classify(1, 400, -80f, 60f))
    }

    @Test fun verticalShortAndLongGesturesAreIgnored() {
        assertEquals(TouchpadAction.NONE, classify(1, 300, 8f, 100f))
        assertEquals(TouchpadAction.NONE, classify(1, 300, 50f, 2f))
        assertEquals(TouchpadAction.NONE, classify(1, 1500, -100f, 0f))
    }
}
