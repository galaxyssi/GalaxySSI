package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Pairing controls remain pending until an authenticated peer receipt, not a broker ACK. */
internal class PhonePairingDeliveryLedger(
    private val read: () -> JSONObject,
    private val write: (JSONObject) -> Unit,
    private val clock: () -> Long = System::currentTimeMillis
) {
    @Synchronized
    fun enqueue(topic: String, secret: String, payload: JSONObject, fingerprint: String): Boolean {
        val state = read()
        val items = active(state)
        val peer = payload.optString("to")
        val type = payload.optString("type")
        if (peer.isBlank() || fingerprint.isBlank() ||
            !PhoneContactCard.isControlType(type) || type == PhoneContactCard.RECEIPT_TYPE ||
            !PhoneContactCard.isFreshControlPayload(payload, clock()) ||
            !GalaxySSILinkProtocol.validLinkSecret(secret) ||
            runCatching { java.util.UUID.fromString(payload.getString("control_id")) }.isFailure
        ) return false
        val prior = items.firstOrNull {
            it.optString("peer") == peer && it.optString("type") == type &&
                it.optString("topic") == topic && it.optString("fingerprint") == fingerprint &&
                it.getJSONObject("payload").optBoolean("session_recovery") == payload.optBoolean("session_recovery")
        }
        if (prior != null) return true
        if (type in setOf(PhoneContactCard.APPROVAL_TYPE, PhoneContactCard.REJECTION_TYPE)) {
            items.removeAll { it.optString("peer") == peer && it.optString("type") in
                setOf(PhoneContactCard.APPROVAL_TYPE, PhoneContactCard.REJECTION_TYPE) }
        }
        if (items.size >= MAX_PENDING) return false
        items += JSONObject().put("peer", peer).put("fingerprint", fingerprint)
            .put("type", type).put("topic", topic).put("secret", secret)
            .put("payload", JSONObject(payload.toString())).put("hash", payloadHash(payload))
            .put("expires_at", payload.getLong("time") + PhoneContactCard.CONTROL_MAX_AGE_MILLIS)
            .put("attempts", 0).put("next_attempt_at", clock())
        save(state, items)
        return true
    }

    @Synchronized
    fun takeDue(): List<JSONObject> {
        val state = read()
        val items = active(state)
        val due = items.filter { it.optInt("attempts") < MAX_ATTEMPTS &&
            it.optLong("next_attempt_at") <= clock() }.take(4)
        due.forEach { item ->
            val attempt = item.optInt("attempts") + 1
            item.put("attempts", attempt).put("next_attempt_at", clock() +
                (2_000L shl (attempt - 1).coerceAtMost(4)).coerceAtMost(30_000L))
        }
        save(state, items)
        return due.map { JSONObject(it.toString()) }
    }

    /** Caller has already verified the relationship AEAD and signed remote identity card. */
    @Synchronized
    fun acknowledge(peer: String, fingerprint: String, receipt: JSONObject): Boolean {
        val state = read()
        val items = active(state)
        val matched = items.firstOrNull {
            it.optString("peer") == peer && it.optString("fingerprint") == fingerprint &&
                it.getJSONObject("payload").optString("control_id") == receipt.optString("ack_control_id") &&
                it.optString("hash") == receipt.optString("ack_payload_hash")
        } ?: return false
        items.remove(matched)
        save(state, items)
        return true
    }

    @Synchronized
    fun nextDelay(): Long? {
        val state = read()
        val items = active(state)
        save(state, items)
        return items.filter { it.optInt("attempts") < MAX_ATTEMPTS }
            .minOfOrNull { (it.optLong("next_attempt_at") - clock()).coerceAtLeast(250L) }
    }

    private fun active(state: JSONObject): MutableList<JSONObject> {
        val array = state.optJSONArray("pending") ?: JSONArray()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
            .filter { it.optLong("expires_at") > clock() }.take(MAX_PENDING).toMutableList()
    }

    private fun save(state: JSONObject, items: List<JSONObject>) {
        state.put("pending", JSONArray(items))
        write(state)
    }

    companion object {
        const val MAX_PENDING = 64
        const val MAX_ATTEMPTS = 20

        fun payloadHash(payload: JSONObject): String = MqttRouteAdvertisement.sha256(canonical(payload))

        private fun canonical(value: Any?): String = when (value) {
            is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") {
                JSONObject.quote(it) + ":" + canonical(value.get(it))
            }
            is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it)) }
            is String -> JSONObject.quote(value)
            null, JSONObject.NULL -> "null"
            else -> value.toString()
        }
    }
}

internal object PhonePairingDelivery {
    private var ledger: PhonePairingDeliveryLedger? = null

    @Synchronized
    fun ledger(context: Context): PhonePairingDeliveryLedger = ledger ?: run {
        val preferences = AgentEncryptedPreferences(context.applicationContext, "phone_pairing_delivery_v1")
        PhonePairingDeliveryLedger(
            read = { JSONObject(preferences.readString("state", "{}")) },
            write = { preferences.writeString("state", it.toString()) }
        ).also { ledger = it }
    }
}
