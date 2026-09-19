package com.galaxyssi.watch

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.DataInputStream
import java.io.DataOutputStream
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import javax.net.ssl.*

class WatchPhoneSetupTest {
    private class Fixture(val approve: Boolean) : AutoCloseable {
        val states = LinkedBlockingQueue<WatchPhoneSetupServer.State>()
        val payloads = LinkedBlockingQueue<JSONObject>()
        val server = WatchPhoneSetupServer(InstrumentationRegistry.getInstrumentation().targetContext, { states.offer(it) }, {
            payloads.offer(it); JSONObject().put("status", "saved")
        })
        fun await(phase: String): WatchPhoneSetupServer.State {
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
            while (System.nanoTime() < until) {
                val state = states.poll(1, TimeUnit.SECONDS) ?: continue
                assertFalse("Receiver startup failed: ${state.phase}", state.phase in setOf("error", "wifi_required"))
                if (state.phase == phase) return state
            }
            error("Timed out waiting for $phase")
        }
        fun connect(): SSLSocket {
            server.start(); val ready = await("waiting")
            // Test bootstrap only: the production client must compare the bound SAS before sending secrets.
            val trust = object : X509TrustManager {
                override fun getAcceptedIssuers() = emptyArray<X509Certificate>()
                override fun checkClientTrusted(chain: Array<X509Certificate>, type: String) = Unit
                override fun checkServerTrusted(chain: Array<X509Certificate>, type: String) = Unit
            }
            val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), SecureRandom()) }
            return (tls.socketFactory.createSocket(ready.host, ready.port) as SSLSocket).apply { soTimeout = 5000; startHandshake() }
        }
        override fun close() = server.close()
    }
    @Test fun confirmedSessionTransfersAndAcknowledgesWithoutChangingUserSettings() {
        Fixture(true).use { fixture -> fixture.connect().use { socket ->
            val input = DataInputStream(socket.inputStream); val output = DataOutputStream(socket.outputStream)
            val nonce = ByteArray(32).also { SecureRandom().nextBytes(it) }
            WatchPhoneSetupServer.write(output, JSONObject().put("type", "hello").put("version", 1).put("commitment", WatchPhoneSetupServer.hex(WatchPhoneSetupServer.hash(nonce))))
            val challenge = WatchPhoneSetupServer.read(input)
            WatchPhoneSetupServer.write(output, JSONObject().put("nonce", WatchPhoneSetupServer.hex(nonce)))
            val peer = WatchPhoneSetupServer.decode(WatchPhoneSetupServer.read(input).getString("nonce"))
            assertEquals(challenge.getString("commitment"), WatchPhoneSetupServer.hex(WatchPhoneSetupServer.hash(peer)))
            val code = WatchPhoneSetupServer.verificationCode(socket.session.peerCertificates.first().encoded, nonce, peer)
            assertEquals(code, fixture.await("confirm").code)
            fixture.server.confirm(true)
            WatchPhoneSetupServer.write(output, JSONObject().put("type", "confirm").put("accept", true))
            assertEquals("ready", WatchPhoneSetupServer.read(input).getString("type"))
            WatchPhoneSetupServer.write(output, JSONObject().put("type", "configure").put("kind", "test"))
            assertEquals("saved", WatchPhoneSetupServer.read(input).getString("status"))
            assertEquals("test", fixture.payloads.poll(3, TimeUnit.SECONDS)?.getString("kind"))
        } }
    }
    @Test fun mismatchedCommitmentCannotReachConfiguration() {
        Fixture(false).use { fixture -> fixture.connect().use { socket ->
            val input = DataInputStream(socket.inputStream); val output = DataOutputStream(socket.outputStream)
            WatchPhoneSetupServer.write(output, JSONObject().put("type", "hello").put("version", 1).put("commitment", "00".repeat(32)))
            WatchPhoneSetupServer.read(input)
            WatchPhoneSetupServer.write(output, JSONObject().put("nonce", "11".repeat(32)))
            fixture.await("retry")
            assertTrue(fixture.payloads.isEmpty())
        } }
    }
    @Test fun unconfirmedConnectionDoesNotApplyPayloadAndClosesOnExit() {
        Fixture(false).use { fixture -> fixture.connect().use { socket ->
            val input = DataInputStream(socket.inputStream); val output = DataOutputStream(socket.outputStream)
            val nonce = ByteArray(32).also { SecureRandom().nextBytes(it) }
            WatchPhoneSetupServer.write(output, JSONObject().put("type", "hello").put("version", 1).put("commitment", WatchPhoneSetupServer.hex(WatchPhoneSetupServer.hash(nonce))))
            WatchPhoneSetupServer.read(input)
            WatchPhoneSetupServer.write(output, JSONObject().put("nonce", WatchPhoneSetupServer.hex(nonce)))
            WatchPhoneSetupServer.read(input); fixture.await("confirm")
            fixture.server.confirm(false); fixture.await("retry")
            assertTrue(fixture.payloads.isEmpty())
            fixture.server.close()
        } }
    }
}
