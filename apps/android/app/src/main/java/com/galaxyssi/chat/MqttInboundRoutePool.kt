package com.galaxyssi.chat

import java.util.ArrayDeque
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Bounded wire admission. A Signal peer has at most one active handler across all mailboxes. */
internal class MqttInboundRoutePool<T : Any>(
    private val process: (T) -> Unit,
    private val onFailure: (Throwable) -> Unit = {},
    private val maxWorkers: Int = 4,
    private val maxPending: Int = 1_024,
    private val maxBytes: Long = 32L * 1024 * 1024,
    private val routePending: Int = 64,
    private val routeBytes: Long = 8L * 1024 * 1024,
    private val idleMillis: Long = 5_000,
    private val threadFactory: (Runnable) -> Thread = { work ->
        Thread(work, "galaxyssi-mqtt-inbound").apply { isDaemon = true }
    }
) : AutoCloseable {
    enum class Admission { ACCEPTED, CLOSED, ROUTE_COUNT, ROUTE_BYTES, GLOBAL_COUNT, GLOBAL_BYTES, WORKER_UNAVAILABLE }
    data class Snapshot(val workers: Int, val active: Int, val pending: Int, val routes: Int,
                        val retainedBytes: Long, val highBytes: Long, val accepted: Long,
                        val processed: Long, val failed: Long, val cancelled: Long,
                        val rejected: Map<Admission, Long>, val closed: Boolean)
    private data class Item<T>(val value: T, val bytes: Int)
    private class Lane<T> {
        val items = ArrayDeque<Item<T>>()
        var bytes = 0L
        var active = false
    }
    private data class Work<T>(val scope: String, val lane: Lane<T>, val bytes: Int, var item: Item<T>?)

    init {
        require(maxWorkers in 1..32 && maxPending in 1..10_000 && routePending in 1..maxPending)
        require(maxBytes in 1..(128L * 1024 * 1024) && routeBytes in 1..maxBytes)
        require(idleMillis in 1..120_000)
    }

    private val lock = ReentrantLock()
    private val changed = lock.newCondition()
    private val lanes = mutableMapOf<String, Lane<T>>()
    private val ready = linkedSetOf<String>()
    private val workers = mutableSetOf<Thread>()
    private var active = 0
    private var pending = 0
    private var retainedBytes = 0L
    private var highBytes = 0L
    private var accepted = 0L
    private var processed = 0L
    private var failed = 0L
    private var cancelled = 0L
    private val rejected = mutableMapOf<Admission, Long>()
    private var closed = false

    /** Returns immediately; a rejected packet has not been durably accepted or peer-acknowledged. */
    fun submit(scope: String, value: T, size: Int): Admission {
        require(scope.isNotBlank() && scope.length <= 512 && size > 0)
        return lock.withLock {
            fun reject(reason: Admission): Admission {
                rejected[reason] = (rejected[reason] ?: 0) + 1
                return reason
            }
            val current = lanes[scope]
            when {
                closed -> return reject(Admission.CLOSED)
                (current?.items?.size ?: 0) + (if (current?.active == true) 1 else 0) >= routePending ->
                    return reject(Admission.ROUTE_COUNT)
                (current?.bytes ?: 0) + size > routeBytes -> return reject(Admission.ROUTE_BYTES)
                pending + active >= maxPending -> return reject(Admission.GLOBAL_COUNT)
                retainedBytes + size > maxBytes -> return reject(Admission.GLOBAL_BYTES)
            }
            val lane = lanes.getOrPut(scope) { Lane() }
            lane.items.addLast(Item(value, size))
            lane.bytes += size
            retainedBytes += size
            pending++
            if (!lane.active) ready.add(scope)
            val desired = minOf(maxWorkers, active + ready.size)
            while (workers.size < desired) {
                var worker: Thread? = null
                try {
                    worker = threadFactory(Runnable(::runWorker))
                    workers.add(worker)
                    worker.start()
                } catch (_: Exception) {
                    workers.remove(worker)
                    if (workers.isEmpty()) {
                        lane.items.removeLast()
                        pending--
                        release(scope, lane, size)
                        ready.remove(scope)
                        return reject(Admission.WORKER_UNAVAILABLE)
                    }
                    break
                }
            }
            accepted++
            highBytes = maxOf(highBytes, retainedBytes)
            changed.signalAll()
            Admission.ACCEPTED
        }
    }

    private fun release(scope: String, lane: Lane<T>, size: Int) {
        retainedBytes -= size
        lane.bytes -= size
        if (!lane.active && lane.items.isEmpty()) lanes.remove(scope)
    }

    private fun runWorker() {
        val worker = Thread.currentThread()
        while (true) {
            val work = lock.withLock {
                var remaining = TimeUnit.MILLISECONDS.toNanos(idleMillis)
                while (ready.isEmpty() && !closed && remaining > 0) {
                    try {
                        remaining = changed.awaitNanos(remaining)
                    } catch (_: InterruptedException) {
                        // Lifecycle cancellation uses close(), never interrupts an active Signal handler.
                    }
                }
                if (ready.isEmpty()) {
                    workers.remove(worker)
                    changed.signalAll()
                    return
                }
                val scope = ready.first()
                ready.remove(scope)
                val lane = lanes.getValue(scope)
                lane.active = true
                active++
                pending--
                val item = lane.items.removeFirst()
                Work(scope, lane, item.bytes, item)
            }
            val didFail = processOne(work)
            lock.withLock {
                work.lane.active = false
                active--
                release(work.scope, work.lane, work.bytes)
                if (work.lane.items.isNotEmpty()) ready.add(work.scope)
                processed++
                if (didFail) failed++
                changed.signalAll()
            }
        }
    }

    private fun processOne(work: Work<T>): Boolean = try {
        process(checkNotNull(work.item).value)
        false
    } catch (error: Throwable) {
        runCatching { onFailure(error) }
        true
    } finally {
        work.item = null
    }

    fun snapshot(): Snapshot = lock.withLock {
        Snapshot(workers.size, active, pending, lanes.size, retainedBytes, highBytes, accepted,
            processed, failed, cancelled, rejected.toMap(), closed)
    }

    fun awaitIdle(timeoutMillis: Long = 5_000): Boolean = lock.withLock {
        var remaining = TimeUnit.MILLISECONDS.toNanos(timeoutMillis.coerceAtLeast(0))
        while (active + pending > 0 && remaining > 0) remaining = changed.awaitNanos(remaining)
        active + pending == 0
    }

    /** Does not interrupt an accepted handler or imply cancellation of a business task. */
    fun close(cancelPending: Boolean) = lock.withLock {
        closed = true
        if (cancelPending) {
            lanes.keys.toList().forEach { scope ->
                val lane = lanes.getValue(scope)
                while (lane.items.isNotEmpty()) {
                    val size = lane.items.removeFirst().bytes
                    pending--
                    cancelled++
                    release(scope, lane, size)
                }
            }
            ready.clear()
        }
        changed.signalAll()
    }

    override fun close() = close(cancelPending = true)
}
