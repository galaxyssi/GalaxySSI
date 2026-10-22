package com.galaxyssi.chat

internal class MainPageBackPressGate {
    private var firstPressAt: Long? = null

    fun shouldBackground(nowElapsedMillis: Long): Boolean {
        val first = firstPressAt
        if (first != null && nowElapsedMillis - first in 0L..500L) {
            reset()
            return true
        }
        firstPressAt = nowElapsedMillis
        return false
    }

    fun reset() {
        firstPressAt = null
    }
}
