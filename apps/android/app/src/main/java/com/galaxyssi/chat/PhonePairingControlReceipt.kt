package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal object PhonePairingControlReceipt {
    fun matches(payload: JSONObject, receipt: JSONObject): Boolean =
        receipt.optString("type") == PhoneContactCard.RECEIPT_TYPE &&
            payload.optString("type") != PhoneContactCard.RECEIPT_TYPE &&
            payload.optString("control_id").isNotBlank() &&
            receipt.optString("ack_control_id") == payload.optString("control_id") &&
            receipt.optString("from") == payload.optString("to") &&
            receipt.optString("to") == payload.optString("from") &&
            receipt.optString("ack_payload_hash") == payloadHash(payload)

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
