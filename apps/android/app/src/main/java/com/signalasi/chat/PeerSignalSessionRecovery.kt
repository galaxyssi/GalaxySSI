package com.signalasi.chat

import android.content.Context
import android.util.Log
import org.json.JSONObject

internal object PeerSignalSessionRecoveryGate {
    internal const val REQUEST_COOLDOWN_MILLIS = 60_000L
    private val requestedAt = mutableMapOf<String, Long>()

    @Synchronized
    fun begin(contactId: String, nowMillis: Long = System.currentTimeMillis()): Boolean {
        if (contactId.isBlank()) return false
        val previous = requestedAt[contactId]
        if (previous != null && nowMillis - previous < REQUEST_COOLDOWN_MILLIS) return false
        requestedAt[contactId] = nowMillis
        return true
    }

    @Synchronized
    fun requestFailed(contactId: String) {
        requestedAt.remove(contactId)
    }

    @Synchronized
    fun sessionHealthy(contactId: String) {
        requestedAt.remove(contactId)
    }

    @Synchronized
    internal fun clearForTest() {
        requestedAt.clear()
    }
}

internal object PeerSignalBundlePolicy {
    fun replacesExistingSession(controlType: String): Boolean = controlType in setOf(
        PhoneContactCard.BUNDLE_REFRESH_TYPE,
        PhoneContactCard.BUNDLE_RESPONSE_TYPE
    )
}

internal object PeerSignalSessionRecoveryCoordinator {
    private const val TAG = "PeerSignalRecovery"

    fun decryptOrRequestRefresh(
        context: Context,
        contactId: String,
        wire: JSONObject
    ): JSONObject? = when (val result = SignalASICrypto.decryptEnvelopeDetailed(wire)) {
        is SignalASICrypto.EnvelopeDecryptionResult.Success -> {
            PeerSignalSessionRecoveryGate.sessionHealthy(contactId)
            result.payload
        }
        is SignalASICrypto.EnvelopeDecryptionResult.Failure -> {
            if (PeerSignalSessionRecoveryGate.begin(contactId)) {
                if (SignalASIMqttMessagePublisher.requestSignalBundle(context, contactId)) {
                    Log.w(
                        TAG,
                        "Signal session refresh requested contact=$contactId " +
                            "error=${result.error.javaClass.simpleName}"
                    )
                } else {
                    PeerSignalSessionRecoveryGate.requestFailed(contactId)
                    Log.e(TAG, "Signal session refresh could not be published contact=$contactId")
                }
            }
            null
        }
        SignalASICrypto.EnvelopeDecryptionResult.Rejected -> null
    }

    fun reencryptPendingMessages(context: Context, contactId: String): Int {
        val routes = AppStore.phoneRoutesForIdentity(context, contactId) ?: return 0
        return SignalASILinkDeliveryStore.reencryptRecoverableMessages(
            context,
            contactId,
            routes.up
        ) { applicationEnvelope ->
            SignalASICrypto.encryptPayloadForContact(contactId, applicationEnvelope)
        }
    }
}
