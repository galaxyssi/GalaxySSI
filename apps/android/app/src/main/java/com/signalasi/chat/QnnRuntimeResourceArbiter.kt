package com.signalasi.chat

import java.io.Closeable
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

internal class QnnRuntimeResourceArbiter {
    private data class Registration(
        val id: Long,
        val releaseAsr: () -> Unit
    )

    private val ids = AtomicLong(0L)
    private val asrRegistration = AtomicReference<Registration?>(null)

    fun registerAsr(releaseAsr: () -> Unit): Closeable {
        val registration = Registration(ids.incrementAndGet(), releaseAsr)
        asrRegistration.set(registration)
        return Closeable { asrRegistration.compareAndSet(registration, null) }
    }

    fun releaseAsrForLocalModel() {
        asrRegistration.get()?.releaseAsr?.invoke()
    }
}

internal object SharedQnnRuntimeResources {
    val arbiter = QnnRuntimeResourceArbiter()
}
