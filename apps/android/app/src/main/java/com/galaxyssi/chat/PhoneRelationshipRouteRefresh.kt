package com.galaxyssi.chat

import org.json.JSONObject

/** Rotates transport routes only for an already trusted copy of the same signed identity. */
internal object PhoneRelationshipRouteRefresh {
    fun apply(
        existing: JSONObject,
        remoteCard: JSONObject,
        linkSecret: String,
        clientRouteId: String,
        localFingerprint: String,
        nowMillis: Long = System.currentTimeMillis()
    ): JSONObject? {
        val existingId = existing.optString("galaxyssi_id").ifBlank { existing.optString("id") }
        val remoteId = remoteCard.optString("galaxyssi_id")
        val existingFingerprint = existing.optString("identity_fingerprint")
        val remoteFingerprint = remoteCard.optString("identity_fingerprint")
        if (existingId.isBlank() || existingId != remoteId ||
            existing.optBoolean("deleted", false) ||
            existing.optString("trust_state") != "verified" ||
            existingFingerprint.isBlank() ||
            !existingFingerprint.equals(remoteFingerprint, ignoreCase = true) ||
            !GalaxySSILinkProtocol.validLinkSecret(linkSecret) ||
            !GalaxySSILinkProtocol.validRouteId(clientRouteId) ||
            localFingerprint.isBlank() ||
            localFingerprint.equals(remoteFingerprint, ignoreCase = true)
        ) return null

        return JSONObject(existing.toString()).apply {
            put("client_route_id", clientRouteId)
            put("link_secret", linkSecret)
            put("local_identity_fingerprint", localFingerprint)
            put("identity_public_key", remoteCard.optString("identity_public_key"))
            put("identity_fingerprint", remoteFingerprint)
            put("contact_card", JSONObject(remoteCard.toString()))
            remoteCard.optJSONObject("signal_bundle")?.let { bundle ->
                put("signal_bundle", JSONObject(bundle.toString()))
            }
            put("relationship_rotated_at", nowMillis)
            put("deleted", false)
        }
    }
}
