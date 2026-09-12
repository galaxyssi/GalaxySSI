package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.MqttException
import java.util.Locale
import java.util.UUID

/** Bounded physical copies. The existing durable outbox, not this scheduler, owns restart/retry. */
internal class MqttDeliveryDispatch(
    private val policy: MqttMultipathPolicy,
    private val publish: (String, Long, String, ByteArray, String) -> Long?,
    private val completed: (IMqttDeliveryToken, Boolean) -> Unit,
    private val now: () -> Long
) : AutoCloseable {
    data class Delivery(val peer: String, val message: MqttDeliveryEnvelope.Message, val receiveTopics: Set<String>,
        val encodeAttempt: (MqttDeliveryEnvelope.Frame) -> ByteArray,
        val authorized: (String, Long) -> Boolean, val sizeBound: Int)
    private data class Scheduled(val due: Long, val plan: MqttMultipathPolicy.Dispatch)
    private class Job(val topic: String, val delivery: Delivery, val token: IMqttDeliveryToken,
        val started: Long, val scheduled: MutableList<Scheduled>) {
        val key = delivery.peer to delivery.message
        val attempts = mutableSetOf<String>()
        var accepted = false
        var publishing = false
        var finished = false
    }
    private data class Sent(val job: Job, val frame: MqttDeliveryEnvelope.Frame, var pending: Boolean = true)
    data class Diagnostics(val messages: Int, val trackedAttempts: Int, val queuedCopies: Int, val bufferedBytes: Long)
    private val lock = Any()
    private val jobs = linkedMapOf<Pair<String, MqttDeliveryEnvelope.Message>, Job>()
    private val sent = mutableMapOf<String, Sent>()
    private var closed = false
    private fun traffic(message: MqttDeliveryEnvelope.Message) = MqttMultipathPolicy.Traffic.valueOf(message.traffic.uppercase(Locale.ROOT))
    private fun priority(job: Job) = job.delivery.message.traffic in setOf("control", "receipt", "final")
    private fun disconnected(): Nothing = throw MqttException(MqttException.REASON_CODE_CLIENT_NOT_CONNECTED.toInt())

    fun submit(topic: String, delivery: Delivery, token: IMqttDeliveryToken): IMqttDeliveryToken {
        val at = now()
        val plans = policy.plan(delivery.peer, delivery.message.messageId, traffic(delivery.message),
            delivery.sizeBound, delivery.receiveTopics, at)
        val job: Job
        synchronized(lock) {
            val key = delivery.peer to delivery.message
            jobs[key]?.let { if (expired(it, at)) retire(it) }
            jobs[key]?.let { return it.token }
            if (closed || plans.isEmpty()) disconnected()
            val reserved = delivery.message.traffic !in setOf("control", "receipt", "final")
            if (jobs.size >= MqttBrokerCatalog.MAX_ATTEMPTS - (if (reserved) MqttBrokerCatalog.CONTROL_RESERVE else 0) ||
                jobs.values.sumOf { it.delivery.sizeBound.toLong() } + delivery.sizeBound > MqttBrokerCatalog.INFLIGHT_BYTES -
                (if (reserved) MqttBrokerCatalog.CONTROL_RESERVE * MqttBrokerCatalog.SMALL_PACKET_BYTES else 0)) {
                throw MqttException(MqttException.REASON_CODE_MAX_INFLIGHT.toInt())
            }
            job = Job(topic, delivery, token, at, plans.map { Scheduled(at + it.delayMs, it) }.toMutableList())
            jobs[key] = job
        }
        try { pump(job, at) } catch (error: Exception) {
            synchronized(lock) { if (job.attempts.isEmpty()) jobs.remove(job.key) }
            throw error
        }
        synchronized(lock) {
            if (job.attempts.isEmpty() && !job.accepted) {
                job.scheduled.clear()
                jobs.remove(job.key)
                disconnected()
            }
        }
        return token
    }

    private fun finish(job: Job, accepted: Boolean) {
        synchronized(lock) {
            if (job.finished) return
            job.finished = true
        }
        completed(job.token, accepted)
    }

    private fun pump(job: Job, at: Long) {
        synchronized(lock) {
            if (closed || job.accepted || job.publishing || jobs[job.key] !== job) return
            job.publishing = true
        }
        try {
            while (true) {
                val plan = synchronized(lock) {
                    if (closed || job.accepted || job.scheduled.isEmpty() || job.scheduled[0].due > at) return
                    job.scheduled.removeAt(0).plan
                }
                val delivery = job.delivery
                val message = delivery.message
                val allowed = policy.plan(delivery.peer, message.messageId, traffic(message), delivery.sizeBound,
                    delivery.receiveTopics, now())
                if (allowed.none { it.brokerId == plan.brokerId && it.generation == plan.generation } ||
                    !delivery.authorized(plan.brokerId, plan.generation)) continue
                val attemptId = UUID.randomUUID().toString().replace("-", "")
                val frame = MqttDeliveryEnvelope.Frame(message, MqttDeliveryEnvelope.Attempt(attemptId, plan.brokerId, plan.generation))
                val encoded = delivery.encodeAttempt(frame)
                val size = mqttPublishPacketBytes(job.topic, encoded.size)
                require(size <= delivery.sizeBound) { "Delivery exceeds final encoded packet bound" }
                val admitted = synchronized(lock) {
                    if (closed || job.accepted || jobs[job.key] !== job) return
                    if (!policy.reserve(attemptId, MqttMultipathPolicy.Attempt(delivery.peer, message.messageId,
                            message.contentHash, plan.brokerId, plan.generation, size.toInt(), traffic(message), now()))) {
                        job.scheduled.add(0, Scheduled(at + 250, plan))
                        false
                    } else {
                        job.attempts.add(attemptId)
                        sent[attemptId] = Sent(job, frame)
                        true
                    }
                }
                if (!admitted) break
                val result = runCatching { publish(plan.brokerId, plan.generation, job.topic, encoded, attemptId) }.getOrNull()
                if (result == null) synchronized(lock) {
                    sent.remove(attemptId)
                    job.attempts.remove(attemptId)
                    policy.discardAttempt(attemptId)
                    expedite(job, at)
                }
            }
        } catch (error: Exception) {
            synchronized(lock) { job.scheduled.clear() }
            throw error
        } finally {
            val failed = synchronized(lock) {
                job.publishing = false
                job.scheduled.isEmpty() && job.attempts.none { sent[it]?.pending == true }
            }
            if (failed) finish(job, false)
        }
    }

    private fun expedite(job: Job, at: Long) {
        for (index in job.scheduled.indices) job.scheduled[index] = job.scheduled[index].copy(due = at)
    }

    fun published(receipt: MqttBrokerPool.PublishReceipt): Boolean {
        val job: Job
        val failed: Boolean
        synchronized(lock) {
            val item = sent[receipt.attemptId] ?: return false
            val attempt = item.frame.attempt
            if (attempt.brokerId != receipt.physical.brokerId || attempt.generation != receipt.physical.generation) return true
            if (!item.pending) return true
            item.pending = false
            job = item.job
            if (receipt.brokerAcked) policy.brokerAck(attempt.attemptId, attempt.brokerId, attempt.generation)
            else {
                policy.discardAttempt(attempt.attemptId)
                sent.remove(attempt.attemptId)
                job.attempts.remove(attempt.attemptId)
                expedite(job, now())
            }
            if (job.accepted || closed) {
                sent.remove(attempt.attemptId)
                job.attempts.remove(attempt.attemptId)
                policy.discardAttempt(attempt.attemptId)
                if (job.attempts.isEmpty()) jobs.remove(job.key)
            }
            failed = !job.publishing && job.scheduled.isEmpty() && job.attempts.none { sent[it]?.pending == true }
        }
        if (receipt.brokerAcked) finish(job, true) else if (failed) finish(job, false)
        return true
    }

    /** Only after current pair AEAD validation. A failed durable commit leaves retries live. */
    fun acceptVerifiedReceipt(peer: String, frame: MqttDeliveryEnvelope.Frame, commit: () -> Unit): Boolean {
        val job = synchronized(lock) {
            val item = sent[frame.attempt.attemptId]
            if (closed || item == null || item.frame != frame || item.job.delivery.peer != peer || item.job.accepted) return false
            item.job
        }
        commit()
        synchronized(lock) {
            val accepted = policy.acceptVerifiedReceipt(peer, frame.message.messageId, frame.message.contentHash,
                frame.attempt.attemptId, now())
            if (accepted.isEmpty()) return false
            job.accepted = true
            job.scheduled.clear()
            accepted.forEach { key ->
                sent[key]?.takeIf { !it.pending }?.let { sent.remove(key); it.job.attempts.remove(key) }
            }
            return true
        }
    }

    /** Stored-message ACKs without attempt attribution cannot supply path RTT samples. */
    fun acceptVerifiedMessage(peer: String, messageId: String, contentHash: String) = synchronized(lock) {
        if (closed) return@synchronized
        policy.acceptVerifiedMessage(peer, messageId, contentHash)
        jobs.values.filter { it.delivery.peer == peer && it.delivery.message.messageId == messageId &&
            it.delivery.message.contentHash == contentHash }.forEach { it.accepted = true; it.scheduled.clear() }
    }

    fun tick() {
        val at = now()
        val selected = synchronized(lock) {
            val due = jobs.values.filter { expired(it, at) || it.accepted || it.scheduled.firstOrNull()?.due?.let { due -> due <= at } == true }
            val (urgent, ordinary) = due.partition(::priority)
            val batch = (urgent.take(12) + ordinary.take(4)).toMutableList()
            batch.addAll((urgent.drop(12) + ordinary.drop(4)).take(16 - batch.size))
            batch.forEach { jobs.remove(it.key); jobs[it.key] = it }
            batch
        }
        for (job in selected) {
            val retired = synchronized(lock) {
                if (expired(job, at) || job.accepted) { retire(job); true } else false
            }
            if (!retired) pump(job, at)
        }
    }

    private fun expired(job: Job, at: Long) = at - job.started >= MqttBrokerCatalog.ATTEMPT_OBSERVATION_MS
    private fun retire(job: Job) {
        if (job.publishing) return
        job.scheduled.clear()
        job.attempts.toList().forEach { key ->
            sent[key]?.takeIf { !it.pending }?.let { sent.remove(key); policy.discardAttempt(key); job.attempts.remove(key) }
        }
        if (job.attempts.isEmpty()) jobs.remove(job.key)
    }

    override fun close() {
        val pending = synchronized(lock) { closed = true; jobs.values.toList().also { it.forEach(::retire) } }
        pending.forEach { finish(it, false) }
    }

    fun diagnostics() = synchronized(lock) {
        Diagnostics(jobs.size, sent.size, jobs.values.sumOf { it.scheduled.size }, jobs.values.sumOf { it.delivery.sizeBound.toLong() })
    }
}
