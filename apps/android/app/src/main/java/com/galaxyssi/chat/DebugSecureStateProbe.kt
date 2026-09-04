package com.galaxyssi.chat

import android.content.Context
import android.content.pm.ApplicationInfo
import org.json.JSONArray
import org.json.JSONObject

internal object DebugSecureStateProbe {
    private const val STORAGE = "android-keystore-aes-gcm"
    private const val MAX_REQUEST_BYTES = 512 * 1024
    private val sensitiveContactKeys = setOf(
        "access_token",
        "api_key",
        "authorization",
        "client_route_id",
        "cloud_api_key",
        "identity_fingerprint",
        "identity_public_key",
        "pairing_access",
        "pairing_secret",
        "pairing_token",
        "private_key",
        "secret",
        "signal_bundle"
    )

    fun run(context: Context, request: JSONObject): JSONObject {
        check(context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            "Secure state probe is unavailable in release builds"
        }
        require(request.toString().toByteArray(Charsets.UTF_8).size <= MAX_REQUEST_BYTES) {
            "Secure state probe request is too large"
        }
        val requestId = request.optString("request_id")
        val action = request.optString("action", "snapshot")
        when (action) {
            "snapshot" -> Unit
            "replace_app_store" -> {
                val state = request.optJSONObject("state")
                    ?: throw IllegalArgumentException("Debug app store state is required")
                AppStore.replaceDebugState(context, state)
            }
            "patch_contact" -> {
                val contactId = request.optString("contact_id")
                val patch = request.optJSONObject("patch")
                    ?: throw IllegalArgumentException("Debug contact patch is required")
                check(AppStore.patchDebugContact(context, contactId, patch)) {
                    "Debug contact was not found"
                }
            }
            else -> throw IllegalArgumentException("Unsupported secure state probe action")
        }
        return JSONObject()
            .put("request_id", requestId)
            .put("ok", true)
            .put("storage", STORAGE)
            .put("state", snapshot(context, request.optString("expected_pc_fingerprint")))
    }

    private fun snapshot(context: Context, expectedPcFingerprint: String): JSONObject {
        val verifiedPcFingerprint = GalaxySSICrypto.verifiedPcFingerprint()
        return JSONObject()
            .put("profile", redactObject(AppStore.profile(context)))
            .put("contacts", redactArray(AppStore.contacts(context)))
            .put("friend_requests", redactArray(AppStore.friendRequests(context)))
            .put(
                "server_links",
                JSONArray().apply {
                    GalaxySSILinkProtocol.allServerLinks(context).forEach { link ->
                        put(
                            JSONObject()
                                .put("desktop_id", link.desktopId)
                                .put("paired", link.paired)
                                .put(
                                    "cryptographically_ready",
                                    GalaxySSILinkProtocol.isCryptographicallyReady(context, link)
                                )
                                .put("has_desktop_session", GalaxySSICrypto.hasDesktopSession(context, link.desktopId))
                                .put("access_profile", link.accessProfile)
                        )
                    }
                }
            )
            .put(
                "trust",
                JSONObject()
                    .put("pc_verified", verifiedPcFingerprint.isNotBlank())
                    .put(
                        "expected_pc_fingerprint_matches",
                        expectedPcFingerprint.isNotBlank() &&
                            verifiedPcFingerprint.equals(expectedPcFingerprint, ignoreCase = true)
                    )
            )
            .put("local_identity_sha256", GalaxySSICrypto.localIdentitySha256())
    }

    private fun redactArray(source: JSONArray): JSONArray {
        val output = JSONArray()
        for (index in 0 until source.length()) {
            when (val value = source.opt(index)) {
                is JSONObject -> output.put(redactObject(value))
                is JSONArray -> output.put(redactArray(value))
                else -> output.put(value)
            }
        }
        return output
    }

    private fun redactObject(source: JSONObject): JSONObject {
        val output = JSONObject()
        source.keys().forEach { key ->
            val value = source.opt(key)
            when {
                sensitiveContactKeys.contains(key.lowercase()) -> {
                    output.put("has_$key", value != null && value != JSONObject.NULL && value.toString().isNotBlank())
                }
                value is JSONObject -> output.put(key, redactObject(value))
                value is JSONArray -> output.put(key, redactArray(value))
                else -> output.put(key, value)
            }
        }
        return output
    }
}
