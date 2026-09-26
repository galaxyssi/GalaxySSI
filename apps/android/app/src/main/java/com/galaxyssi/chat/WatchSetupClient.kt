package com.galaxyssi.chat

import android.net.Network
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.math.BigInteger
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.ssl.*

/** Bootstrap TLS is authenticated by an explicit, certificate-bound numeric comparison on BOTH devices.
 * This trust manager is confined to provisioning and must never be used for model requests. */
internal class WatchSetupClient : AutoCloseable {
    @Volatile private var socket: Socket? = null
    @Volatile private var stopped = false
    private val decision = CountDownLatch(1)
    @Volatile private var accepted = false
    private lateinit var input: DataInputStream
    private lateinit var output: DataOutputStream

    fun connect(network: Network, host: String, port: Int, code: (String) -> Unit) {
        require(port in 1..65535)
        require(host.matches(Regex("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}")))
        val address = InetAddress.getByName(host)
        require(!address.isLoopbackAddress && !address.isAnyLocalAddress && !address.isMulticastAddress)
        val tcp = network.socketFactory.createSocket(); socket = tcp
        if (stopped) { tcp.close(); error("Closed") }
        tcp.connect(InetSocketAddress(address, port), 10000)
        tcp.soTimeout = 65000
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers() = emptyArray<X509Certificate>()
            override fun checkClientTrusted(c: Array<X509Certificate>, a: String) = Unit
            override fun checkServerTrusted(c: Array<X509Certificate>, a: String) = Unit
        }
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), SecureRandom()) }
        val tls = context.socketFactory.createSocket(tcp, host, port, true) as SSLSocket
        socket = tls
        if (stopped) { tls.close(); error("Closed") }
        tls.enabledProtocols = tls.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }.toTypedArray()
        tls.startHandshake()
        input = DataInputStream(tls.inputStream); output = DataOutputStream(tls.outputStream)
        val nonce = ByteArray(32).also { SecureRandom().nextBytes(it) }
        write(JSONObject().put("type", "hello").put("version", 1).put("commitment", hex(hash(nonce))))
        val challenge = read()
        require(challenge.getString("type") == "challenge" && challenge.getInt("version") == 1)
        val commitment = decode(challenge.getString("commitment"))
        write(JSONObject().put("type", "reveal").put("nonce", hex(nonce)))
        val reveal = read(); require(reveal.getString("type") == "reveal")
        val peer = decode(reveal.getString("nonce"))
        require(MessageDigest.isEqual(commitment, hash(peer)))
        code(verificationCode(tls.session.peerCertificates.first().encoded, nonce, peer))
        require(decision.await(60, TimeUnit.SECONDS) && accepted && !stopped)
        write(JSONObject().put("type", "confirm").put("accept", true))
        require(read().getString("type") == "ready")
        tls.soTimeout = 30000
    }

    fun confirm() { accepted = true; decision.countDown() }
    fun exchange(config: JSONObject, timeoutMillis: Int = 30000): JSONObject {
        check(accepted && !stopped)
        socket?.soTimeout = timeoutMillis
        write(config); return read()
    }
    private fun write(value: JSONObject) {
        val bytes = value.toString().toByteArray(Charsets.UTF_8); require(bytes.size in 2..32768)
        output.writeInt(bytes.size); output.write(bytes); output.flush()
    }
    private fun read(): JSONObject {
        val size = input.readInt(); require(size in 2..32768)
        val bytes = ByteArray(size); input.readFully(bytes)
        return JSONObject(bytes.toString(Charsets.UTF_8))
    }
    override fun close() { stopped = true; decision.countDown(); runCatching { socket?.close() } }
    companion object {
        private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
        private fun decode(value: String): ByteArray {
            require(value.matches(Regex("[0-9a-f]{64}")))
            return ByteArray(32) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        }
        internal fun verificationCode(cert: ByteArray, client: ByteArray, server: ByteArray): String =
            BigInteger(1, hash("GalaxySSI-Watch-Setup-v1".toByteArray() + hash(cert) + client + server))
                .mod(BigInteger.valueOf(1000000)).toString().padStart(6, '0')
    }
}
