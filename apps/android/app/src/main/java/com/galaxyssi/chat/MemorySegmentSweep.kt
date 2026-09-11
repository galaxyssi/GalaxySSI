package com.galaxyssi.chat

internal class MemoryMaintenanceYield : RuntimeException(null, null, false, false)

/** One scheduling quantum, not a corpus limit. The catalog owns the durable cursor. */
internal class MemorySegmentSweep(
    private val shouldYield: () -> Boolean,
    private val step: (() -> Unit) -> Boolean?,
    private val clockNanos: () -> Long = System::nanoTime,
    private val quantumNanos: Long = 5_000_000_000L
) {
    enum class Outcome { COMPLETE, DEFERRED }

    fun run(): Outcome {
        require(quantumNanos > 0)
        val started = clockNanos()
        val checkActive = {
            if (shouldYield() || clockNanos() - started >= quantumNanos) throw MemoryMaintenanceYield()
        }
        try {
            while (true) {
                checkActive()
                when (step(checkActive)) {
                    null -> return Outcome.DEFERRED
                    true -> return Outcome.COMPLETE
                    false -> Unit
                }
            }
        } catch (_: MemoryMaintenanceYield) { return Outcome.DEFERRED }
    }
}
