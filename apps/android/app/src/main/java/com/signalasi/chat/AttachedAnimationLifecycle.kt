package com.signalasi.chat

internal class AttachedAnimationLifecycle(
    private val startAnimation: () -> Unit,
    private val stopAnimation: () -> Unit
) {
    private var running = false

    fun updateAttached(attached: Boolean) {
        if (attached == running) return
        running = attached
        if (attached) startAnimation() else stopAnimation()
    }
}
