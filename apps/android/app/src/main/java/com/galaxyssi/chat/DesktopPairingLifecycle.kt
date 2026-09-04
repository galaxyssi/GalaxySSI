package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal data class DesktopPairingRemoval(
    val desktopId: String,
    val contactIds: Set<String>
)

/** Owns the complete, idempotent cleanup of one revoked Desktop relationship. */
internal object DesktopPairingLifecycle {
    fun belongsToDesktop(contact: JSONObject, desktopId: String): Boolean {
        val cleanDesktopId = desktopId.trim()
        if (cleanDesktopId.isBlank()) return false
        val contactId = contact.optString("id").ifBlank {
            contact.optString("galaxyssi_id").ifBlank { contact.optString("hermes_id") }
        }
        return contact.optString("desktop_id") == cleanDesktopId ||
            contact.optString("parent_contact") == cleanDesktopId ||
            contactId == cleanDesktopId ||
            contactId.startsWith("$cleanDesktopId:")
    }

    fun remove(context: Context, desktopId: String): DesktopPairingRemoval {
        val appContext = context.applicationContext
        val cleanDesktopId = desktopId.trim()
        if (cleanDesktopId.isBlank()) return DesktopPairingRemoval("", emptySet())

        val removedContactIds = AppStore.deleteDesktopConnector(
            appContext,
            cleanDesktopId,
            deleteMessages = true
        )
        removedContactIds.forEach { contactId ->
            CloudConversationContextStore.removeContact(appContext, contactId)
        }
        AgentOutboundAttachmentTransferStore.discardDesktop(appContext, cleanDesktopId)
        AgentDesktopRemoteNativeTools.removeDesktop(appContext, cleanDesktopId)
        DesktopRemoteControl.clearDesktop(appContext, cleanDesktopId)
        GalaxySSIMqttClient.unsubscribeServer(appContext, cleanDesktopId)
        GalaxySSICrypto.clearDesktopTrust(appContext, cleanDesktopId)
        GalaxySSILinkProtocol.removeServer(appContext, cleanDesktopId)
        GalaxySSIMqttClient.forgetSecureChannel()
        return DesktopPairingRemoval(cleanDesktopId, removedContactIds)
    }
}
