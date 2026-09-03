package com.signalasi.chat

import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.Lock
import java.util.concurrent.locks.ReentrantReadWriteLock

/** Process-wide read/write gate shared by every Agent runtime and conversation. */
internal object AgentNativeToolExecutionGate {
    private val stateLock = ReentrantReadWriteLock(true)
    private val readPermits = Semaphore(MAX_PARALLEL_READS, true)

    fun <T> execute(
        descriptor: AgentNativeToolDescriptor,
        invocation: AgentNativeToolInvocation,
        block: () -> T
    ): T {
        val parallelRead = descriptor.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY
        if (parallelRead) acquireReadPermit(invocation)
        val lock = if (parallelRead) stateLock.readLock() else stateLock.writeLock()
        try {
            acquire(lock, invocation)
            try {
                invocation.checkpoint()
                return block()
            } finally {
                lock.unlock()
            }
        } finally {
            if (parallelRead) readPermits.release()
        }
    }

    private fun acquireReadPermit(invocation: AgentNativeToolInvocation) {
        while (!waitForPermit()) {
            invocation.checkpoint()
        }
    }

    private fun acquire(lock: Lock, invocation: AgentNativeToolInvocation) {
        while (!waitForLock(lock)) {
            invocation.checkpoint()
        }
    }

    private fun waitForPermit(): Boolean = try {
        readPermits.tryAcquire(POLL_MILLIS, TimeUnit.MILLISECONDS)
    } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        throw AgentNativeToolCancelledException()
    }

    private fun waitForLock(lock: Lock): Boolean = try {
        lock.tryLock(POLL_MILLIS, TimeUnit.MILLISECONDS)
    } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        throw AgentNativeToolCancelledException()
    }

    private const val MAX_PARALLEL_READS = 4
    private const val POLL_MILLIS = 100L
}
