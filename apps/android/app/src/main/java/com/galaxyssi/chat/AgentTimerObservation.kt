package com.galaxyssi.chat

/** Conservative Samsung adapter; other Clock apps remain unverified for model-driven inspection. */
internal object AgentTimerObservation {
    const val PACKAGE = "com.sec.android.app.clockpackage"
    data class Sample(val label: String, val remaining: Int, val paused: Boolean, val observedAt: Long)

    fun read(frame: PhoneUiSnapshot?, label: String): Sample? {
        if (frame == null || frame.packageName != PACKAGE || frame.truncated) return null
        val names = frame.nodes.filter { it.viewId.endsWith(":id/timer_name_view") }
        if (names.size != 1 || names.single().text != label) return null
        val clock = frame.nodes.singleOrNull { it.viewId.endsWith(":id/timer_time_view") } ?: return null
        val seconds = AgentDeviceIntent.seconds(clock.description.ifBlank { clock.text }) ?: return null
        val paused = frame.nodes.any { it.enabled && it.viewId.endsWith(":id/timer_resume_button") }
        val running = frame.nodes.any { it.enabled && it.viewId.endsWith(":id/timer_pause_button") }
        if (paused == running) return null
        return Sample(label, seconds, paused, frame.observedAt)
    }

    fun provesRunning(a: Sample?, b: Sample?, duration: Int, minimumRemaining: Int = 0): Boolean = a != null && b != null &&
        a.label == b.label && !a.paused && !b.paused && b.observedAt > a.observedAt &&
        a.remaining in minimumRemaining..duration && b.remaining < a.remaining && b.remaining > 0 &&
        a.remaining - b.remaining <= (b.observedAt - a.observedAt) / 1000 + 2

    fun provesPaused(a: Sample?, b: Sample?): Boolean = a != null && b != null &&
        a.label == b.label && a.paused && b.paused && a.remaining == b.remaining &&
        b.observedAt - a.observedAt >= 1000

    fun provesRemoved(frame: PhoneUiSnapshot?, label: String): Boolean = frame != null &&
        frame.packageName == PACKAGE && !frame.truncated &&
        frame.nodes.none { it.text == label } && frame.nodes.any {
            it.viewId.endsWith(":id/timer_start_button") || it.viewId.endsWith(":id/timer_name_view")
        }

    fun control(frame: PhoneUiSnapshot, label: String, operation: String): PhoneUiNode? {
        if (read(frame, label) == null) return null
        val suffix = when (operation) {
            "pause" -> "timer_pause_button"
            "start", "resume" -> "timer_resume_button"
            "cancel", "replace" -> "timer_cancel_button"
            else -> return null
        }
        return frame.nodes.singleOrNull { it.enabled && it.clickable && it.viewId.endsWith(":id/$suffix") }
    }
}
