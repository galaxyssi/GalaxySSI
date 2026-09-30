package com.galaxyssi.chat

import android.content.Context
import android.util.Log

internal object AgentDeferredTaskEncryption {
    fun prepare(context: Context, pending: GalaxySSILinkDeliveryStore.PendingMessage) = runCatching {
        GalaxySSILinkDeliveryStore.prepareFirstSend(context, pending) { envelope ->
            val desktop = AppStore.usesPcConnectorTunnel(context, pending.contactId)
            val target = if (desktop) AppStore.desktopIdForContact(context, pending.contactId) else pending.contactId
            if (envelope.optString("target_id") != target ||
                envelope.optString("source_id") != GalaxySSICrypto.localGalaxySSIId()) null
            else if (desktop) GalaxySSICrypto.encryptPayloadForDesktop(target, envelope)
            else GalaxySSICrypto.encryptPayloadForContact(target, envelope)
        }
    }.onFailure { Log.w("GalaxySSILink", "Deferred task encryption not ready", it) }.getOrNull()?.also {
        Log.i("GalaxySSILink", "Attachment-dependent task sealed source=${pending.clientSourceMessageId}")
    }
}
