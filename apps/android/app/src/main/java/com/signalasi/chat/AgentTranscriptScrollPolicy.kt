package com.signalasi.chat

internal object AgentTranscriptScrollPolicy {
    fun shouldLoadOlderFromScroll(
        dy: Int,
        firstVisiblePosition: Int,
        hydrationPending: Boolean
    ): Boolean =
        dy < 0 &&
            !hydrationPending &&
            firstVisiblePosition <= 1

    fun shouldLoadOlderFromPull(
        downY: Float,
        currentY: Float,
        canScrollUp: Boolean,
        hydrationPending: Boolean,
        thresholdPx: Int
    ): Boolean =
        !hydrationPending &&
            !canScrollUp &&
            currentY - downY >= thresholdPx
}
