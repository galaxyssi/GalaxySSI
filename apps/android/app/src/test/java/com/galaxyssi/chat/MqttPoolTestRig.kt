package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.*
import org.junit.Assert.assertTrue
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

internal class MqttPoolTestRig : AutoCloseable {
    val clock = AtomicLong(1_000)
    val wall = AtomicLong(1_000_000)
    var autoSuback = true
    var earlyAck = true
    var earlyFailure = false
    var rejected = emptySet<String>()
    var classifier: (String, ByteArray) -> MqttPoolTransport.Publication? = { _, _ -> null }
    val clients = ConcurrentHashMap<String, CopyOnWriteArrayList<Fake>>()
    val completed = CopyOnWriteArrayList<Pair<Int, Boolean>>()
    val connectionStates = CopyOnWriteArrayList<Boolean>()
    val subscriptionResults = CopyOnWriteArrayList<Boolean>()
    lateinit var pool: MqttBrokerPool
    val transport = MqttPoolTransport(object : MqttPoolTransport.Listener {
        override fun onConnectionChanged(connected: Boolean) { connectionStates.add(connected) }
        override fun onPublished(token: IMqttDeliveryToken, accepted: Boolean) { completed.add(token.messageId to accepted) }
    }, { topic, bytes -> classifier(topic, bytes) }, { listener ->
        MqttBrokerPool(listener, { broker, endpoint ->
            Fake(broker, endpoint).also { clients.getOrPut(broker) { CopyOnWriteArrayList() }.add(it) }.proxy
        }, clock::get).also { pool = it }
    }, clock::get)

    data class Sent(val topic: String, val message: MqttMessage, val token: IMqttDeliveryToken, val listener: IMqttActionListener)
    data class Subscription(val topics: List<String>, val listener: IMqttActionListener)
    inner class Fake(val broker: String, val endpoint: MqttBrokerCatalog.Endpoint) {
        lateinit var callback: MqttCallbackExtended
        var connected = false
        private var nextId = 0
        val sent = CopyOnWriteArrayList<Sent>()
        val subscriptions = CopyOnWriteArrayList<Subscription>()
        val proxy = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IMqttAsyncClient::class.java)) { _, method, args ->
            when (method.name) {
                "setCallback" -> { callback = args[0] as MqttCallbackExtended; null }
                "isConnected" -> connected
                "getServerURI" -> endpoint.serverUri
                "getClientId" -> broker
                "connect" -> {
                    if (broker in rejected) (args.last() as IMqttActionListener).onFailure(null, IllegalStateException("offline"))
                    else { connected = true; callback.connectComplete(false, endpoint.serverUri) }
                    token(0)
                }
                "subscribe" -> {
                    val topics = (args[0] as Array<*>).map { it as String }
                    val listener = args.last() as IMqttActionListener
                    subscriptions.add(Subscription(topics, listener))
                    val result = token(100, IntArray(topics.size) { 1 })
                    if (autoSuback) listener.onSuccess(result)
                    result
                }
                "unsubscribe" -> token(200)
                "publish" -> {
                    val result = token(++nextId)
                    val listener = args.last() as IMqttActionListener
                    sent.add(Sent(args[0] as String, args[1] as MqttMessage, result, listener))
                    if (earlyFailure) listener.onFailure(result, IllegalStateException("rejected"))
                    else if (earlyAck) listener.onSuccess(result)
                    result
                }
                "disconnectForcibly", "disconnect", "close" -> { connected = false; null }
                else -> null
            }
        } as IMqttAsyncClient
        fun grant(accepted: Set<String>) {
            subscriptions.forEach { sub ->
                sub.listener.onSuccess(token(100, sub.topics.map { if (it in accepted) 1 else 128 }.toIntArray()))
            }
        }
        fun lose() { connected = false; callback.connectionLost(IllegalStateException("offline")) }
    }

    fun token(mid: Int, grants: IntArray = intArrayOf(1)): IMqttDeliveryToken =
        Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IMqttDeliveryToken::class.java)) { _, method, _ ->
            when (method.name) { "getMessageId" -> mid; "getGrantedQos" -> grants; "isComplete" -> true; else -> null }
        } as IMqttDeliveryToken

    fun subscribe(topics: Set<String>) = transport.subscribe(topics.toTypedArray(), IntArray(topics.size) { 1 }, null,
        object : IMqttActionListener {
            override fun onSuccess(asyncActionToken: IMqttToken?) { subscriptionResults.add(true) }
            override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) { subscriptionResults.add(false) }
        })
    fun start(topics: Set<String> = setOf("inbox")) {
        subscribe(topics)
        transport.start()
        await { clients.size == 3 && clients.filterKeys { it !in rejected }.values.all { it.first().subscriptions.isNotEmpty() } }
        if (autoSuback) await { transport.readyPathGenerations(topics).size == 3 - rejected.size }
    }
    fun client(broker: String) = clients.getValue(broker).last()
    fun ingress(broker: String) = MqttBrokerPool.Ingress(broker, transport.snapshot().getValue(broker).generation, clock.get())
    fun descriptor(broker: String, bootstrap: Boolean = true, topics: Set<String> = setOf("inbox")) =
        MqttPoolTransport.Publication("peer", "message", "a".repeat(64), MqttMultipathPolicy.Traffic.CONTROL,
            topics, bootstrap = bootstrap, preferredBroker = broker)
    fun publish(broker: String, bootstrap: Boolean = true) = transport.publish("outbox",
        MqttMessage(byteArrayOf(1)).apply { qos = 1 }, publication = descriptor(broker, bootstrap))
    fun await(condition: () -> Boolean) {
        val until = System.nanoTime() + 4_000_000_000L
        while (!condition() && System.nanoTime() < until) Thread.sleep(5)
        assertTrue("MQTT test condition timed out", condition())
    }
    override fun close() { transport.close() }
}
