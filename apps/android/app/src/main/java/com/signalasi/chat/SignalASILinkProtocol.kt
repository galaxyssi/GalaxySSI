package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object SignalASILinkProtocol {
    const val NAME = "signalasi-link"
    const val VERSION = 2
    private const val PREFS = "opaque_link_v2"
    private const val KEY_SERVERS = "servers"
    private const val LINK_SECRET_BYTES = 32
    private const val TOPIC_EPOCH_SECONDS = 6 * 60 * 60L
    private const val TOPIC_RECEIVE_WINDOW = 1
    private const val MAX_QR_AGE_MS = 10 * 60 * 1000L
    private const val MAX_CLOCK_SKEW_MS = 5 * 60 * 1000L
    private const val DEFAULT_MESSAGE_TTL_MS = 7 * 24 * 60 * 60 * 1000L
    private const val MAX_OPAQUE_PACKET_BYTES = 60 * 1024
    const val MAX_ENVELOPE_BYTES = 512 * 1024
    const val ACCESS_CONTRACT = "signalasi.pairing-access/1.0"
    const val ACCESS_RESTRICTED = "restricted"
    const val ACCESS_DESKTOP_EXECUTOR = "desktop_executor"
    const val SCOPE_AGENT_CHAT = "agent.chat"
    const val SCOPE_EXPLICIT_ATTACHMENTS = "agent.attachments.explicit"
    const val SCOPE_TASK_WORKSPACE = "desktop.task_workspace"
    const val SCOPE_DESKTOP_EXECUTOR = "desktop.executor.full"
    const val SCOPE_DESKTOP_CONTROL = "desktop.control"
    const val SCOPE_DESKTOP_NATIVE_TOOLS = "desktop.native_tools"
    const val SCOPE_DESKTOP_EXTERNAL_FILES = "desktop.files.external"
    const val CAPABILITY_MANIFEST_VERSION = 2
    private const val MAX_TEXT_BYTES = 128 * 1024
    private val routePattern = Regex("^[A-Za-z0-9_-]{22}$")
    private val secretPattern = Regex("^[A-Za-z0-9_-]{43}$")
    private val wireBuckets = intArrayOf(1024, 4096, 16 * 1024, 40 * 1024)
    private val random = SecureRandom()

    data class Routes(
        val clientRouteId: String,
        val linkSecret: String,
        val localFingerprint: String,
        val remoteFingerprint: String
    ) {
        init {
            require(validRouteId(clientRouteId)) { "Invalid internal route ID" }
            require(validLinkSecret(linkSecret)) { "Invalid link secret" }
            require(localFingerprint.isNotBlank() && remoteFingerprint.isNotBlank()) {
                "Identity fingerprints are required"
            }
            require(localFingerprint != remoteFingerprint) { "Identity fingerprints must differ" }
        }

        val up: String
            get() = relationshipTopic(linkSecret, localFingerprint, remoteFingerprint)
        val down: String
            get() = relationshipTopic(linkSecret, remoteFingerprint, localFingerprint)
        val control: String
            get() = up
        val receiveWindow: Set<String>
            get() {
                val current = topicEpoch()
                return (-TOPIC_RECEIVE_WINDOW..TOPIC_RECEIVE_WINDOW).mapTo(linkedSetOf()) { offset ->
                    relationshipTopic(linkSecret, remoteFingerprint, localFingerprint, current + offset)
                }
            }
        val sendWindow: Set<String>
            get() {
                val current = topicEpoch()
                return (-TOPIC_RECEIVE_WINDOW..TOPIC_RECEIVE_WINDOW).mapTo(linkedSetOf()) { offset ->
                    relationshipTopic(linkSecret, localFingerprint, remoteFingerprint, current + offset)
                }
            }
    }

    data class ServerLink(
        val desktopId: String,
        val desktopName: String,
        val desktopFingerprint: String,
        val signalName: String,
        val routes: Routes,
        val paired: Boolean,
        val accessProfile: String = ACCESS_RESTRICTED,
        val accessScopes: Set<String> = emptySet(),
        val capabilityManifestVersion: Int = 0
    ) {
        val fullDesktopExecutor: Boolean
            get() = accessProfile == ACCESS_DESKTOP_EXECUTOR &&
                SCOPE_DESKTOP_EXECUTOR in accessScopes

        fun toJson(): JSONObject = JSONObject()
            .put("desktop_id", desktopId)
            .put("desktop_name", desktopName)
            .put("desktop_fingerprint", desktopFingerprint)
            .put("signal_name", signalName)
            .put("client_route_id", routes.clientRouteId)
            .put("link_secret", routes.linkSecret)
            .put("local_identity_fingerprint", routes.localFingerprint)
            .put("paired", paired)
            .put("access_profile", accessProfile)
            .put("access_scopes", JSONArray(accessScopes.sorted()))
            .put("capability_manifest_version", capabilityManifestVersion)
            .put("updated_at", System.currentTimeMillis())
    }

    data class PairingAccess(val profile: String, val scopes: Set<String>) {
        val fullDesktopExecutor: Boolean
            get() = profile == ACCESS_DESKTOP_EXECUTOR && SCOPE_DESKTOP_EXECUTOR in scopes
    }

    fun newRouteId(): String = b64Url(ByteArray(16).also(random::nextBytes))

    fun newLinkSecret(): String = b64Url(ByteArray(LINK_SECRET_BYTES).also(random::nextBytes))

    fun validRouteId(value: String): Boolean = routePattern.matches(value)

    fun validLinkSecret(value: String): Boolean = secretPattern.matches(value)

    fun validTopic(value: String): Boolean = secretPattern.matches(value)

    fun pairingTopic(secret: String): String = b64Url(kdf(secretBytes(secret), "rendezvous-topic".toByteArray()))

    fun deriveLinkSecret(pairingSecret: String, firstFingerprint: String, secondFingerprint: String): String {
        val identities = listOf(firstFingerprint, secondFingerprint).sorted()
        require(identities.all(String::isNotBlank)) { "Both identity fingerprints are required" }
        val binding = identities.joinToString("\u0000").toByteArray(Charsets.UTF_8)
        return b64Url(kdf(secretBytes(pairingSecret), "relationship\u0000".toByteArray() + binding))
    }

    fun topicEpoch(atSeconds: Long = System.currentTimeMillis() / 1000L): Long =
        atSeconds / TOPIC_EPOCH_SECONDS

    fun topicRefreshDelayMillis(nowMillis: Long = System.currentTimeMillis()): Long {
        val epochMillis = TOPIC_EPOCH_SECONDS * 1_000L
        return (epochMillis - Math.floorMod(nowMillis, epochMillis) + 5_000L)
            .coerceAtLeast(1_000L)
    }

    fun relationshipTopic(
        linkSecret: String,
        senderFingerprint: String,
        receiverFingerprint: String,
        epoch: Long = topicEpoch()
    ): String {
        require(senderFingerprint.isNotBlank() && receiverFingerprint.isNotBlank()) {
            "Sender and receiver fingerprints are required"
        }
        require(senderFingerprint != receiverFingerprint) { "Sender and receiver must differ" }
        val binding = buildString {
            append("mailbox\u0000")
            append(senderFingerprint)
            append('\u0000')
            append(receiverFingerprint)
            append('\u0000')
            append(epoch)
        }.toByteArray(Charsets.UTF_8)
        return b64Url(kdf(secretBytes(linkSecret), binding))
    }

    fun sealWirePacket(payload: String, secret: String): String {
        val raw = payload.toByteArray(Charsets.UTF_8)
        val required = 5 + raw.size
        val bucket = wireBuckets.firstOrNull { required <= it }
            ?: throw IllegalArgumentException("Wire payload exceeds opaque packet limit")
        val plaintext = ByteBuffer.allocate(bucket)
            .put(VERSION.toByte())
            .putInt(raw.size)
            .put(raw)
            .put(ByteArray(bucket - required).also(random::nextBytes))
            .array()
        val nonce = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(kdf(secretBytes(secret), "wire-aead".toByteArray()), "AES"),
            GCMParameterSpec(128, nonce)
        )
        val encoded = b64Url(nonce + cipher.doFinal(plaintext))
        require(encoded.toByteArray(Charsets.US_ASCII).size <= MAX_OPAQUE_PACKET_BYTES) {
            "Opaque packet exceeds broker limit"
        }
        return encoded
    }

    fun openWirePacket(wire: ByteArray, secret: String): String {
        val sealed = b64UrlDecode(wire.toString(Charsets.US_ASCII))
        require(sealed.size >= 33) { "Opaque packet is truncated" }
        val nonce = sealed.copyOfRange(0, 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(kdf(secretBytes(secret), "wire-aead".toByteArray()), "AES"),
            GCMParameterSpec(128, nonce)
        )
        val plaintext = cipher.doFinal(sealed.copyOfRange(12, sealed.size))
        val buffer = ByteBuffer.wrap(plaintext)
        require(buffer.get().toInt() == VERSION) { "Unsupported opaque packet version" }
        val payloadSize = buffer.int
        require(payloadSize >= 0 && payloadSize <= buffer.remaining()) { "Invalid opaque packet length" }
        val payload = ByteArray(payloadSize)
        buffer.get(payload)
        return payload.toString(Charsets.UTF_8)
    }

    fun needsCapabilityManifest(link: ServerLink): Boolean =
        link.capabilityManifestVersion < CAPABILITY_MANIFEST_VERSION

    fun normalizePairingQr(source: JSONObject): JSONObject? {
        if (source.optString("t") != "o2") return null
        val desktopName = source.optString("n").ifBlank { "SignalASI Desktop" }
        val fingerprint = source.optString("h")
        val pairingSecret = source.optString("e")
        val executor = source.optInt("a") == 1
        val scopes = mutableListOf(
            SCOPE_AGENT_CHAT,
            SCOPE_EXPLICIT_ATTACHMENTS,
            SCOPE_TASK_WORKSPACE
        ).apply {
            if (executor) {
                add(SCOPE_DESKTOP_EXECUTOR)
                add(SCOPE_DESKTOP_CONTROL)
                add(SCOPE_DESKTOP_NATIVE_TOOLS)
                add(SCOPE_DESKTOP_EXTERNAL_FILES)
            }
        }
        val createdAt = source.optLong("c")
        return JSONObject()
            .put("type", "opaque_pairing")
            .put("version", VERSION)
            .put("desktop_id", "desktop_${fingerprint.take(16)}")
            .put("desktop_name", desktopName)
            .put("desktop_display_name", desktopName)
            .put("device_id", 1)
            .put("identity_key", source.optString("k"))
            .put("identity_key_sha256", fingerprint)
            .put("created_at", createdAt)
            .put("pairing_topic", pairingTopic(pairingSecret))
            .put("pairing_token", source.optString("x"))
            .put("pairing_secret", pairingSecret)
            .put(
                "pairing_access",
                JSONObject()
                    .put("contract_version", ACCESS_CONTRACT)
                    .put("version", 1)
                    .put("profile", if (executor) ACCESS_DESKTOP_EXECUTOR else ACCESS_RESTRICTED)
                    .put("scopes", JSONArray(scopes))
                    .put("desktop_executor", executor)
                    .put("issued_at", TimeUnit.SECONDS.toMillis(createdAt))
            )
            .apply {
                source.optString("o").takeIf(String::isNotBlank)?.let { token ->
                    put("desktop_control_authorization", JSONObject().put("token", token))
                }
            }
    }

    fun validatePairingQr(qr: JSONObject, nowMs: Long = System.currentTimeMillis()): Boolean {
        if (qr.optString("type") != "opaque_pairing" || qr.optInt("version") != VERSION) return false
        if (qr.optString("pairing_token").length < 32) return false
        val secret = qr.optString("pairing_secret")
        if (!validLinkSecret(secret) || qr.optString("pairing_topic") != pairingTopic(secret)) return false
        if (qr.optString("desktop_id").isBlank() || qr.optString("identity_key_sha256").length != 64) return false
        if (pairingAccess(qr.optJSONObject("pairing_access")) == null) return false
        val createdAt = qr.optLong("created_at")
        val createdAtMs = if (createdAt < 10_000_000_000L) TimeUnit.SECONDS.toMillis(createdAt) else createdAt
        return createdAtMs > 0 && kotlin.math.abs(nowMs - createdAtMs) <= MAX_QR_AGE_MS
    }

    fun shouldRotateClientRoute(
        existing: ServerLink?,
        qr: JSONObject,
        localFingerprint: String = SignalASICrypto.localIdentitySha256()
    ): Boolean {
        if (existing == null) return true
        val nextSecret = runCatching {
            deriveLinkSecret(qr.getString("pairing_secret"), localFingerprint, qr.getString("identity_key_sha256"))
        }.getOrDefault("")
        val requestedAccess = pairingAccess(qr.optJSONObject("pairing_access")) ?: return true
        return existing.desktopId != qr.optString("desktop_id") ||
            existing.desktopFingerprint != qr.optString("identity_key_sha256") ||
            existing.routes.linkSecret != nextSecret ||
            existing.accessProfile != requestedAccess.profile ||
            existing.accessScopes != requestedAccess.scopes
    }

    @Synchronized
    fun ensureServerLink(context: Context, qr: JSONObject, rotateClientRoute: Boolean = false): ServerLink {
        require(validatePairingQr(qr)) { "Invalid opaque pairing QR" }
        val desktopId = qr.getString("desktop_id")
        val existing = serverLink(context, desktopId)
        val localFingerprint = SignalASICrypto.localIdentitySha256()
        val remoteFingerprint = qr.getString("identity_key_sha256")
        val linkSecret = deriveLinkSecret(qr.getString("pairing_secret"), localFingerprint, remoteFingerprint)
        if (!rotateClientRoute && existing != null && existing.routes.linkSecret == linkSecret) return existing
        val access = requireNotNull(pairingAccess(qr.optJSONObject("pairing_access"))) {
            "Invalid pairing access grant"
        }
        val link = ServerLink(
            desktopId = desktopId,
            desktopName = qr.optString("desktop_name", "SignalASI Desktop"),
            desktopFingerprint = remoteFingerprint,
            signalName = desktopId,
            routes = Routes(newRouteId(), linkSecret, localFingerprint, remoteFingerprint),
            paired = false,
            accessProfile = access.profile,
            accessScopes = access.scopes
        )
        existing?.let { SignalASILinkDeliveryStore.discardRoutes(context, it.routes) }
        save(context, link)
        return link
    }

    @Synchronized
    fun markPaired(context: Context, desktopId: String, access: JSONObject? = null): ServerLink? {
        val current = serverLink(context, desktopId) ?: return null
        val parsedAccess = pairingAccess(access)
        val updated = current.copy(
            paired = true,
            accessProfile = parsedAccess?.profile ?: current.accessProfile,
            accessScopes = parsedAccess?.scopes ?: current.accessScopes
        )
        save(context, updated)
        return updated
    }

    @Synchronized
    fun updatePairingAccess(context: Context, desktopId: String, access: JSONObject?): ServerLink? {
        val current = serverLink(context, desktopId) ?: return null
        val parsed = pairingAccess(access) ?: return current
        val updated = current.copy(accessProfile = parsed.profile, accessScopes = parsed.scopes)
        save(context, updated)
        return updated
    }

    @Synchronized
    fun markCapabilityManifestReceived(context: Context, desktopId: String, version: Int): ServerLink? {
        val current = serverLink(context, desktopId) ?: return null
        if (version <= current.capabilityManifestVersion) return current
        val updated = current.copy(capabilityManifestVersion = version)
        save(context, updated)
        return updated
    }

    fun serverLink(context: Context, desktopId: String): ServerLink? =
        allServerLinks(context).firstOrNull { it.desktopId == desktopId }

    fun isCryptographicallyReady(context: Context, link: ServerLink): Boolean {
        if (link.paired) return true
        val verifiedFingerprint = SignalASICrypto.verifiedDesktopFingerprint(link.desktopId)
        return verifiedFingerprint.isNotBlank() &&
            verifiedFingerprint.equals(link.desktopFingerprint, ignoreCase = true) &&
            SignalASICrypto.hasDesktopSession(context, link.desktopId)
    }

    fun serverLink(context: Context, desktopId: String, clientRouteId: String): ServerLink? =
        allServerLinks(context).firstOrNull {
            it.desktopId == desktopId && it.routes.clientRouteId == clientRouteId
        }

    fun allServerLinks(context: Context): List<ServerLink> {
        val raw = storage(context).readString(KEY_SERVERS, "[]")
        val array = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                runCatching {
                    val remoteFingerprint = item.getString("desktop_fingerprint")
                    add(
                        ServerLink(
                            desktopId = item.getString("desktop_id"),
                            desktopName = item.optString("desktop_name", "SignalASI Desktop"),
                            desktopFingerprint = remoteFingerprint,
                            signalName = item.optString("signal_name", item.getString("desktop_id")),
                            routes = Routes(
                                item.getString("client_route_id"),
                                item.getString("link_secret"),
                                item.getString("local_identity_fingerprint"),
                                remoteFingerprint
                            ),
                            paired = item.optBoolean("paired", false),
                            accessProfile = item.optString("access_profile", ACCESS_RESTRICTED),
                            accessScopes = item.optJSONArray("access_scopes").toStringSet(),
                            capabilityManifestVersion = item.optInt("capability_manifest_version", 0)
                        )
                    )
                }
            }
        }
    }

    @Synchronized
    fun removeServer(context: Context, desktopId: String) {
        val links = allServerLinks(context)
        links.firstOrNull { it.desktopId == desktopId }?.let {
            SignalASILinkDeliveryStore.discardRoutes(context, it.routes)
        }
        write(context, links.filterNot { it.desktopId == desktopId })
    }

    @Synchronized
    fun clear(context: Context) = storage(context).clear()

    fun makeEnvelope(payload: JSONObject, sourceId: String, targetId: String): JSONObject {
        require(payload.optString("content").toByteArray(Charsets.UTF_8).size <= MAX_TEXT_BYTES) {
            "Text exceeds Link limit"
        }
        val now = System.currentTimeMillis()
        val messageId = runCatching { UUID.fromString(payload.optString("message_id")).toString() }
            .getOrElse { UUID.randomUUID().toString() }
        val envelope = JSONObject()
            .put("protocol", NAME)
            .put("version", VERSION)
            .put("message_id", messageId)
            .put("conversation_id", payload.optString("conversation_id"))
            .put("source_id", sourceId)
            .put("target_id", targetId)
            .put("reply_to", payload.optString("reply_to"))
            .put("sent_at", now)
            .put("expires_at", now + DEFAULT_MESSAGE_TTL_MS)
            .put("payload", payload)
        require(envelope.toString().toByteArray(Charsets.UTF_8).size <= MAX_ENVELOPE_BYTES) {
            "Envelope exceeds Link limit"
        }
        return envelope
    }

    fun pairingAccess(source: JSONObject?): PairingAccess? {
        val value = source ?: return null
        if (value.optString("contract_version") != ACCESS_CONTRACT || value.optInt("version") != 1) return null
        val profile = value.optString("profile")
        if (profile !in setOf(ACCESS_RESTRICTED, ACCESS_DESKTOP_EXECUTOR)) return null
        val scopes = value.optJSONArray("scopes").toStringSet()
        val restrictedScopes = setOf(SCOPE_AGENT_CHAT, SCOPE_EXPLICIT_ATTACHMENTS, SCOPE_TASK_WORKSPACE)
        val executorScopes = restrictedScopes + setOf(
            SCOPE_DESKTOP_EXECUTOR,
            SCOPE_DESKTOP_CONTROL,
            SCOPE_DESKTOP_NATIVE_TOOLS,
            SCOPE_DESKTOP_EXTERNAL_FILES
        )
        if (!scopes.containsAll(restrictedScopes)) return null
        if (profile == ACCESS_DESKTOP_EXECUTOR && !scopes.containsAll(executorScopes)) return null
        if (profile == ACCESS_RESTRICTED && scopes.any { it in executorScopes - restrictedScopes }) return null
        return PairingAccess(profile, scopes)
    }

    fun encryptPairingClaim(claim: JSONObject, qr: JSONObject): String {
        require(validatePairingQr(qr)) { "Invalid opaque pairing QR" }
        return sealWirePacket(claim.toString(), qr.getString("pairing_secret"))
    }

    fun unwrapEnvelope(envelope: JSONObject): JSONObject? {
        if (envelope.optString("protocol") != NAME || envelope.optInt("version") != VERSION) return null
        if (envelope.toString().toByteArray(Charsets.UTF_8).size > MAX_ENVELOPE_BYTES) return null
        if (runCatching { UUID.fromString(envelope.optString("message_id")) }.isFailure) return null
        if (envelope.optString("source_id").isBlank() || envelope.optString("target_id").isBlank()) return null
        val now = System.currentTimeMillis()
        val sentAt = envelope.optLong("sent_at")
        val expiresAt = envelope.optLong("expires_at")
        if (sentAt <= 0 || sentAt - now > MAX_CLOCK_SKEW_MS || expiresAt <= sentAt || now > expiresAt) return null
        return envelope.optJSONObject("payload")?.apply {
            put("message_id", envelope.optString("message_id"))
            if (optString("reply_to").isBlank()) put("reply_to", envelope.optString("reply_to"))
            if (optString("conversation_id").isBlank()) put("conversation_id", envelope.optString("conversation_id"))
        }
    }

    private fun save(context: Context, link: ServerLink) {
        write(context, allServerLinks(context).filterNot { it.desktopId == link.desktopId } + link)
    }

    private fun write(context: Context, links: List<ServerLink>) {
        val array = JSONArray()
        links.forEach { array.put(it.toJson()) }
        storage(context).writeString(KEY_SERVERS, array.toString())
    }

    private fun kdf(secret: ByteArray, label: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return mac.doFinal("signalasi-opaque-v2\u0000".toByteArray(Charsets.UTF_8) + label)
    }

    private fun secretBytes(value: String): ByteArray {
        require(validLinkSecret(value)) { "Invalid link secret" }
        return b64UrlDecode(value)
    }

    private fun b64Url(value: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value)

    private fun b64UrlDecode(value: String): ByteArray = Base64.getUrlDecoder().decode(value)

    private fun storage(context: Context): AgentEncryptedPreferences =
        AgentEncryptedPreferences(context.applicationContext, PREFS)

    private fun JSONArray?.toStringSet(): Set<String> = buildSet {
        val source = this@toStringSet ?: return@buildSet
        for (index in 0 until source.length()) {
            source.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
        }
    }
}
