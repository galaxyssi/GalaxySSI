package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

class MqttBrokerPoolTest {
    private val clients = ConcurrentHashMap<String, CopyOnWriteArrayList<Fake>>()
    private val receipts = CopyOnWriteArrayList<MqttBrokerPool.PublishReceipt>()
    private val subacks = CopyOnWriteArrayList<Pair<String, Set<String>>>()
    private val packets = CopyOnWriteArrayList<Pair<MqttBrokerPool.Ingress, ByteArray>>()
    private var reject = emptySet<String>()
    private var delayed = emptySet<String>()
    private var early = false
    private var autoSuback = true
    private val clock = AtomicLong()
    private val pool = MqttBrokerPool(object : MqttBrokerPool.Listener {
        override fun onSubscribed(ingress: MqttBrokerPool.Ingress, topics: Set<String>, allAccepted: Boolean) {
            subacks.add(ingress.brokerId to topics)
        }
        override fun onPublish(receipt: MqttBrokerPool.PublishReceipt) { receipts.add(receipt) }
        override fun onPacket(ingress: MqttBrokerPool.Ingress, topic: String, payload: ByteArray) {
            packets.add(ingress to payload)
        }
    }, { broker, endpoint ->
        Fake(broker, endpoint).also { clients.getOrPut(broker) { CopyOnWriteArrayList() }.add(it) }.proxy
    }, { clock.get() })

    private inner class Fake(val broker: String, val endpoint: MqttBrokerCatalog.Endpoint) {
        lateinit var callback: MqttCallbackExtended
        var options: MqttConnectOptions? = null
        var connected = false
        var closed = false
        var disconnectTimeout = -1L
        var mid = 1
        val published = CopyOnWriteArrayList<MqttMessage>()
        val publishListeners = ConcurrentHashMap<Int, Pair<IMqttActionListener, IMqttToken>>()
        val subscribeListeners = CopyOnWriteArrayList<Pair<IMqttActionListener, IMqttToken>>()
        val proxy = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IMqttAsyncClient::class.java)) { _, method, args ->
            when (method.name) {
                "setCallback" -> { callback = args[0] as MqttCallbackExtended; null }
                "isConnected" -> connected
                "getServerURI" -> endpoint.serverUri
                "getClientId" -> broker
                "connect" -> {
                    options = args[0] as MqttConnectOptions
                    val listener = args.last() as IMqttActionListener
                    if (broker in reject) listener.onFailure(null, IllegalStateException("refused"))
                    else if (broker !in delayed) completeConnect()
                    token(0)
                }
                "subscribe" -> {
                    val topics = args[0] as Array<*>
                    val listener = args.last() as IMqttActionListener
                    val token = token(100, IntArray(topics.size) { 1 })
                    subscribeListeners.add(listener to token)
                    if (autoSuback) listener.onSuccess(token)
                    token
                }
                "unsubscribe" -> token(200)
                "publish" -> {
                    val id = mid++
                    published.add(args[1] as MqttMessage)
                    val listener = args.last() as IMqttActionListener
                    val token = token(id)
                    publishListeners[id] = listener to token
                    if (early) listener.onSuccess(token)
                    token
                }
                "disconnectForcibly" -> { disconnectTimeout = args[1] as Long; connected = false; null }
                "disconnect" -> { connected = false; null }
                "close" -> { closed = true; null }
                "toString" -> "Fake($broker)"
                "hashCode" -> System.identityHashCode(this)
                "equals" -> false
                else -> null
            }
        } as IMqttAsyncClient
        fun completeConnect() { connected = true; callback.connectComplete(false, endpoint.serverUri) }
        fun ack(id: Int) { publishListeners.getValue(id).let { it.first.onSuccess(it.second) } }
        fun lose() { connected = false; callback.connectionLost(IllegalStateException("offline")) }
    }

    private fun token(mid: Int, grants: IntArray = intArrayOf(1)): IMqttDeliveryToken =
        Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IMqttDeliveryToken::class.java)) { _, method, _ ->
            when (method.name) {
                "getMessageId" -> mid
                "getGrantedQos" -> grants
                "isComplete" -> true
                else -> null
            }
        } as IMqttDeliveryToken

    private fun waitFor(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 3_000_000_000
        while (!condition() && System.nanoTime() < deadline) Thread.sleep(5)
        assertTrue("timed out waiting for independent MQTT path", condition())
    }
    private fun start() {
        pool.subscribe(mapOf("inbox" to 1))
        pool.start()
        waitFor { clients.size == 3 }
    }
    private fun ready() { start(); waitFor { subacks.size >= 3 } }
    private fun client(broker: String) = clients.getValue(broker).first()
    @After fun close() { pool.close() }

    @Test fun startsOnlyThreeConnectionsWithHostnameVerificationAndNoDefault() {
        ready()
        pool.start()
        assertEquals(3, clients.values.sumOf { it.size })
        clients.values.flatten().forEach { fake ->
            assertTrue(fake.endpoint.serverUri.startsWith("ssl://"))
            assertTrue(fake.options!!.isHttpsHostnameVerificationEnabled)
            assertFalse(fake.options!!.isAutomaticReconnect)
            assertEquals(30, fake.options!!.keepAliveInterval)
        }
        assertEquals(8886, client("mosquitto").endpoint.tlsPort)
    }

    @Test fun refusedOrDelayedEmqxDoesNotBlockOtherPaths() {
        reject = setOf("emqx")
        start()
        waitFor { subacks.size >= 2 }
        assertFalse(pool.snapshot().getValue("emqx").connected)
        assertTrue(pool.snapshot().getValue("hivemq").connected)
        assertTrue(pool.snapshot().getValue("mosquitto").connected)
    }

    @Test fun connectionCompletionIsNotSubscriptionReadiness() {
        autoSuback = false
        readyWithoutSuback()
        assertTrue(pool.snapshot().values.all { it.connected && it.activeSubscriptions == 0 })
    }
    private fun readyWithoutSuback() { start(); waitFor { clients.values.all { it.first().subscribeListeners.isNotEmpty() } } }

    @Test fun sameMqttPacketIdAcrossBrokersGetsDistinctLogicalIds() {
        ready()
        val ids = clients.keys.map { pool.publish(it, 1, "outbox", byteArrayOf(1), it) }
        assertEquals(3, ids.toSet().size)
        clients.keys.forEach { client(it).ack(1) }
        assertEquals(3, receipts.size)
        assertEquals(clients.keys, receipts.map { it.physical.brokerId }.toSet())
        assertEquals(setOf(1), receipts.map { it.physical.packetId }.toSet())
    }

    @Test fun earlyPublishAckIsEmittedExactlyOnce() {
        early = true
        ready()
        val id = pool.publish("hivemq", 1, "outbox", byteArrayOf(1), "a")
        assertEquals(id, receipts.single().logicalId)
        client("hivemq").ack(1)
        assertEquals(1, receipts.size)
    }

    @Test fun failedPathOnlyFailsItsOwnPendingCopies() {
        ready()
        clients.keys.forEach { pool.publish(it, 1, "outbox", byteArrayOf(1), it) }
        client("emqx").lose()
        assertEquals(listOf("emqx"), receipts.map { it.attemptId })
        assertFalse(receipts.single().brokerAcked)
        assertEquals(1, pool.snapshot().getValue("hivemq").pendingPublishes)
    }

    @Test fun staleCallbacksCannotCompleteNewGenerationPackets() {
        ready()
        val old = client("emqx")
        pool.publish("emqx", 1, "outbox", byteArrayOf(1), "old")
        old.lose()
        waitFor { clients.getValue("emqx").size == 2 && pool.snapshot().getValue("emqx").activeSubscriptions == 1 }
        pool.publish("emqx", 2, "outbox", byteArrayOf(2), "new")
        old.ack(1)
        assertEquals(1, receipts.size)
        clients.getValue("emqx")[1].ack(1)
        assertEquals("new", receipts.last().attemptId)
        assertEquals(2L, receipts.last().physical.generation)
    }

    @Test fun missingSubackCanBeRetriedWithoutResettingHealthyPaths() {
        autoSuback = false
        readyWithoutSuback()
        clock.set(11_000)
        pool.refreshSubscriptions()
        assertTrue(clients.values.all { it.first().subscribeListeners.size == 2 })
    }

    @Test fun removedTopicIsNotReactivatedByLateSuback() {
        autoSuback = false
        readyWithoutSuback()
        pool.unsubscribe(setOf("inbox"))
        client("emqx").subscribeListeners.first().let { it.first.onSuccess(it.second) }
        assertEquals(0, pool.snapshot().getValue("emqx").activeSubscriptions)
    }

    @Test fun ingressRequiresActiveTopicAndRetainsBrokerGeneration() {
        ready()
        val fake = client("mosquitto")
        fake.callback.messageArrived("unknown", MqttMessage(byteArrayOf(1)))
        fake.callback.messageArrived("inbox", MqttMessage(ByteArray(1_048_577)))
        fake.callback.messageArrived("inbox", MqttMessage(byteArrayOf(2)))
        assertEquals(1, packets.size)
        assertEquals("mosquitto", packets.single().first.brokerId)
    }

    @Test fun outboundIsQosOneNotRetainedAndBounded() {
        ready()
        val ids = (0 until 100).map { pool.publish("emqx", 1, "outbox", byteArrayOf(1), "$it") }
        assertEquals(12, ids.count { it != null })
        assertTrue(client("emqx").published.all { it.qos == 1 && !it.isRetained })
    }

    @Test fun rejectsWildcardSubscriptionAndStaleGenerationSend() {
        assertThrows(IllegalArgumentException::class.java) { pool.subscribe(mapOf("#" to 1)) }
        assertThrows(IllegalArgumentException::class.java) { pool.subscribe(mapOf("inbox/+" to 1)) }
        ready()
        assertNull(pool.publish("emqx", 2, "outbox", byteArrayOf(1), "a"))
    }

    @Test fun delayedConnectionAfterCloseIsDisposed() {
        delayed = setOf("emqx")
        start()
        waitFor { client("emqx").options != null }
        pool.close()
        client("emqx").completeConnect()
        assertTrue(client("emqx").closed)
        assertFalse(pool.snapshot().getValue("emqx").connected)
    }

    @Test fun packetLimitIncludesTopicAndMqttHeaders() {
        assertEquals(10L, mqttPublishPacketBytes("abc", 1))
        assertTrue(mqttPublishPacketBytes("abc", 1_048_576) > 1_048_576)
        ready()
        assertNull(pool.publish("emqx", 1, "outbox", ByteArray(1_048_576), "too-large"))
    }

    @Test fun shutdownNeverUsesPahosInfiniteCompletionTimeout() {
        ready()
        pool.close()
        assertTrue(clients.values.all { it.first().disconnectTimeout in 1..1_000 })
    }
}
