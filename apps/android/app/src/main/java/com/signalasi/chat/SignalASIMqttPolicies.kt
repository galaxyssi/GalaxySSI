package com.signalasi.chat

import java.util.LinkedHashMap

internal object MqttPublishGuard {
    inline fun <T> attempt(operation: () -> T): Result<T> = runCatching(operation)
}

internal enum class MqttPublishResult(val accepted: Boolean) {
    PUBLISHED(true),
    QUEUED(true),
    FAILED(false)
}

internal object MqttOutboxDispatchPolicy {
    fun result(connected: Boolean, published: Boolean): MqttPublishResult =
        if (connected && published) MqttPublishResult.PUBLISHED else MqttPublishResult.QUEUED
}

internal class MqttBrokerAckWatchdog(
    private val timeoutMillis: Long
) {
    init {
        require(timeoutMillis > 0L)
    }

    private val publishedAtByMessageId = LinkedHashMap<Int, Long>()

    @Synchronized
    fun onPublished(messageId: Int, nowElapsedMillis: Long) {
        publishedAtByMessageId.putIfAbsent(messageId, nowElapsedMillis)
    }

    @Synchronized
    fun onAcknowledged(messageId: Int) {
        publishedAtByMessageId.remove(messageId)
    }

    @Synchronized
    fun nextCheckDelayMillis(nowElapsedMillis: Long): Long? =
        publishedAtByMessageId.values.minOrNull()?.let { publishedAt ->
            (timeoutMillis - (nowElapsedMillis - publishedAt)).coerceAtLeast(0L)
        }

    @Synchronized
    fun oldestPendingAgeMillis(nowElapsedMillis: Long): Long? =
        publishedAtByMessageId.values.minOrNull()?.let { publishedAt ->
            (nowElapsedMillis - publishedAt).coerceAtLeast(0L)
        }

    @Synchronized
    fun pendingCount(): Int = publishedAtByMessageId.size

    @Synchronized
    fun clear() {
        publishedAtByMessageId.clear()
    }
}

internal class MqttBrokerDeliveryRegistration(
    private val maxCompletedMessageIds: Int = 256
) {
    private enum class State {
        ACKNOWLEDGED_BEFORE_REGISTRATION,
        REGISTERED,
        COMPLETED
    }

    init {
        require(maxCompletedMessageIds > 0)
    }

    private val states = LinkedHashMap<Int, State>()

    @Synchronized
    fun onPublished(messageId: Int): Boolean {
        val acknowledgedEarly = states[messageId] == State.ACKNOWLEDGED_BEFORE_REGISTRATION
        states[messageId] = State.REGISTERED
        trimCompleted()
        return acknowledgedEarly
    }

    @Synchronized
    fun onAcknowledged(messageId: Int): Boolean = when (states[messageId]) {
        State.REGISTERED -> {
            states[messageId] = State.COMPLETED
            trimCompleted()
            true
        }
        State.COMPLETED,
        State.ACKNOWLEDGED_BEFORE_REGISTRATION -> false
        null -> {
            states[messageId] = State.ACKNOWLEDGED_BEFORE_REGISTRATION
            false
        }
    }

    @Synchronized
    fun clear() {
        states.clear()
    }

    private fun trimCompleted() {
        var removeCount = states.values.count { it == State.COMPLETED } - maxCompletedMessageIds
        if (removeCount <= 0) return
        val iterator = states.entries.iterator()
        while (iterator.hasNext() && removeCount > 0) {
            if (iterator.next().value == State.COMPLETED) {
                iterator.remove()
                removeCount -= 1
            }
        }
    }
}

internal class MqttConnectionRetryPolicy(
    private val delaysMillis: LongArray = longArrayOf(2_000L, 5_000L, 10_000L, 20_000L, 30_000L)
) {
    init {
        require(delaysMillis.isNotEmpty())
        require(delaysMillis.all { it >= 0L })
    }

    private var attempt = 0

    @Synchronized
    fun nextDelayMillis(): Long {
        val delay = delaysMillis[attempt.coerceAtMost(delaysMillis.lastIndex)]
        attempt += 1
        return delay
    }

    @Synchronized
    fun reset() {
        attempt = 0
    }
}

internal enum class MqttSubscriptionAttemptOutcome {
    STALE,
    PENDING,
    READY,
    RETRY
}

internal class MqttSubscriptionRecoveryState {
    private var generation = 0
    private var remaining = 0
    private var failed = false

    @Synchronized
    fun begin(subscriptionCount: Int): Int {
        require(subscriptionCount > 0)
        generation += 1
        remaining = subscriptionCount
        failed = false
        return generation
    }

    @Synchronized
    fun complete(attemptGeneration: Int, succeeded: Boolean): MqttSubscriptionAttemptOutcome {
        if (attemptGeneration != generation || remaining <= 0) {
            return MqttSubscriptionAttemptOutcome.STALE
        }
        if (!succeeded) failed = true
        remaining -= 1
        if (remaining > 0) return MqttSubscriptionAttemptOutcome.PENDING
        return if (failed) MqttSubscriptionAttemptOutcome.RETRY else MqttSubscriptionAttemptOutcome.READY
    }

    @Synchronized
    fun invalidate() {
        generation += 1
        remaining = 0
        failed = false
    }
}

internal fun mqttInboundRouteScope(topic: String): String = topic
