package com.galaxyssi.chat

import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Opt-in, at most one synthetic packet per public broker. Never a load test. */
@RunWith(AndroidJUnit4::class)
class MqttPublicPoolDeviceTest {
    @Test(timeout = 60_000) fun independentTlsPathsExchangeOneSmallPacketWithoutUserData() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("publicMqttSmoke") == "true")
        val topic = "galaxyssi-verification/${UUID.randomUUID()}"
        val bytes = "Synthetic MQTT pool verification ${UUID.randomUUID()}".toByteArray()
        val started = SystemClock.elapsedRealtime()
        val ready = ConcurrentHashMap<String, Long>()
        val sent = mutableMapOf<String, Long>()
        val received = ConcurrentHashMap<String, Long>()
        val connected = ConcurrentHashMap<String, Long>()
        val reports = JSONObject()
        val pool = MqttBrokerPool(object : MqttBrokerPool.Listener {
            override fun onState(ingress: MqttBrokerPool.Ingress, state: String, reason: String) {
                if (state == "connected") connected.putIfAbsent(ingress.brokerId, SystemClock.elapsedRealtime() - started)
            }
            override fun onSubscribed(ingress: MqttBrokerPool.Ingress, topics: Set<String>, allAccepted: Boolean) {
                if (topic in topics) ready[ingress.brokerId] = ingress.generation
            }
            override fun onPacket(ingress: MqttBrokerPool.Ingress, topic: String, payload: ByteArray) {
                if (payload.contentEquals(bytes)) received.putIfAbsent(ingress.brokerId, SystemClock.elapsedRealtime())
            }
        })
        try {
            pool.subscribe(mapOf(topic to 1))
            pool.start()
            while (SystemClock.elapsedRealtime() - started < 35_000 && received.size < 3) {
                ready.forEach { (broker, generation) ->
                    if (broker !in sent) {
                        sent[broker] = SystemClock.elapsedRealtime()
                        pool.publish(broker, generation, topic, bytes, UUID.randomUUID().toString())
                    }
                }
                Thread.sleep(25)
            }
            pool.snapshot().forEach { (broker, state) ->
                reports.put(broker, JSONObject().put("connected", state.connected)
                    .put("subscribed", ready.containsKey(broker)).put("echo_received", received.containsKey(broker))
                    .put("connect_ms", connected[broker] ?: JSONObject.NULL)
                    .put("loopback_ms", received[broker]?.let { it - sent.getValue(broker) } ?: JSONObject.NULL)
                    .put("last_error", state.lastError))
            }
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("mqtt_public_pool", reports.toString())
            })
            assertTrue("No public TLS path returned its synthetic packet: $reports", received.isNotEmpty())
        } finally {
            val closeStarted = SystemClock.elapsedRealtime()
            pool.close()
            val closeMillis = SystemClock.elapsedRealtime() - closeStarted
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putLong("mqtt_pool_close_ms", closeMillis)
            })
            assertTrue("MQTT pool close took ${closeMillis}ms", closeMillis < 5_000)
        }
    }
}
