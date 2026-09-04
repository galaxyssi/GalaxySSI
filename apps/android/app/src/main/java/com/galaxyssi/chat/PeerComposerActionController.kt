package com.galaxyssi.chat

import android.content.pm.PackageManager
import android.net.Uri
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
            sendImageForChatContact(contact, uri)
        } else {
            contentResolver.delete(uri, null, null)
        }
    } else if (uri != null) {
        contentResolver.delete(uri, null, null)
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
