package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.internal.wire.MqttWireMessage
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Logical callbacks over three physical clients; no native packet ID escapes this adapter. */
internal class MqttPoolTransport(
    private val listener: Listener,
    private val classify: (String, ByteArray) -> Publication?,
    poolFactory: (MqttBrokerPool.Listener) -> MqttBrokerPool = { MqttBrokerPool(it) },
    private val now: () -> Long = { System.nanoTime() / 1_000_000 }
) : AutoCloseable {
    data class Publication(val peer: String, val messageId: String, val contentHash: String,
        val traffic: MqttMultipathPolicy.Traffic, val receiveTopics: Set<String>,
        val bootstrap: Boolean = false, val preferredBroker: String? = null,
        val authorizedPaths: Map<String, Long>? = null)
    interface Listener {
        fun onConnectionChanged(connected: Boolean) = Unit
        fun onSubscriptionsChanged() = Unit
        fun onPacket(ingress: MqttBrokerPool.Ingress, topic: String, payload: ByteArray) = Unit
        fun onPublished(token: IMqttDeliveryToken, accepted: Boolean) = Unit
        fun onMaintenanceFailure(error: Throwable) = Unit
    }
    private data class Path(var generation: Long = 0, var connected: Boolean = false,
                            val topics: MutableSet<String> = mutableSetOf())
    private data class Pending(val token: LogicalToken, val broker: String, val generation: Long, val notify: Boolean)
    val policy = MqttMultipathPolicy()
    private val lock = Any()
    private val paths = MqttBrokerCatalog.brokers.keys.associateWith { Path() }
    private val desired = mutableMapOf<String, Int>()
    private data class PendingSubscription(val token: LogicalToken, val intent: Map<String, Int>, val startedAt: Long)
    private val subscriptions = mutableMapOf<Int, PendingSubscription>()
    private val publications = mutableMapOf<String, Pending>()
    private val sequence = AtomicInteger()
    private val tieSeed = UUID.randomUUID().toString()
    private var closed = false
    private var started = false
    @Volatile var onTick: (() -> Unit)? = null
    private var lastTickError = Long.MIN_VALUE
    private val maintenance = ScheduledThreadPoolExecutor(1) { runnable ->
        Thread(runnable, "galaxyssi-mqtt-resume").apply { isDaemon = true }
    }.apply { removeOnCancelPolicy = true }
    private val pool = poolFactory(object : MqttBrokerPool.Listener {
        override fun onState(ingress: MqttBrokerPool.Ingress, state: String, reason: String) {
            val before: Boolean
            val after: Boolean
            synchronized(lock) {
                val path = paths.getValue(ingress.brokerId)
                if (ingress.generation < path.generation || (closed && state != "disconnected")) return
                before = paths.values.any { it.connected }
                if (state == "connected") {
                    if (ingress.generation == path.generation || !policy.connected(ingress.brokerId, ingress.generation)) return
                    path.generation = ingress.generation
                    path.connected = true
                    path.topics.clear()
                } else if (state == "disconnected") {
                    policy.disconnected(ingress.brokerId, path.generation)
                    path.generation = ingress.generation
                    path.connected = false
                    path.topics.clear()
                }
                after = paths.values.any { it.connected }
            }
            if (before != after) listener.onConnectionChanged(after)
            listener.onSubscriptionsChanged()
        }
        override fun onSubscribed(ingress: MqttBrokerPool.Ingress, topics: Set<String>, allAccepted: Boolean) {
            synchronized(lock) {
                val path = paths.getValue(ingress.brokerId)
                if (!path.connected || path.generation != ingress.generation || closed) return
                val active = topics intersect desired.keys
                policy.subscribed(ingress.brokerId, ingress.generation, active)
                path.topics.addAll(active)
            }
            completeSubscriptions()
            listener.onSubscriptionsChanged()
        }
        override fun onPacket(ingress: MqttBrokerPool.Ingress, topic: String, payload: ByteArray) =
            listener.onPacket(ingress, topic, payload)
        override fun onPublish(receipt: MqttBrokerPool.PublishReceipt) = onPhysicalPublished(receipt)
    })
    val delivery = MqttDeliveryDispatch(policy, pool::publish, { token, accepted ->
        (token as LogicalToken).finish(accepted)
        listener.onPublished(token, accepted)
    }, now)

    private fun onPhysicalPublished(receipt: MqttBrokerPool.PublishReceipt) {
        if (delivery.published(receipt)) return
        val pending = synchronized(lock) {
            val item = publications[receipt.attemptId] ?: return
            if (item.broker != receipt.physical.brokerId || item.generation != receipt.physical.generation) return
            publications.remove(receipt.attemptId)
            item
        }
        if (receipt.brokerAcked) policy.brokerAck(receipt.attemptId, pending.broker, pending.generation)
        policy.discardAttempt(receipt.attemptId)
        pending.token.finish(receipt.brokerAcked)
        if (pending.notify) listener.onPublished(pending.token, receipt.brokerAcked)
    }

    val isConnected: Boolean get() = synchronized(lock) { !closed && paths.values.any { it.connected } }

    fun start() {
        synchronized(lock) { check(!closed); if (started) return; started = true }
        pool.start()
        maintenance.scheduleWithFixedDelay({
            try { expireSubscriptions(); delivery.tick(); onTick?.invoke() } catch (error: Exception) {
                val at = now()
                if (lastTickError == Long.MIN_VALUE || at - lastTickError >= 30_000) {
                    lastTickError = at
                    listener.onMaintenanceFailure(error)
                }
            }
        }, 0, 250, TimeUnit.MILLISECONDS)
    }

    fun readyPathGenerations(topics: Set<String>): Map<String, Long> = synchronized(lock) {
        if (closed || topics.isEmpty()) emptyMap() else paths.filterValues {
            it.connected && it.topics.containsAll(topics)
        }.mapValues { it.value.generation }
    }

    fun snapshot() = pool.snapshot()

    fun subscribe(topics: Array<String>, qos: IntArray, context: Any?, callback: IMqttActionListener) {
        require(topics.size == qos.size && topics.isNotEmpty())
        val intent = topics.zip(qos.toList()).toMap()
        require(intent.all { (topic, level) -> topic.isNotEmpty() && topic.length <= 512 &&
            topic.none { it in "#+\u0000" } && level in 0..1 })
        val token = LogicalToken(nextId(), MqttMessage(), topics, context, callback)
        val superseded = synchronized(lock) {
            check(!closed && (desired.keys + intent.keys).size <= 65_536)
            val old = subscriptions.values.filter { it.intent == intent }
            old.forEach { subscriptions.remove(it.token.messageId) }
            check(subscriptions.size < MqttBrokerCatalog.MAX_PEER_ROUTES + 2)
            desired.putAll(intent)
            subscriptions[token.messageId] = PendingSubscription(token, intent, now())
            old
        }
        superseded.forEach { it.token.finish(false) }
        pool.subscribe(intent)
        completeSubscriptions()
    }

    private fun completeSubscriptions() {
        val complete = synchronized(lock) {
            subscriptions.values.filter { readyPathGenerations(it.intent.keys).isNotEmpty() }.also {
                it.forEach { pending -> subscriptions.remove(pending.token.messageId) }
            }
        }
        complete.forEach { it.token.finish(true) }
    }

    private fun expireSubscriptions() {
        val expired = synchronized(lock) {
            subscriptions.values.filter { now() - it.startedAt >= 15_000 }.also {
                it.forEach { pending -> subscriptions.remove(pending.token.messageId) }
            }
        }
        expired.forEach { it.token.finish(false) }
    }

    fun unsubscribe(topics: Array<String>, context: Any?, callback: IMqttActionListener) {
        val removed = topics.toSet()
        val cancelled = synchronized(lock) {
            removed.forEach(desired::remove)
            paths.values.forEach { it.topics.removeAll(removed) }
            subscriptions.values.filter { it.intent.keys.any(removed::contains) }.also {
                it.forEach { pending -> subscriptions.remove(pending.token.messageId) }
            }
        }
        policy.unsubscribe(removed)
        pool.unsubscribe(removed)
        cancelled.forEach { it.token.finish(false) }
        LogicalToken(nextId(), MqttMessage(), topics, context, callback).finish(true)
    }

    fun publish(topic: String, message: MqttMessage, context: Any? = null, callback: IMqttActionListener? = null,
                publication: Publication? = null): IMqttDeliveryToken {
        require(message.qos == 1 && !message.isRetained)
        val payload = message.payload
        val size = mqttPublishPacketBytes(topic, payload.size)
        require(size <= MqttBrokerCatalog.PACKET_BYTES)
        val descriptor = publication ?: classify(topic, payload) ?: throw MqttException(MqttException.REASON_CODE_CLIENT_NOT_CONNECTED.toInt())
        val token = LogicalToken(nextId(), message, arrayOf(topic), context, callback)
        val at = now()
        val choices = if (descriptor.bootstrap) readyPathGenerations(descriptor.receiveTopics).entries
            .sortedWith(compareBy<Map.Entry<String, Long>> { it.key != descriptor.preferredBroker }
                .thenBy { MqttRouteAdvertisement.sha256("$tieSeed:${descriptor.messageId}:${it.key}") })
            .map { it.key to it.value }
        else policy.plan(descriptor.peer, descriptor.messageId, descriptor.traffic, size.toInt(),
            descriptor.receiveTopics, at, descriptor.preferredBroker).filter { it.delayMs == 0L }
            .filter { descriptor.authorizedPaths == null || descriptor.authorizedPaths[it.brokerId] == it.generation }
            .map { it.brokerId to it.generation }
        for ((broker, generation) in choices) {
            val attempt = UUID.randomUUID().toString()
            if (!policy.reserve(attempt, MqttMultipathPolicy.Attempt(descriptor.peer, descriptor.messageId,
                    descriptor.contentHash, broker, generation, size.toInt(), descriptor.traffic, at))) continue
            synchronized(lock) { publications[attempt] = Pending(token, broker, generation, !descriptor.bootstrap) }
            if (pool.publish(broker, generation, topic, payload, attempt) != null) return token
            synchronized(lock) { publications.remove(attempt) }
            policy.discardAttempt(attempt)
        }
        throw MqttException(MqttException.REASON_CODE_CLIENT_NOT_CONNECTED.toInt())
    }

    fun repair() { pool.refreshSubscriptions(); pool.repairStalledPublishes() }
    fun publishDelivery(topic: String, descriptor: MqttDeliveryDispatch.Delivery, context: Any? = null,
                        callback: IMqttActionListener? = null): IMqttDeliveryToken {
        val token = LogicalToken(nextId(), MqttMessage().apply { qos = 1 }, arrayOf(topic), context, callback)
        return delivery.submit(topic, descriptor, token)
    }
    fun networkAvailable(networkKey: String = "available") { policy.setNetwork(networkKey); pool.networkAvailable() }
    fun networkUnavailable() { pool.networkUnavailable() }
    private fun nextId(): Int = sequence.incrementAndGet().also { check(it > 0) { "Logical MQTT token space exhausted" } }

    override fun close() {
        synchronized(lock) { if (closed) return; closed = true }
        maintenance.shutdownNow()
        delivery.close()
        pool.close()
        val cancelled = synchronized(lock) { subscriptions.values.toList().also { subscriptions.clear() } }
        cancelled.forEach { it.token.finish(false) }
    }

    private class LogicalToken(private val id: Int, private val message: MqttMessage,
        private val topics: Array<String>, private var context: Any?, private var callback: IMqttActionListener?
    ) : IMqttDeliveryToken {
        private val done = CountDownLatch(1)
        @Volatile private var error: MqttException? = null
        @Synchronized fun finish(accepted: Boolean) {
            if (done.count == 0L) return
            if (!accepted) error = MqttException(MqttException.REASON_CODE_CONNECTION_LOST.toInt())
            done.countDown()
            runCatching { if (accepted) callback?.onSuccess(this) else callback?.onFailure(this, error) }
        }
        override fun getMessageId() = id
        override fun getMessage() = message
        override fun getTopics() = topics
        override fun getUserContext() = context
        override fun setUserContext(value: Any?) { context = value }
        override fun getActionCallback() = callback
        override fun setActionCallback(value: IMqttActionListener?) { callback = value }
        override fun getException() = error
        override fun isComplete() = done.count == 0L && error == null
        override fun getGrantedQos() = IntArray(topics.size) { if (error == null) 1 else 128 }
        override fun getClient(): IMqttAsyncClient? = null
        override fun getSessionPresent() = false
        override fun getResponse(): MqttWireMessage? = null
        override fun waitForCompletion() { done.await(); error?.let { throw it } }
        override fun waitForCompletion(timeout: Long) {
            if (timeout <= 0) { waitForCompletion(); return }
            if (!done.await(timeout, TimeUnit.MILLISECONDS)) throw MqttException(MqttException.REASON_CODE_CLIENT_TIMEOUT.toInt())
            error?.let { throw it }
        }
    }
}
