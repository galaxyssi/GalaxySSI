package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object SignalASILinkProtocol {
    const val NAME = "signalasi-link"
    const val VERSION = 1
    const val TOPIC_ROOT = "signalasichat/v1"
    private const val PREFS = "signalasi_link_v1"
    private const val KEY_SERVERS = "servers"
    private const val MAX_QR_AGE_MS = 10 * 60 * 1000L
    private const val MAX_CLOCK_SKEW_MS = 5 * 60 * 1000L
    private const val DEFAULT_MESSAGE_TTL_MS = 7 * 24 * 60 * 60 * 1000L
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
    private val random = SecureRandom()

    data class Routes(val serverRouteId: String, val clientRouteId: String) {
        init {
            require(validRouteId(serverRouteId)) { "Invalid server route ID" }
            require(validRouteId(clientRouteId)) { "Invalid client route ID" }
        }

        val pairing: String get() = "$TOPIC_ROOT/$serverRouteId/pair"
        val up: String get() = "$TOPIC_ROOT/$serverRouteId/$clientRouteId/up"
        val down: String get() = "$TOPIC_ROOT/$serverRouteId/$clientRouteId/down"
        val control: String get() = "$TOPIC_ROOT/$serverRouteId/$clientRouteId/control"
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
            .put("server_route_id", routes.serverRouteId)
            .put("client_route_id", routes.clientRouteId)
            .put("paired", paired)
            .put("access_profile", accessProfile)
            .put("access_scopes", JSONArray(accessScopes.sorted()))
            .put("capability_manifest_version", capabilityManifestVersion)
            .put("updated_at", System.currentTimeMillis())
    }

    data class PairingAccess(
        val profile: String,
        val scopes: Set<String>
    ) {
        val fullDesktopExecutor: Boolean
            get() = profile == ACCESS_DESKTOP_EXECUTOR &&
                SCOPE_DESKTOP_EXECUTOR in scopes
    }

    fun newRouteId(): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    fun validRouteId(value: String): Boolean = routePattern.matches(value)

    fun needsCapabilityManifest(link: ServerLink): Boolean =
        link.capabilityManifestVersion < CAPABILITY_MANIFEST_VERSION

    fun normalizePairingQr(source: JSONObject): JSONObject? {
        if (source.optString("type") == "signalasi_verify") return source
        if (source.optString("t") != "sv1") return null

        val desktopName = source.optString("n").ifBlank { "SignalASI Desktop" }
        val fingerprint = source.optString("h")
        val serverRouteId = source.optString("s")
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
            .put("type", "signalasi_verify")
            .put("version", VERSION)
            .put("device", "pc")
            .put("desktop_id", "desktop_${fingerprint.take(16)}")
            .put("desktop_name", desktopName)
            .put("desktop_display_name", desktopName)
            .put("device_id", 1)
            .put("identity_key", source.optString("k"))
            .put("identity_key_sha256", fingerprint)
            .put("created_at", createdAt)
            .put("protocol", NAME)
            .put("role", "server")
            .put("server_route_id", serverRouteId)
            .put("pairing_topic", "$TOPIC_ROOT/$serverRouteId/pair")
            .put("pairing_token", source.optString("x"))
            .put("pairing_secret", source.optString("e"))
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
                source.optString("o").takeIf { it.isNotBlank() }?.let { token ->
                    put("desktop_control_authorization", JSONObject().put("token", token))
                }
            }
    }

    fun validatePairingQr(qr: JSONObject, nowMs: Long = System.currentTimeMillis()): Boolean {
        if (qr.optString("type") != "signalasi_verify") return false
        if (qr.optString("protocol") != NAME || qr.optInt("version") != VERSION) return false
        if (qr.optString("role") != "server") return false
        val serverRouteId = qr.optString("server_route_id")
        if (!validRouteId(serverRouteId)) return false
        if (qr.optString("pairing_topic") != "$TOPIC_ROOT/$serverRouteId/pair") return false
        if (qr.optString("pairing_token").length < 32) return false
        if (runCatching { Base64.getUrlDecoder().decode(qr.optString("pairing_secret")) }.getOrNull()?.size != 32) return false
        if (qr.optString("desktop_id").isBlank() || qr.optString("identity_key_sha256").length != 64) return false
        if (pairingAccess(qr.optJSONObject("pairing_access")) == null) return false
        val createdAt = qr.optLong("created_at")
        val createdAtMs = if (createdAt < 10_000_000_000L) TimeUnit.SECONDS.toMillis(createdAt) else createdAt
        return createdAtMs > 0 && kotlin.math.abs(nowMs - createdAtMs) <= MAX_QR_AGE_MS
    }

    fun shouldRotateClientRoute(existing: ServerLink?, qr: JSONObject): Boolean {
        if (existing == null) return true
        if (existing.desktopId != qr.optString("desktop_id") ||
            existing.desktopFingerprint != qr.optString("identity_key_sha256") ||
            existing.routes.serverRouteId != qr.optString("server_route_id")
        ) return true
        val requestedAccess = pairingAccess(qr.optJSONObject("pairing_access")) ?: return true
        return existing.accessProfile != requestedAccess.profile ||
            existing.accessScopes != requestedAccess.scopes
    }

    @Synchronized
    fun ensureServerLink(
        context: Context,
        qr: JSONObject,
        rotateClientRoute: Boolean = false
    ): ServerLink {
        require(validatePairingQr(qr)) { "Invalid SignalASI Link v1 pairing QR" }
        val desktopId = qr.getString("desktop_id")
        val existing = serverLink(context, desktopId)
        if (!rotateClientRoute &&
            existing != null &&
            existing.routes.serverRouteId == qr.getString("server_route_id")
        ) return existing
        val access = requireNotNull(pairingAccess(qr.optJSONObject("pairing_access"))) {
            "Invalid SignalASI pairing access grant"
        }
        val link = ServerLink(
            desktopId = desktopId,
            desktopName = qr.optString("desktop_name", "SignalASI Desktop"),
            desktopFingerprint = qr.getString("identity_key_sha256"),
            signalName = desktopId,
            routes = Routes(qr.getString("server_route_id"), newRouteId()),
            paired = false,
            accessProfile = access.profile,
            accessScopes = access.scopes
        )
        existing?.let { SignalASILinkDeliveryStore.discardRoutes(context, it.routes) }
        save(context, link)
        return link
    }

    @Synchronized
    fun markPaired(
        context: Context,
        desktopId: String,
        access: JSONObject? = null
    ): ServerLink? {
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
    fun updatePairingAccess(
        context: Context,
        desktopId: String,
        access: JSONObject?
    ): ServerLink? {
        val current = serverLink(context, desktopId) ?: return null
        val parsed = pairingAccess(access) ?: return current
        val updated = current.copy(
            accessProfile = parsed.profile,
            accessScopes = parsed.scopes
        )
        save(context, updated)
        return updated
    }

    @Synchronized
    fun markCapabilityManifestReceived(
        context: Context,
        desktopId: String,
        version: Int
    ): ServerLink? {
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

    fun serverLink(
        context: Context,
        desktopId: String,
        clientRouteId: String
    ): ServerLink? = allServerLinks(context).firstOrNull {
        it.desktopId == desktopId && it.routes.clientRouteId == clientRouteId
    }

    fun allServerLinks(context: Context): List<ServerLink> {
        val raw = storage(context).readString(KEY_SERVERS, "[]")
        val array = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                runCatching {
                    add(
                        ServerLink(
                            desktopId = item.getString("desktop_id"),
                            desktopName = item.optString("desktop_name", "SignalASI Desktop"),
                            desktopFingerprint = item.getString("desktop_fingerprint"),
                            signalName = item.optString("signal_name", item.getString("desktop_id")),
                            routes = Routes(item.getString("server_route_id"), item.getString("client_route_id")),
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
        val remaining = links.filterNot { it.desktopId == desktopId }
        write(context, remaining)
    }

    @Synchronized
    fun clear(context: Context) {
        storage(context).clear()
    }

    fun makeEnvelope(payload: JSONObject, sourceId: String, targetId: String): JSONObject {
        require(payload.optString("content").toByteArray(Charsets.UTF_8).size <= MAX_TEXT_BYTES) { "Text exceeds Link limit" }
        val now = System.currentTimeMillis()
        val requestedMessageId = payload.optString("message_id")
        val messageId = runCatching { UUID.fromString(requestedMessageId).toString() }
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
        require(envelope.toString().toByteArray(Charsets.UTF_8).size <= MAX_ENVELOPE_BYTES) { "Envelope exceeds Link limit" }
        return envelope
    }

    fun pairingAccess(source: JSONObject?): PairingAccess? {
        val value = source ?: return null
        if (value.optString("contract_version") != ACCESS_CONTRACT ||
            value.optInt("version") != 1
        ) return null
        val profile = value.optString("profile")
        if (profile !in setOf(ACCESS_RESTRICTED, ACCESS_DESKTOP_EXECUTOR)) return null
        val scopes = value.optJSONArray("scopes").toStringSet()
        val restrictedScopes = setOf(
            SCOPE_AGENT_CHAT,
            SCOPE_EXPLICIT_ATTACHMENTS,
            SCOPE_TASK_WORKSPACE
        )
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

    fun encryptPairingClaim(claim: JSONObject, qr: JSONObject): JSONObject {
        require(validatePairingQr(qr)) { "Invalid SignalASI Link v1 pairing QR" }
        val token = qr.getString("pairing_token")
        val serverRouteId = qr.getString("server_route_id")
        val key = Base64.getUrlDecoder().decode(qr.getString("pairing_secret"))
        val nonce = ByteArray(12).also { random.nextBytes(it) }
        val aad = "$NAME|$VERSION|$token|$serverRouteId".toByteArray(Charsets.UTF_8)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(claim.toString().toByteArray(Charsets.UTF_8))
        return JSONObject()
            .put("type", "signalasi_pairing_ciphertext")
            .put("protocol", NAME)
            .put("version", VERSION)
            .put("pairing_token", token)
            .put("server_route_id", serverRouteId)
            .put("nonce", Base64.getUrlEncoder().withoutPadding().encodeToString(nonce))
            .put("ciphertext", Base64.getUrlEncoder().withoutPadding().encodeToString(ciphertext))
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
        val values = allServerLinks(context).filterNot { it.desktopId == link.desktopId } + link
        write(context, values)
    }

    private fun write(context: Context, links: List<ServerLink>) {
        val array = JSONArray()
        links.forEach { array.put(it.toJson()) }
        storage(context).writeString(KEY_SERVERS, array.toString())
    }

    private fun storage(context: Context): AgentEncryptedPreferences =
        AgentEncryptedPreferences(context.applicationContext, PREFS)

    private fun JSONArray?.toStringSet(): Set<String> = buildSet {
        val source = this@toStringSet ?: return@buildSet
        for (index in 0 until source.length()) {
            source.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
        }
    }
}
