package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.IMqttActionListener
import org.eclipse.paho.client.mqttv3.IMqttAsyncClient
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.IMqttToken
import org.eclipse.paho.client.mqttv3.MqttAsyncClient
import org.eclipse.paho.client.mqttv3.MqttCallbackExtended
import org.eclipse.paho.client.mqttv3.MqttConnectOptions
import org.eclipse.paho.client.mqttv3.MqttMessage
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import java.util.UUID
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

internal fun mqttPublishPacketBytes(topic: String, payloadBytes: Int): Long {
    val remaining = 2L + topic.toByteArray(Charsets.UTF_8).size + 2L + payloadBytes
    var value = remaining
    var encodedLengthBytes = 1
    while (value >= 128) { encodedLengthBytes += 1; value /= 128 }
    return 1L + encodedLengthBytes + remaining
}

/** One application-scoped pool. MQTT acknowledgements are physical receipts, never delivery claims. */
internal class MqttBrokerPool(
    private val listener: Listener,
    private val clientFactory: (String, MqttBrokerCatalog.Endpoint) -> IMqttAsyncClient = { _, endpoint ->
        MqttAsyncClient(endpoint.serverUri, UUID.randomUUID().toString().replace("-", "").take(22), MemoryPersistence())
    },
    private val now: () -> Long = { System.nanoTime() / 1_000_000 }
) : AutoCloseable {
    data class Ingress(val brokerId: String, val generation: Long, val receivedAt: Long)
    data class PublishReceipt(val logicalId: Long, val physical: MqttMultipathPolicy.PhysicalKey,
                              val attemptId: String, val brokerAcked: Boolean)
    interface Listener {
        fun onState(ingress: Ingress, state: String, reason: String) = Unit
        fun onSubscribed(ingress: Ingress, topics: Set<String>, allAccepted: Boolean) = Unit
        fun onPacket(ingress: Ingress, topic: String, payload: ByteArray) = Unit
        fun onPublish(receipt: PublishReceipt) = Unit
    }
    enum class PathState { DISCONNECTED, CONNECTING, SUBSCRIBING, RECEIVE_READY, RECOVERING, NETWORK_UNAVAILABLE }
    data class PathSnapshot(val generation: Long, val connected: Boolean, val activeSubscriptions: Int,
                            val pendingSubscriptions: Int, val pendingPublishes: Int, val lastError: String,
                            val state: PathState, val reconnectAttempts: Long)
    private data class PendingPublish(val logicalId: Long, val attemptId: String, val startedAt: Long, var packetId: Int = 0)
    private class Path(val brokerId: String) {
        val lock = Any()
        var generation = 0L
        var client: IMqttAsyncClient? = null
        var connected = false
        var connecting = false
        var retryScheduled = false
        var failures = 0
        var connectedAt = 0L
        var lastError = ""
        val activeTopics = mutableSetOf<String>()
        val pendingTopics = mutableMapOf<String, Long>()
        val publications = mutableMapOf<Long, PendingPublish>()
    }
    private val paths = MqttBrokerCatalog.brokers.keys.associateWith { Path(it) }
    private val desiredLock = Any()
    private val desired = mutableMapOf<String, Int>()
    private val executor = ScheduledThreadPoolExecutor(3) { runnable ->
        Thread(runnable, "galaxyssi-mqtt-connection").apply { isDaemon = true }
    }.apply { removeOnCancelPolicy = true }
    private val started = AtomicBoolean()
    private val closed = AtomicBoolean()
    private val networkPresent = AtomicBoolean(true)
    private val sequence = AtomicLong()

    private inline fun emit(callback: () -> Unit) { runCatching(callback) }
    private fun ingress(path: Path, generation: Long) = Ingress(path.brokerId, generation, now())
    private fun current(path: Path, client: IMqttAsyncClient, generation: Long): Boolean =
        !closed.get() && path.client === client && path.generation == generation

    fun start() {
        check(!closed.get()) { "Broker pool is closed" }
        if (!started.compareAndSet(false, true)) return
        paths.values.shuffled().forEach { path -> executor.execute { connect(path) } }
        executor.scheduleWithFixedDelay({ refreshSubscriptions() }, 10, 10, TimeUnit.SECONDS)
    }

    private fun connect(path: Path) {
        val generation = synchronized(path.lock) {
            path.retryScheduled = false
            if (closed.get() || !networkPresent.get() || path.connected || path.connecting) return
            path.connecting = true
            ++path.generation
        }
        emit { listener.onState(ingress(path, generation), "connecting", "") }
        var client: IMqttAsyncClient? = null
        try {
            client = clientFactory(path.brokerId, MqttBrokerCatalog.brokers.getValue(path.brokerId))
            synchronized(path.lock) {
                if (closed.get() || !networkPresent.get() || path.generation != generation) {
                    client.close()
                    return
                }
                path.client = client
            }
            bind(path, client, generation)
            val options = MqttConnectOptions().apply {
                isAutomaticReconnect = false
                isCleanSession = true
                keepAliveInterval = MqttBrokerCatalog.KEEPALIVE_SECONDS
                connectionTimeout = 10
                maxInflight = MqttBrokerCatalog.INFLIGHT_PACKETS
                isHttpsHostnameVerificationEnabled = true
            }
            client.connect(options, null, object : IMqttActionListener {
                override fun onSuccess(asyncActionToken: IMqttToken?) = Unit
                override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) {
                    lost(path, client, generation, exception?.javaClass?.simpleName ?: "connect_failed")
                }
            })
        } catch (error: Exception) {
            lost(path, client, generation, error.javaClass.simpleName)
        }
    }

    private fun bind(path: Path, client: IMqttAsyncClient, generation: Long) {
        client.setCallback(object : MqttCallbackExtended {
            override fun connectComplete(reconnect: Boolean, serverURI: String?) {
                val stale: Boolean
                synchronized(path.lock) {
                    stale = !current(path, client, generation)
                    if (!stale) {
                        path.connected = true
                        path.connecting = false
                        path.lastError = ""
                        path.connectedAt = now()
                    }
                }
                if (stale) { executorCleanup(client); return }
                emit { listener.onState(ingress(path, generation), "connected", "") }
                subscribePath(path)
            }
            override fun connectionLost(cause: Throwable?) {
                lost(path, client, generation, cause?.javaClass?.simpleName ?: "connection_lost")
            }
            override fun messageArrived(topic: String?, message: MqttMessage?) {
                val payload = message?.payload ?: return
                val accepted = synchronized(path.lock) {
                    current(path, client, generation) && path.connected && topic in path.activeTopics
                }
                if (!accepted || payload.isEmpty() ||
                    mqttPublishPacketBytes(topic.orEmpty(), payload.size) > MqttBrokerCatalog.PACKET_BYTES) return
                emit { listener.onPacket(ingress(path, generation), requireNotNull(topic), payload) }
            }
            override fun deliveryComplete(token: IMqttDeliveryToken?) = Unit
        })
    }

    private fun lost(path: Path, client: IMqttAsyncClient?, generation: Long, reason: String) {
        val pending: List<PendingPublish>
        synchronized(path.lock) {
            if (path.client !== client || path.generation != generation) return
            if (path.connected && now() - path.connectedAt >= 60_000) path.failures = 0
            path.connecting = false
            path.connected = false
            path.activeTopics.clear()
            path.pendingTopics.clear()
            path.lastError = reason
            pending = path.publications.values.toList()
            path.publications.clear()
            path.client = null
        }
        pending.forEach { emit { listener.onPublish(PublishReceipt(it.logicalId,
            MqttMultipathPolicy.PhysicalKey(path.brokerId, generation, it.packetId), it.attemptId, false)) } }
        emit { listener.onState(ingress(path, generation), "disconnected", reason) }
        if (client != null) executorCleanup(client)
        synchronized(path.lock) {
            if (closed.get() || !networkPresent.get() || path.retryScheduled) return
            path.retryScheduled = true
            val ceiling = (1000L shl path.failures.coerceAtMost(5)).coerceAtMost(30_000)
            path.failures = (path.failures + 1).coerceAtMost(5)
            val delay = kotlin.random.Random.nextLong(ceiling / 2, ceiling + 1)
            executor.schedule({ connect(path) }, delay, TimeUnit.MILLISECONDS)
        }
    }

    private fun executorCleanup(client: IMqttAsyncClient) {
        if (closed.get()) {
            disposeClient(client)
        } else {
            runCatching { executor.execute { disposeClient(client) } }
        }
    }

    private fun disposeClient(client: IMqttAsyncClient) {
        // Paho interprets a zero completion timeout as an unbounded wait.
        runCatching { client.disconnectForcibly(0, 500) }
        runCatching { client.close() }
    }

    fun subscribe(topics: Map<String, Int>) {
        require(topics.all { (topic, qos) -> topic.isNotEmpty() && topic.length <= 512 &&
            topic.none { it == '#' || it == '+' || it == '\u0000' } && qos in 0..1 })
        synchronized(desiredLock) {
            require((desired.keys + topics.keys).size <= 65_536)
            desired.putAll(topics)
        }
        refreshSubscriptions()
    }

    fun refreshSubscriptions() {
        if (closed.get()) return
        paths.values.forEach(::subscribePath)
    }

    private fun subscribePath(path: Path) {
        val expected = synchronized(desiredLock) { desired.toMap() }
        val client: IMqttAsyncClient
        val generation: Long
        val missing: List<String>
        synchronized(path.lock) {
            if (closed.get() || !path.connected) return
            client = path.client ?: return
            generation = path.generation
            path.pendingTopics.entries.removeAll { now() - it.value > 10_000 }
            missing = (expected.keys - path.activeTopics - path.pendingTopics.keys).sorted()
        }
        missing.chunked(128).forEach { batch ->
            val topics = synchronized(path.lock) {
                if (!current(path, client, generation) || !path.connected) return
                batch.filterNot(path.pendingTopics::containsKey).also { pending ->
                    pending.forEach { path.pendingTopics[it] = now() }
                }
            }
            if (topics.isEmpty()) return@forEach
            fun finish(token: IMqttToken?, succeeded: Boolean) {
                val stillDesired = synchronized(desiredLock) { desired.keys.toSet() }
                val active: Set<String>
                synchronized(path.lock) {
                    if (!current(path, client, generation) || !path.connected) return
                    topics.forEach(path.pendingTopics::remove)
                    val grants = token?.grantedQos ?: intArrayOf()
                    active = topics.filterIndexed { index, topic -> succeeded &&
                        grants.getOrNull(index)?.let { it in 0..1 } == true && topic in stillDesired }.toSet()
                    path.activeTopics.addAll(active)
                }
                emit { listener.onSubscribed(ingress(path, generation), active, active.size == topics.size) }
            }
            try {
                client.subscribe(topics.toTypedArray(), topics.map { expected.getValue(it) }.toIntArray(), null,
                    object : IMqttActionListener {
                        override fun onSuccess(asyncActionToken: IMqttToken?) { finish(asyncActionToken, true) }
                        override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) { finish(null, false) }
                    })
            } catch (_: Exception) { finish(null, false) }
        }
    }

    fun unsubscribe(topics: Set<String>) {
        synchronized(desiredLock) { topics.forEach(desired::remove) }
        paths.values.forEach { path ->
            synchronized(path.lock) {
                path.activeTopics.removeAll(topics)
                topics.forEach(path.pendingTopics::remove)
                if (path.connected && topics.isNotEmpty()) runCatching { path.client?.unsubscribe(topics.toTypedArray()) }
            }
        }
    }

    fun publish(broker: String, generation: Long, topic: String, payload: ByteArray, attemptId: String): Long? {
        if (attemptId.isBlank() || topic.isEmpty() || topic.any { it == '#' || it == '+' || it == '\u0000' } ||
            topic.toByteArray(Charsets.UTF_8).size > 65535 || payload.isEmpty() ||
            mqttPublishPacketBytes(topic, payload.size) > MqttBrokerCatalog.PACKET_BYTES) return null
        val path = paths[broker] ?: return null
        val logicalId = sequence.incrementAndGet()
        val client: IMqttAsyncClient
        val pending = PendingPublish(logicalId, attemptId, now())
        synchronized(path.lock) {
            client = path.client ?: return null
            if (!current(path, client, generation) || !path.connected ||
                path.publications.size >= MqttBrokerCatalog.INFLIGHT_PACKETS) return null
            path.publications[logicalId] = pending
        }
        fun finish(token: IMqttToken?, accepted: Boolean) {
            synchronized(path.lock) {
                if (!current(path, client, generation) || path.publications.remove(logicalId) == null) return
            }
            emit { listener.onPublish(PublishReceipt(logicalId,
                MqttMultipathPolicy.PhysicalKey(broker, generation, token?.messageId ?: pending.packetId), attemptId, accepted)) }
        }
        try {
            val message = MqttMessage(payload).apply { qos = 1; isRetained = false }
            val token = client.publish(topic, message, attemptId, object : IMqttActionListener {
                override fun onSuccess(asyncActionToken: IMqttToken?) { finish(asyncActionToken, true) }
                override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) { finish(asyncActionToken, false) }
            })
            synchronized(path.lock) { pending.packetId = token.messageId }
        } catch (_: Exception) {
            synchronized(path.lock) { path.publications.remove(logicalId) }
            return null
        }
        return logicalId
    }

    fun snapshot(): Map<String, PathSnapshot> {
        val expected = synchronized(desiredLock) { desired.keys.toSet() }
        return paths.mapValues { (_, path) -> synchronized(path.lock) {
            // Local subscription readiness is not proof of authenticated peer delivery.
            val state = when {
                closed.get() -> PathState.DISCONNECTED
                !networkPresent.get() -> PathState.NETWORK_UNAVAILABLE
                path.connecting -> PathState.CONNECTING
                path.connected && expected.isNotEmpty() && path.activeTopics.containsAll(expected) -> PathState.RECEIVE_READY
                path.connected -> PathState.SUBSCRIBING
                path.retryScheduled -> PathState.RECOVERING
                else -> PathState.DISCONNECTED
            }
            PathSnapshot(path.generation, path.connected, path.activeTopics.size, path.pendingTopics.size,
                path.publications.size, path.lastError, state, (path.generation - 1).coerceAtLeast(0))
        } }
    }

    fun networkAvailable() {
        if (closed.get() || networkPresent.getAndSet(true)) return
        paths.values.forEach { path -> executor.execute { connect(path) } }
    }

    fun networkUnavailable() {
        if (closed.get() || !networkPresent.getAndSet(false)) return
        paths.values.forEach { path ->
            val old = synchronized(path.lock) { path.client to path.generation }
            lost(path, old.first, old.second, "network_unavailable")
        }
    }

    fun repairStalledPublishes(timeoutMs: Long = 30_000) {
        if (closed.get()) return
        paths.values.forEach { path ->
            val stalled = synchronized(path.lock) {
                if (path.publications.values.any { now() - it.startedAt >= timeoutMs })
                    path.client?.let { it to path.generation } else null
            }
            stalled?.let { lost(path, it.first, it.second, "publish_timeout") }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        paths.values.forEach { path ->
            val current = synchronized(path.lock) { path.client to path.generation }
            lost(path, current.first, current.second, "closed")
        }
        executor.shutdownNow()
    }
}
