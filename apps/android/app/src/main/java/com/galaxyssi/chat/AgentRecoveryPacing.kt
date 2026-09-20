package com.galaxyssi.chat

/** Failed reads back off; new authenticated progress makes a task immediately eligible. */
internal object AgentRecoveryPacing {
    data class State(val attempts: Int = 0, val nextAt: Long = 0, val progress: String = "")
    private val delays = longArrayOf(15_000, 30_000, 60_000, 120_000, 300_000, 900_000, 3_600_000)

    fun reserve(state: State, now: Long): State? {
        if (now < state.nextAt && state.nextAt - now <= delays.last()) return null
        val index = state.attempts.coerceIn(0, delays.lastIndex)
        return state.copy(attempts = (index + 1).coerceAtMost(delays.size), nextAt = now + delays[index])
    }

    fun observed(state: State, progress: String, now: Long): State =
        if (progress == state.progress) state else State(nextAt = now + delays.first(), progress = progress)
}
