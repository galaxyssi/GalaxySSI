package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

internal class QnnRuntimeResourceArbiter {
    private data class Registration(
        val id: Long,
        val reservesQnn: () -> Boolean
    )

    private val ids = AtomicLong(0L)
    private val asrRegistration = AtomicReference<Registration?>(null)

    fun registerAsr(reservesQnn: () -> Boolean): Closeable {
        val registration = Registration(ids.incrementAndGet(), reservesQnn)
        asrRegistration.set(registration)
        return Closeable { asrRegistration.compareAndSet(registration, null) }
    }

    fun asrHasPriority(): Boolean = asrRegistration.get()?.reservesQnn?.invoke() == true
}

internal object SharedQnnRuntimeResources {
    val arbiter = QnnRuntimeResourceArbiter()
}
