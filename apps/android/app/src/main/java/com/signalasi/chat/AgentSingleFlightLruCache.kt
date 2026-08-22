package com.signalasi.chat

import java.util.concurrent.CountDownLatch

/** Computes one value per key while allowing unrelated keys to compile concurrently. */
internal class AgentSingleFlightLruCache<K : Any, V : Any>(
    private val maximumEntries: Int
) {
    private class InFlightValue<V : Any> {
        private val completion = CountDownLatch(1)

        @Volatile
        private var value: V? = null

        @Volatile
        private var failure: Throwable? = null

        fun complete(value: V) {
            this.value = value
            completion.countDown()
        }

        fun fail(failure: Throwable) {
            this.failure = failure
            completion.countDown()
        }

        fun await(): V {
            try {
                completion.await()
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                throw interrupted
            }
            failure?.let { throw it }
            return requireNotNull(value)
        }
    }

    init {
        require(maximumEntries > 0)
    }

    private val lock = Any()
    private val values = LinkedHashMap<K, V>(maximumEntries + 1, 0.75f, true)
    private val inFlightValues = mutableMapOf<K, InFlightValue<V>>()

    fun getOrCompute(key: K, compute: () -> V): V {
        var ownsComputation = false
        val inFlight = synchronized(lock) {
            values[key]?.let { cached -> return cached }
            inFlightValues[key] ?: InFlightValue<V>().also { created ->
                inFlightValues[key] = created
                ownsComputation = true
            }
        }
        if (!ownsComputation) return inFlight.await()

        return try {
            val value = compute()
            synchronized(lock) {
                values[key] = value
                while (values.size > maximumEntries) {
                    values.remove(values.entries.first().key)
                }
            }
            inFlight.complete(value)
            value
        } catch (failure: Throwable) {
            inFlight.fail(failure)
            throw failure
        } finally {
            synchronized(lock) {
                if (inFlightValues[key] === inFlight) {
                    inFlightValues.remove(key)
                }
            }
        }
    }
}
