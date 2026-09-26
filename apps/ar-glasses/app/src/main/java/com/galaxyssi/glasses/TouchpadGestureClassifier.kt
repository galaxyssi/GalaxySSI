package com.galaxyssi.glasses

import kotlin.math.abs

internal enum class TouchpadAction { NONE, ACTIVATE, BACK, NEXT, PREVIOUS }

internal object TouchpadGestureClassifier {
    fun classify(
        pointerCount: Int,
        durationMs: Long,
        deltaX: Float,
        deltaY: Float,
        tapSlop: Float,
        swipeThreshold: Float
    ): TouchpadAction {
        val horizontal = abs(deltaX) >= abs(deltaY) * 0.65f
        if (pointerCount >= 2 && durationMs <= 550 && abs(deltaX) <= tapSlop && abs(deltaY) <= tapSlop) {
            return TouchpadAction.BACK
        }
        if (pointerCount != 1 || durationMs > 1200) return TouchpadAction.NONE
        if (abs(deltaX) <= tapSlop && abs(deltaY) <= tapSlop) return TouchpadAction.ACTIVATE
        if (!horizontal || abs(deltaX) < swipeThreshold) return TouchpadAction.NONE
        return if (deltaX < 0f) TouchpadAction.NEXT else TouchpadAction.PREVIOUS
    }
}
