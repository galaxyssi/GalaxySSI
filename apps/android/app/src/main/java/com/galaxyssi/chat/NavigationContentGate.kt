package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicLong

internal class NavigationContentGate {
    private val generation = AtomicLong(0L)

    fun begin(): Long = generation.incrementAndGet()

    fun invalidate() {
        generation.incrementAndGet()
    }

    fun invalidateIfCurrent(token: Long) {
        generation.compareAndSet(token, token + 1L)
    }

    fun isCurrent(token: Long): Boolean = generation.get() == token
}
