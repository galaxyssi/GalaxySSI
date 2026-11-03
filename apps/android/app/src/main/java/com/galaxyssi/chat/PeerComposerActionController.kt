package com.galaxyssi.chat

import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.LinearLayout
import java.util.WeakHashMap

private data class PeerComposerActionState(
    var trayExpanded: Boolean = false,
    var pendingCameraUri: Uri? = null,
    var pendingCameraContactId: String? = null
)

private val peerComposerActionStates = WeakHashMap<MainActivity, PeerComposerActionState>()

private fun MainActivity.peerComposerActionState(): PeerComposerActionState =
    peerComposerActionStates.getOrPut(this) { PeerComposerActionState() }

internal fun MainActivity.isChatActionTrayExpanded(): Boolean =
    peerComposerActionState().trayExpanded

internal fun MainActivity.setChatActionTrayRequested(expanded: Boolean) {
    peerComposerActionState().trayExpanded = expanded
}

internal fun MainActivity.chatActionTrayView(): LinearLayout =
    findViewById(R.id.chatAttachmentActionTray)

internal fun MainActivity.collapseChatActionTrayOnBack(): Boolean {
    if (!isChatActionTrayExpanded()) return false
    setChatActionTrayExpanded(false)
    return true
}

internal fun MainActivity.rememberPendingChatCamera(uri: Uri, contactId: String) {
    peerComposerActionState().apply {
        pendingCameraUri = uri
        pendingCameraContactId = contactId
    }
}

internal fun MainActivity.clearPendingChatCamera(): Uri? {
    val state = peerComposerActionState()
    val uri = state.pendingCameraUri
    state.pendingCameraUri = null
    state.pendingCameraContactId = null
    return uri
}

internal fun MainActivity.savePendingChatCamera(out: Bundle) {
    val state = peerComposerActionState()
    out.putString("chat_camera_uri", state.pendingCameraUri?.toString())
    out.putString("chat_camera_contact", state.pendingCameraContactId)
}

internal fun MainActivity.restorePendingChatCamera(saved: Bundle?) {
    val uri = saved?.getString("chat_camera_uri")?.let(Uri::parse) ?: return
    val contactId = saved.getString("chat_camera_contact") ?: return
    rememberPendingChatCamera(uri, contactId)
}

internal fun MainActivity.handleChatCameraActivityResult(
    requestCode: Int,
    resultCode: Int
): Boolean {
    if (requestCode != REQUEST_CHAT_CAMERA) return false
    val state = peerComposerActionState()
    val uri = state.pendingCameraUri
    val contactId = state.pendingCameraContactId
    state.pendingCameraUri = null
    state.pendingCameraContactId = null
    if (resultCode == android.app.Activity.RESULT_OK && uri != null && contactId != null) {
        val contact = selectedContact?.takeIf { it.id == contactId }
            ?: buildChatContacts().firstOrNull { it.id == contactId }
        if (contact != null) {
            val captured = PrivateCameraStorage.finish(this, uri, accepted = true)
            if (captured != null) previewPickedAttachments(listOf(captured), camera = true, contactId = contact.id)
            else android.widget.Toast.makeText(this, R.string.agent_attachment_camera_unavailable,
                android.widget.Toast.LENGTH_SHORT).show()
        } else {
            PrivateCameraStorage.finish(this, uri, accepted = false)
        }
    } else if (uri != null) {
        PrivateCameraStorage.finish(this, uri, accepted = false)
    }
    return true
}

internal fun MainActivity.handleChatCameraPermissionResult(
    requestCode: Int,
    grantResults: IntArray
): Boolean {
    if (requestCode != REQUEST_CHAT_CAMERA_PERMISSION) return false
    if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
        openChatCamera()
    }
    return true
}

internal fun MainActivity.renderChatActionTray(visible: Boolean) {
    chatActionTrayView().visibility = if (visible) View.VISIBLE else View.GONE
}
