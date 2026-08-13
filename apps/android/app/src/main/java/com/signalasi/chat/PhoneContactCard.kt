package com.signalasi.chat

import org.json.JSONObject

/** Public, signed identity card exchanged through a QR code. */
internal object PhoneContactCard {
    const val TYPE = "signalasi_contact"
    const val VERSION = 1
    const val REQUEST_TYPE = "signalasi_contact_request"
    const val BUNDLE_RESPONSE_TYPE = "signalasi_contact_bundle"
    const val CONTROL_MAX_AGE_MILLIS = 24L * 60L * 60L * 1_000L

    private val fingerprintPattern = Regex("^[a-fA-F0-9]{64}$")
    private val signalasiIdPattern = Regex("^signalasi:[a-fA-F0-9]{16}$")
    private val inboxTopicPattern = Regex(
        "^signalasichat/v1/contact/[A-Za-z0-9_-]{22}/inbox$"
    )
    private val signedFields = listOf(
        "type",
        "version",
        "signalasi_id",
        "name",
        "identity_public_key",
        "identity_fingerprint",
        "mqtt_inbox_topic",
        "device_id",
        "created_at"
    )
    private val signedControlFields = listOf(
        "type",
        "version",
        "control_id",
        "from",
        "to",
        "reply_topic",
        "contact_card_signature",
        "bundle_identity_fingerprint",
        "time"
    )

    fun canonicalBytes(card: JSONObject): ByteArray = buildString {
        signedFields.forEach { key ->
            val value = card.opt(key)?.toString().orEmpty()
            append(key.length).append(':').append(key)
            append(value.length).append(':').append(value).append('|')
        }
    }.toByteArray(Charsets.UTF_8)

    fun isStructurallyValid(card: JSONObject): Boolean {
        if (card.optString("type") != TYPE || card.optInt("version") != VERSION) return false
        val signalasiId = card.optString("signalasi_id")
        val name = card.optString("name")
        val publicKey = card.optString("identity_public_key")
        val fingerprint = card.optString("identity_fingerprint")
        val inboxTopic = card.optString("mqtt_inbox_topic")
        val deviceId = card.optString("device_id")
        val createdAt = card.optLong("created_at")
        return signalasiIdPattern.matches(signalasiId) &&
            name.isNotBlank() && name.length <= 64 &&
            publicKey.length in 40..256 &&
            fingerprintPattern.matches(fingerprint) &&
            signalasiId.substringAfter(':').equals(fingerprint.take(16), ignoreCase = true) &&
            inboxTopicPattern.matches(inboxTopic) &&
            SignalASILinkProtocol.validRouteId(deviceId) &&
            createdAt > 0L &&
            card.optString("signature").length in 40..256
    }

    fun canonicalControlBytes(payload: JSONObject): ByteArray = buildString {
        signedControlFields.forEach { key ->
            val value = payload.opt(key)?.toString().orEmpty()
            append(key.length).append(':').append(key)
            append(value.length).append(':').append(value).append('|')
        }
    }.toByteArray(Charsets.UTF_8)

    fun isFreshControlPayload(payload: JSONObject, nowMillis: Long = System.currentTimeMillis()): Boolean {
        val type = payload.optString("type")
        val card = cardFromControlPayload(payload) ?: return false
        val sentAt = payload.optLong("time")
        return type in setOf(REQUEST_TYPE, BUNDLE_RESPONSE_TYPE) &&
            payload.optInt("version") == VERSION &&
            payload.optString("control_id").isNotBlank() &&
            payload.optString("from") == card.optString("signalasi_id") &&
            signalasiIdPattern.matches(payload.optString("to")) &&
            payload.optString("reply_topic") == card.optString("mqtt_inbox_topic") &&
            payload.optString("contact_card_signature") == card.optString("signature") &&
            payload.optString("bundle_identity_fingerprint")
                .equals(card.optString("identity_fingerprint"), ignoreCase = true) &&
            payload.optString("control_signature").length in 40..256 &&
            sentAt in (nowMillis - CONTROL_MAX_AGE_MILLIS)..(nowMillis + 60_000L)
    }

    fun cardFromControlPayload(payload: JSONObject): JSONObject? =
        payload.optJSONObject("contact_card")
            ?.takeIf(::isStructurallyValid)

    fun inboxTopic(routeId: String): String {
        require(SignalASILinkProtocol.validRouteId(routeId)) { "Invalid phone contact route" }
        return "${SignalASILinkProtocol.TOPIC_ROOT}/contact/$routeId/inbox"
    }

    fun isAddressedToLocalIdentity(payload: JSONObject, localSignalasiId: String): Boolean =
        payload.optString("to") == localSignalasiId
}
