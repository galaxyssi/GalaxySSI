package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** Signed identity cards and one-time rendezvous state for phone-to-phone pairing. */
internal object PhoneContactCard {
    data class SessionClaim(val session: JSONObject, val alreadyClaimed: Boolean)

    const val TYPE = "opaque_contact"
    const val IDENTITY_TYPE = "opaque_identity"
    const val VERSION = 2
    private const val QR_TYPE = "p2"
    const val REQUEST_TYPE = "opaque_contact_claim"
    const val BUNDLE_RESPONSE_TYPE = "opaque_contact_confirm"
    const val BUNDLE_REFRESH_TYPE = "opaque_bundle_refresh"
    const val APPROVAL_TYPE = "opaque_contact_accept"
    const val REJECTION_TYPE = "opaque_contact_reject"
    const val CONTROL_MAX_AGE_MILLIS = 10L * 60L * 1_000L
    private const val PREFS = "opaque_phone_pairing_v2"
    private const val KEY_SESSIONS = "sessions"
    private const val KEY_ACCEPTED_CONTROLS = "accepted_controls"

    private val fingerprintPattern = Regex("^[a-fA-F0-9]{64}$")
    private val signalasiIdPattern = Regex("^signalasi:[a-fA-F0-9]{16}$")
    private val relationshipControlTypes = setOf(
        BUNDLE_RESPONSE_TYPE,
        BUNDLE_REFRESH_TYPE,
        APPROVAL_TYPE,
        REJECTION_TYPE
    )
    private val controlTypes = relationshipControlTypes + REQUEST_TYPE
    private val signedFields = listOf(
        "type",
        "version",
        "signalasi_id",
        "name",
        "identity_public_key",
        "identity_fingerprint",
        "bundle_identity_fingerprint",
        "pairing_token",
        "pairing_secret",
        "pairing_topic",
        "device_id",
        "created_at"
    )

    @Synchronized
    fun createQr(context: Context, profile: JSONObject): JSONObject {
        val now = System.currentTimeMillis()
        val token = SignalASILinkProtocol.newLinkSecret()
        val secret = SignalASILinkProtocol.newLinkSecret()
        val topic = SignalASILinkProtocol.pairingTopic(secret)
        val sessions = activeSessions(context, now).toMutableList()
        sessions += JSONObject()
            .put("token", token)
            .put("secret", secret)
            .put("topic", topic)
            .put("created_at", now)
            .put("expires_at", now + CONTROL_MAX_AGE_MILLIS)
        writeSessions(context, sessions)
        return baseIdentityCard(profile, TYPE)
            .put("pairing_token", token)
            .put("pairing_secret", secret)
            .put("pairing_topic", topic)
            .put("created_at", now)
            .also(::signCard)
    }

    fun identityCard(context: Context): JSONObject =
        baseIdentityCard(AppStore.profile(context), IDENTITY_TYPE)
            .put("created_at", System.currentTimeMillis())
            .also(::signCard)

    fun compactQr(card: JSONObject): JSONObject {
        require(isStructurallyValid(card)) { "Invalid phone pairing card" }
        return JSONObject()
            .put("t", QR_TYPE)
            .put("i", card.getString("signalasi_id"))
            .put("n", card.getString("name"))
            .put("k", card.getString("identity_public_key"))
            .put("h", card.getString("identity_fingerprint"))
            .put("x", card.getString("pairing_token"))
            .put("e", card.getString("pairing_secret"))
            .put("d", card.getString("device_id"))
            .put("c", card.getLong("created_at"))
            .put("s", card.getString("signature"))
    }

    fun normalizeQr(source: JSONObject): JSONObject? {
        if (source.optString("t") != QR_TYPE) return null
        val fingerprint = source.optString("h")
        val secret = source.optString("e")
        if (!SignalASILinkProtocol.validLinkSecret(secret) ||
            !SignalASILinkProtocol.validLinkSecret(source.optString("x"))
        ) return null
        val card = JSONObject()
            .put("type", TYPE)
            .put("version", VERSION)
            .put("signalasi_id", source.optString("i"))
            .put("name", source.optString("n"))
            .put("identity_public_key", source.optString("k"))
            .put("identity_fingerprint", fingerprint)
            .put("bundle_identity_fingerprint", fingerprint)
            .put("pairing_token", source.optString("x"))
            .put("pairing_secret", secret)
            .put("pairing_topic", SignalASILinkProtocol.pairingTopic(secret))
            .put("device_id", source.optString("d"))
            .put("created_at", source.optLong("c"))
            .put("signature", source.optString("s"))
        return card.takeIf(::isQrOfferValid)
    }

    fun controlPayload(
        type: String,
        targetSignalasiId: String,
        localCard: JSONObject,
        pairingToken: String = "",
        nowMillis: Long = System.currentTimeMillis()
    ): JSONObject {
        require(type in controlTypes) {
            "Unsupported phone pairing control type"
        }
        require(targetSignalasiId.isNotBlank()) { "Target identity is required" }
        if (type == REQUEST_TYPE) {
            require(SignalASILinkProtocol.validLinkSecret(pairingToken)) {
                "Pairing claim requires a one-time token"
            }
        }
        return JSONObject()
            .put("type", type)
            .put("version", VERSION)
            .put("control_id", UUID.randomUUID().toString())
            .put("from", localCard.optString("signalasi_id"))
            .put("to", targetSignalasiId)
            .put("contact_card", JSONObject(localCard.toString()))
            .put("time", nowMillis)
            .apply {
                if (type == REQUEST_TYPE) put("pairing_token", pairingToken)
            }
    }

    fun isControlType(type: String): Boolean = type in controlTypes

    fun isRelationshipControlType(type: String): Boolean = type in relationshipControlTypes

    @Synchronized
    fun activeRendezvousTopics(context: Context): Set<String> =
        activeSessions(context).mapTo(linkedSetOf()) { it.getString("topic") }

    @Synchronized
    fun nextRendezvousRefreshDelayMillis(
        context: Context,
        nowMillis: Long = System.currentTimeMillis()
    ): Long? = activeSessions(context, nowMillis)
        .minOfOrNull { it.optLong("expires_at") }
        ?.let { expiresAt -> (expiresAt - nowMillis + 1_000L).coerceAtLeast(1_000L) }

    @Synchronized
    fun sessionForTopic(context: Context, topic: String): JSONObject? =
        activeSessions(context).firstOrNull { it.optString("topic") == topic }

    @Synchronized
    fun claimSession(
        context: Context,
        topic: String,
        token: String,
        identityFingerprint: String
    ): SessionClaim? {
        val sessions = activeSessions(context).toMutableList()
        val index = sessions.indexOfFirst {
            it.optString("topic") == topic && it.optString("token") == token
        }
        if (index < 0) return null
        val session = sessions[index]
        val claimedFingerprint = session.optString("claimed_fingerprint")
        if (claimedFingerprint.isNotBlank() && !constantTimeEquals(
                claimedFingerprint,
                identityFingerprint
            )
        ) return null
        val alreadyClaimed = claimedFingerprint.isNotBlank()
        if (!alreadyClaimed) {
            session
                .put("claimed_fingerprint", identityFingerprint)
                .put("claimed_at", System.currentTimeMillis())
            sessions[index] = session
        }
        writeSessions(context, sessions)
        return SessionClaim(JSONObject(session.toString()), alreadyClaimed)
    }

    fun canonicalBytes(card: JSONObject): ByteArray = buildString {
        signedFields.forEach { key ->
            val value = card.opt(key)?.toString().orEmpty()
            append(key.length).append(':').append(key)
            append(value.length).append(':').append(value).append('|')
        }
    }.toByteArray(Charsets.UTF_8)

    fun isStructurallyValid(card: JSONObject): Boolean =
        isIdentityValid(card) && isQrOfferValid(card)

    fun isQrOfferValid(card: JSONObject): Boolean =
        isIdentityHeaderValid(card) &&
            card.optString("type") == TYPE &&
            SignalASILinkProtocol.validLinkSecret(card.optString("pairing_token")) &&
            SignalASILinkProtocol.validLinkSecret(card.optString("pairing_secret")) &&
            card.optString("pairing_topic") == SignalASILinkProtocol.pairingTopic(
                card.optString("pairing_secret")
            ) &&
            isFreshControlPayload(card) &&
            SignalASICrypto.verifyPublicIdentitySignature(
                card.optString("identity_public_key"),
                card.optString("identity_fingerprint"),
                canonicalBytes(card),
                card.optString("signature")
            )

    fun isIdentityValid(card: JSONObject): Boolean {
        if (!isIdentityHeaderValid(card)) return false
        val fingerprint = card.optString("identity_fingerprint")
        val bundle = card.optJSONObject("signal_bundle") ?: return false
        return SignalASICrypto.signalBundleFingerprint(bundle).equals(fingerprint, ignoreCase = true)
    }

    fun isFreshControlPayload(payload: JSONObject, nowMillis: Long = System.currentTimeMillis()): Boolean {
        val sentAt = payload.optLong("time", payload.optLong("created_at"))
        return sentAt in (nowMillis - CONTROL_MAX_AGE_MILLIS)..(nowMillis + 60_000L)
    }

    @Synchronized
    fun acceptControlMessage(
        context: Context,
        payload: JSONObject,
        nowMillis: Long = System.currentTimeMillis()
    ): Boolean {
        if (!isFreshControlPayload(payload, nowMillis)) return false
        val controlId = payload.optString("control_id")
        if (runCatching { UUID.fromString(controlId) }.isFailure) return false
        val storage = AgentEncryptedPreferences(context.applicationContext, PREFS)
        val stored = runCatching {
            JSONArray(storage.readString(KEY_ACCEPTED_CONTROLS, "[]"))
        }.getOrDefault(JSONArray())
        val active = mutableListOf<JSONObject>()
        var replayed = false
        for (index in 0 until stored.length()) {
            val item = stored.optJSONObject(index) ?: continue
            if (item.optLong("expires_at") < nowMillis) continue
            if (item.optString("id") == controlId) replayed = true
            active += JSONObject(item.toString())
        }
        if (replayed) return false
        active += JSONObject()
            .put("id", controlId)
            .put("expires_at", nowMillis + CONTROL_MAX_AGE_MILLIS)
        val encoded = JSONArray()
        active.takeLast(256).forEach(encoded::put)
        storage.writeString(KEY_ACCEPTED_CONTROLS, encoded.toString())
        return true
    }

    fun cardFromControlPayload(payload: JSONObject): JSONObject? =
        payload.optJSONObject("contact_card")?.takeIf(::isIdentityValid)

    fun isAddressedToLocalIdentity(payload: JSONObject, localSignalasiId: String): Boolean =
        payload.optString("to") == localSignalasiId

    private fun baseIdentityCard(profile: JSONObject, type: String): JSONObject {
        val bundle = SignalASICrypto.localSignalBundleJson()
        return JSONObject()
            .put("type", type)
            .put("version", VERSION)
            .put("signalasi_id", profile.getString("signalasi_id"))
            .put("name", profile.optString("name", "Me"))
            .put("identity_public_key", profile.getString("identity_public_key"))
            .put("identity_fingerprint", profile.getString("identity_fingerprint"))
            .put("signal_bundle", bundle)
            .put("bundle_identity_fingerprint", SignalASICrypto.signalBundleFingerprint(bundle))
            .put("device_id", profile.optString("device_id"))
            .put("pairing_token", "")
            .put("pairing_secret", "")
            .put("pairing_topic", "")
    }

    private fun signCard(card: JSONObject) {
        card.put("signature", SignalASICrypto.signLocalIdentity(canonicalBytes(card)))
    }

    private fun isIdentityHeaderValid(card: JSONObject): Boolean {
        if (card.optString("type") !in setOf(TYPE, IDENTITY_TYPE) || card.optInt("version") != VERSION) {
            return false
        }
        val signalasiId = card.optString("signalasi_id")
        val fingerprint = card.optString("identity_fingerprint")
        return signalasiIdPattern.matches(signalasiId) &&
            card.optString("name").isNotBlank() && card.optString("name").length <= 64 &&
            card.optString("identity_public_key").length in 40..256 &&
            fingerprintPattern.matches(fingerprint) &&
            signalasiId.substringAfter(':').equals(fingerprint.take(16), ignoreCase = true) &&
            card.optString("bundle_identity_fingerprint").equals(fingerprint, ignoreCase = true) &&
            card.optString("device_id").isNotBlank() &&
            card.optLong("created_at") > 0L &&
            card.optString("signature").length in 40..256
    }

    private fun activeSessions(
        context: Context,
        nowMillis: Long = System.currentTimeMillis()
    ): List<JSONObject> {
        val storage = AgentEncryptedPreferences(context.applicationContext, PREFS)
        val array = runCatching {
            JSONArray(storage.readString(KEY_SESSIONS, "[]"))
        }.getOrDefault(JSONArray())
        val active = buildList {
            for (index in 0 until array.length()) {
                val session = array.optJSONObject(index) ?: continue
                if (session.optLong("expires_at") >= nowMillis &&
                    SignalASILinkProtocol.validLinkSecret(session.optString("secret")) &&
                    session.optString("topic") == SignalASILinkProtocol.pairingTopic(
                        session.optString("secret")
                    )
                ) add(JSONObject(session.toString()))
            }
        }
        if (active.size != array.length()) writeSessions(context, active)
        return active
    }

    private fun writeSessions(context: Context, sessions: List<JSONObject>) {
        val array = JSONArray()
        sessions.takeLast(8).forEach(array::put)
        AgentEncryptedPreferences(context.applicationContext, PREFS)
            .writeString(KEY_SESSIONS, array.toString())
    }

    private fun constantTimeEquals(first: String, second: String): Boolean =
        MessageDigest.isEqual(
            first.toByteArray(Charsets.UTF_8),
            second.toByteArray(Charsets.UTF_8)
        )
}
