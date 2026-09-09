package com.galaxyssi.chat

/** Coalesces same-thread reentrant dispatch into the next dependency-selection pass. */
internal class AgentPlanDispatchLoop<T> {
    private class Frame(var requested: Boolean = false)
    private val active = ThreadLocal<Frame>()

    fun run(current: () -> T, canContinue: () -> Boolean, step: () -> T): T {
        active.get()?.let { frame ->
            frame.requested = true
            return current()
        }
        val frame = Frame()
        active.set(frame)
        try {
            while (true) {
                frame.requested = false
                val result = step()
                if (!frame.requested) return result
                if (!canContinue()) return current()
            }
        } finally {
            active.remove()
        }
    }
}
