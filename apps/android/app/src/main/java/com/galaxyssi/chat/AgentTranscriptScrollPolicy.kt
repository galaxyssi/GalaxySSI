package com.galaxyssi.chat

internal object AgentTranscriptScrollPolicy {
    fun nextAutoFollow(
        current: Boolean,
        userScrollActive: Boolean,
        itemCount: Int,
        lastVisiblePosition: Int,
        remainingPx: Int,
        thresholdPx: Int
    ): Boolean {
        if (!userScrollActive) return current
        return itemCount == 0 ||
            (lastVisiblePosition == itemCount - 1 && remainingPx <= thresholdPx)
    }

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
