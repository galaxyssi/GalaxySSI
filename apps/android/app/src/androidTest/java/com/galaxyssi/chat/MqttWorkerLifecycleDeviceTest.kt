package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

@RunWith(AndroidJUnit4::class)
class MqttWorkerLifecycleDeviceTest {
    @Test fun rejectedConnectionsReleaseTheirWorkers() {
        val prefix = "lifecycle-probe-"
        val accepted = AtomicInteger()
        ServerSocket(0).use { server ->
            val acceptor = thread(isDaemon = true) {
                while (!server.isClosed) runCatching {
                    server.accept().use { accepted.incrementAndGet() }
                }
            }
            repeat(24) { attempt ->
                val failed = CountDownLatch(1)
                val client = MqttAsyncClient("tcp://127.0.0.1:${server.localPort}",
                    "$prefix$attempt", MemoryPersistence())
                try {
                    client.connect(MqttConnectOptions().apply {
                        isAutomaticReconnect = false
                        mqttVersion = MqttConnectOptions.MQTT_VERSION_3_1_1
                        connectionTimeout = 2
                    }, null, object : IMqttActionListener {
                        override fun onSuccess(token: IMqttToken?) = Unit
                        override fun onFailure(token: IMqttToken?, error: Throwable?) { failed.countDown() }
                    })
                    assertTrue("Connection failure callback missing", failed.await(5, TimeUnit.SECONDS))
                } finally {
                    runCatching { client.disconnectForcibly(0, 100, false) }
                    client.close(true)
                }
            }
            server.close()
            acceptor.join(1000)
        }
        assertEquals("Each probe must reach the TCP server", 24, accepted.get())
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
        fun retained() = Thread.getAllStackTraces().keys.filter { it.isAlive && it.name.contains(prefix) }
        while (retained().isNotEmpty() && System.nanoTime() < deadline) Thread.sleep(50)
        assertTrue("Retained MQTT workers: ${retained().map { it.name }}", retained().isEmpty())
    }
}
