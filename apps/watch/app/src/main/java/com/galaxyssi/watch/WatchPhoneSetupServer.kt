package com.galaxyssi.watch

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.math.BigInteger
import java.net.Inet4Address
import java.net.InetAddress
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Date
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.ssl.*
import javax.security.auth.x500.X500Principal

/** Foreground-only, Wi-Fi-bound configuration receiver. Never logs payloads or credentials. */
internal class WatchPhoneSetupServer(
    private val context: Context,
    private val onState: (State) -> Unit,
    private val apply: (JSONObject) -> JSONObject
) : AutoCloseable {
    data class State(val phase: String, val host: String = "", val port: Int = 0, val code: String = "")
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var closed = false
    @Volatile private var server: SSLServerSocket? = null
    @Volatile private var client: SSLSocket? = null
    @Volatile private var decision: CountDownLatch? = null
    @Volatile private var accepted = false
    @Volatile private var address = ""
    @Volatile private var port = 0
    private var registration: NsdManager.RegistrationListener? = null
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val timeout = Runnable { close(); onState(State("expired")) }
    private val checkNetwork = object : Runnable {
        override fun run() {
            if (closed) return
            if (wifiAddress(context)?.hostAddress != address) { close(); onState(State("network_changed")); return }
            main.postDelayed(this, 2000)
        }
    }
    fun start() {
        main.postDelayed(timeout, 15 * 60_000L)
        Thread({
            try {
                val ip = wifiAddress(context) ?: return@Thread emit("wifi_required")
                val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                val alias = "watch-phone-setup-ec-v1"
                if (!keys.containsAlias(alias)) {
                    KeyPairGenerator.getInstance("EC", "AndroidKeyStore").apply {
                        initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                            .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
                            .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384)
                            .setCertificateSubject(X500Principal("CN=GalaxySSI Watch Setup"))
                            .setCertificateSerialNumber(BigInteger.ONE)
                            .setCertificateNotBefore(Date(0)).setCertificateNotAfter(Date(4102444800000L)).build())
                    }.generateKeyPair()
                }
                val manager = object : X509ExtendedKeyManager() {
                    override fun getClientAliases(type: String?, issuers: Array<out java.security.Principal>?) = null
                    override fun chooseClientAlias(types: Array<out String>?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?) = null
                    override fun getServerAliases(type: String?, issuers: Array<out java.security.Principal>?) = if (type == "EC") arrayOf(alias) else null
                    override fun chooseServerAlias(type: String?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?) = if (type == "EC") alias else null
                    override fun chooseEngineServerAlias(type: String?, issuers: Array<out java.security.Principal>?, engine: SSLEngine?) = if (type == "EC") alias else null
                    override fun getCertificateChain(name: String?) = if (name == alias) arrayOf(keys.getCertificate(alias) as java.security.cert.X509Certificate) else null
                    override fun getPrivateKey(name: String?) = if (name == alias) keys.getKey(alias, null) as java.security.PrivateKey else null
                }
                val tls = SSLContext.getInstance("TLS").apply { init(arrayOf(manager), null, SecureRandom()) }
                val listener = tls.serverSocketFactory.createServerSocket(0, 2, ip) as SSLServerSocket
                listener.enabledProtocols = arrayOf("TLSv1.3", "TLSv1.2")
                server = listener
                if (closed) { listener.close(); return@Thread }
                address = ip.hostAddress.orEmpty(); port = listener.localPort
                main.post { if (!closed) { advertise(); main.post(checkNetwork) } }
                emit("waiting")
                // Bounded attempts prevent confirmation spam; every connection has fresh nonces.
                repeat(3) {
                    if (closed) return@Thread
                    try {
                        (listener.accept() as SSLSocket).use { socket ->
                            client = socket; socket.soTimeout = 60_000; socket.startHandshake()
                            val input = DataInputStream(socket.inputStream)
                            val output = DataOutputStream(socket.outputStream)
                            val hello = read(input)
                            require(hello.getInt("version") == 1 && hello.getString("type") == "hello")
                            val commitment = decode(hello.getString("commitment"))
                            val nonce = ByteArray(32).also { SecureRandom().nextBytes(it) }
                            write(output, JSONObject().put("type", "challenge").put("version", 1).put("commitment", hex(hash(nonce))))
                            val peer = decode(read(input).getString("nonce"))
                            require(MessageDigest.isEqual(commitment, hash(peer)))
                            write(output, JSONObject().put("type", "reveal").put("nonce", hex(nonce)))
                            val cert = socket.session.localCertificates.first().encoded
                            val code = verificationCode(cert, peer, nonce)
                            accepted = false
                            val latch = CountDownLatch(1); decision = latch
                            emit("confirm", code)
                            require(latch.await(60, TimeUnit.SECONDS) && accepted && !closed)
                            decision = null
                            val confirm = read(input)
                            require(confirm.getString("type") == "confirm" && confirm.getBoolean("accept"))
                            write(output, JSONObject().put("type", "ready"))
                            socket.soTimeout = 5 * 60_000
                            repeat(200) {
                                val config = read(input)
                                require(config.getString("type") == "configure")
                                val result = apply(config)
                                write(output, result)
                                emit(result.getString("status"))
                                if (result.getString("status") == "saved") { close(); return@Thread }
                            }
                            close(); return@Thread
                        }
                    } catch (_: Exception) {
                        decision = null; accepted = false
                        if (!closed) emit("retry")
                    } finally { client = null }
                }
                close(); main.post { onState(State("expired")) }
            } catch (_: Exception) { if (!closed) { emit("error"); close() } }
        }, "watch-phone-setup").start()
    }
    fun confirm(allow: Boolean) { accepted = allow; decision?.countDown() }
    private fun emit(phase: String, code: String = "") {
        val value = State(phase, address, port, code)
        main.post { onState(value) }
    }
    private fun advertise() {
        val callback = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) = Unit
            override fun onRegistrationFailed(info: NsdServiceInfo, error: Int) = Unit // Manual IP remains available.
            override fun onServiceUnregistered(info: NsdServiceInfo) = Unit
            override fun onUnregistrationFailed(info: NsdServiceInfo, error: Int) = Unit
        }
        registration = callback
        runCatching { nsd.registerService(NsdServiceInfo().apply {
            serviceName = "GalaxySSI Watch"; serviceType = "_galaxyssi-watch._tcp."; port = this@WatchPhoneSetupServer.port
            setAttribute("v", "1")
        }, NsdManager.PROTOCOL_DNS_SD, callback) }
    }
    override fun close() {
        closed = true; accepted = false; decision?.countDown()
        main.removeCallbacks(timeout); main.removeCallbacks(checkNetwork)
        runCatching { client?.close() }; runCatching { server?.close() }
        main.post { registration?.let { runCatching { nsd.unregisterService(it) } }; registration = null }
    }
    companion object {
        fun wifiAddress(context: Context): InetAddress? {
            val manager = context.getSystemService(ConnectivityManager::class.java)
            return manager.allNetworks.firstNotNullOfOrNull { network ->
                if (manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) null
                else manager.getLinkProperties(network)?.linkAddresses?.map { it.address }?.firstOrNull { it is Inet4Address && !it.isLoopbackAddress && !it.isLinkLocalAddress }
            }
        }
        fun hash(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)
        fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
        fun decode(value: String): ByteArray {
            require(value.matches(Regex("[0-9a-f]{64}")))
            return ByteArray(32) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        }
        fun verificationCode(cert: ByteArray, peer: ByteArray, own: ByteArray): String {
            val digest = hash("GalaxySSI-Watch-Setup-v1".toByteArray() + hash(cert) + peer + own)
            return (BigInteger(1, digest).mod(BigInteger.valueOf(1_000_000)).toInt()).toString().padStart(6, '0')
        }
        fun read(input: DataInputStream): JSONObject {
            val size = input.readInt(); require(size in 2..32768)
            val bytes = ByteArray(size); input.readFully(bytes)
            return JSONObject(bytes.toString(Charsets.UTF_8))
        }
        fun write(output: DataOutputStream, value: JSONObject) {
            val bytes = value.toString().toByteArray(Charsets.UTF_8); require(bytes.size <= 32768)
            output.writeInt(bytes.size); output.write(bytes); output.flush()
        }
    }
}
