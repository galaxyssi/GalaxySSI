package com.galaxyssi.chat

import android.content.Context
import org.eclipse.paho.client.mqttv3.*
import org.json.JSONObject
import org.junit.Assert.*
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/** Real routing, AEAD and SQLite; only the physical MQTT sockets are controlled. */
internal class MqttChunkDeviceRig(context: Context, val routes: GalaxySSILinkProtocol.Routes) : AutoCloseable {
    data class Sent(val broker: String, val message: MqttMessage)
    val sent = CopyOnWriteArrayList<Sent>()
    private val physical = ConcurrentHashMap<String, Fake>()
    val binding = MqttPeerRoutes.Binding(GalaxySSILinkDeliveryStore.peerScope(routes), routes.localFingerprint,
        routes.remoteFingerprint, routes.linkSecret, routes.up, setOf(routes.up), routes.receiveWindow)
    private val database = AgentEncryptedDatabase(context, "test_link_atomic_chunk_route_${routes.clientRouteId}")
    private val state = MqttRouteState(database)
    val peers: MqttPeerRoutes
    private val poolTransport = MqttPoolTransport(object : MqttPoolTransport.Listener {}, { _, _ -> null }, poolFactory = { listener ->
        MqttBrokerPool(listener, { broker, endpoint -> Fake(broker, endpoint).also { physical[broker] = it }.proxy })
    })

    init {
        peers = MqttPeerRoutes(poolTransport, state, GalaxySSILinkProtocol::sealWirePacket)
        peers.replace(listOf(binding))
        poolTransport.subscribe(binding.receiveTopics.toTypedArray(), IntArray(binding.receiveTopics.size) { 1 }, null,
            object : IMqttActionListener {
                override fun onSuccess(token: IMqttToken?) = Unit
                override fun onFailure(token: IMqttToken?, error: Throwable?) = throw AssertionError(error)
            })
        poolTransport.start()
        await { poolTransport.readyPathGenerations(binding.receiveTopics).size == 3 }
        peers.maintenance()
        val local = sent.map { decode(it.message.payload) }.first { it.optString("type") == "link_resume" }
        val advertised = MqttRouteAdvertisement.parseVerified(local, binding.sender, binding.receiver, System.currentTimeMillis())
        val now = System.currentTimeMillis()
        val remote = MqttRouteAdvertisement(binding.receiver, binding.sender, 1, MqttChunkReceipts.newRequest(), now,
            now + MqttBrokerCatalog.RESUME_TTL_MS, MqttBrokerCatalog.brokers.keys, MqttBrokerCatalog.PACKET_BYTES)
        peers.handleVerified(binding.scope, JSONObject().put("type", "link_resume_ack").put("advertisement", remote.toWire())
            .put("acknowledged_resume_id", advertised.resumeId).put("acknowledged_route_epoch", advertised.epoch)
            .put("acknowledged_digest", advertised.digest()), ingress(), binding.identity)
        assertTrue(peers.ready(binding.scope))
        sent.clear()
    }

    fun decode(bytes: ByteArray) = JSONObject(GalaxySSILinkProtocol.openWirePacket(bytes, routes.linkSecret))
    fun ingress(broker: String = "hivemq") = MqttBrokerPool.Ingress(broker,
        poolTransport.snapshot().getValue(broker).generation, System.nanoTime() / 1_000_000)
    fun publish(packets: List<Pair<String, MqttPoolTransport.Publication>>) = packets.forEach { (wire, descriptor) ->
        poolTransport.publish(routes.up, MqttMessage(wire.toByteArray(Charsets.UTF_8)).apply { qos = 1 }, publication = descriptor)
    }
    fun await(condition: () -> Boolean) {
        val until = System.nanoTime() + 5_000_000_000L
        while (!condition() && System.nanoTime() < until) Thread.sleep(5)
        assertTrue("Chunk exchange readiness timed out", condition())
    }
    private fun token(grants: Int = 1): IMqttDeliveryToken = Proxy.newProxyInstance(javaClass.classLoader,
        arrayOf(IMqttDeliveryToken::class.java)) { _, method, _ -> when (method.name) {
            "getMessageId" -> 1; "isComplete" -> true; "getGrantedQos" -> IntArray(grants) { 1 }; else -> null
        } } as IMqttDeliveryToken
    private inner class Fake(val broker: String, endpoint: MqttBrokerCatalog.Endpoint) {
        lateinit var callback: MqttCallbackExtended
        var connected = false
        val proxy = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IMqttAsyncClient::class.java)) { _, method, args ->
            when (method.name) {
                "setCallback" -> { callback = args[0] as MqttCallbackExtended; null }
                "isConnected" -> connected
                "getServerURI" -> endpoint.serverUri
                "getClientId" -> broker
                "connect" -> { connected = true; callback.connectComplete(false, endpoint.serverUri); token() }
                "subscribe" -> token((args[0] as Array<*>).size).also { (args.last() as IMqttActionListener).onSuccess(it) }
                "publish" -> token().also {
                    sent.add(Sent(broker, args[1] as MqttMessage)); (args.last() as IMqttActionListener).onSuccess(it)
                }
                "unsubscribe" -> token()
                "disconnectForcibly", "disconnect", "close" -> { connected = false; null }
                else -> null
            }
        } as IMqttAsyncClient
    }
    override fun close() { poolTransport.close(); database.close() }
}
