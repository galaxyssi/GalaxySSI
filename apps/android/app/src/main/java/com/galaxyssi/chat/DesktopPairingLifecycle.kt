package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal data class DesktopPairingRemoval(
    val desktopId: String,
    val contactIds: Set<String>
)

/** Owns the complete, idempotent cleanup of one revoked Desktop relationship. */
internal object DesktopPairingLifecycle {
    private const val HISTORY_ONLY = "desktop_disconnected"

    fun isHistoryOnly(contact: JSONObject?): Boolean =
        contact?.optBoolean(HISTORY_ONLY, false) == true

    fun preserveAsHistory(contact: JSONObject, desktopId: String): Boolean {
        if (!belongsToDesktop(contact, desktopId) || isHistoryOnly(contact)) return false
        contact.put(HISTORY_ONLY, true)
        // Keep the record addressable by ID, but exclude it from active contact catalogs.
        contact.put("deleted", true)
        contact.put("trust_state", "disconnected")
        return true
    }

    fun clearHistoryOnly(contact: JSONObject) {
        contact.remove(HISTORY_ONLY)
    }

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
        disconnectTransport(appContext, cleanDesktopId)
        return DesktopPairingRemoval(cleanDesktopId, removedContactIds)
    }

    fun disconnectTransport(appContext: Context, cleanDesktopId: String) {
        AgentOutboundAttachmentTransferStore.discardDesktop(appContext, cleanDesktopId)
        AgentDesktopRemoteNativeTools.removeDesktop(appContext, cleanDesktopId)
        DesktopRemoteControl.clearDesktop(appContext, cleanDesktopId)
        GalaxySSIMqttClient.unsubscribeServer(appContext, cleanDesktopId)
        GalaxySSICrypto.clearDesktopTrust(appContext, cleanDesktopId)
        GalaxySSILinkProtocol.removeServer(appContext, cleanDesktopId)
        GalaxySSIMqttClient.forgetSecureChannel()
    }
}
