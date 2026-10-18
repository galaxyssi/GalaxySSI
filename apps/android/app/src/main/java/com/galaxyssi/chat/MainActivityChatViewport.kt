package com.galaxyssi.chat

import android.content.Context
import android.view.View
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

internal class ChatMessageLayoutManager(context: Context, private val afterLayout: () -> Unit) :
    LinearLayoutManager(context) {
    override fun onLayoutCompleted(state: RecyclerView.State?) {
        super.onLayoutCompleted(state)
        afterLayout()
    }
}

internal fun alignChatViewportToLatest(list: RecyclerView) {
    val layout = list.layoutManager as? LinearLayoutManager ?: return
    val last = (list.adapter?.itemCount ?: 0) - 1
    if (last < 0) return
    val view = layout.findViewByPosition(last)
    if (view == null) {
        layout.scrollToPosition(last)
    } else {
        val delta = layout.getDecoratedBottom(view) - (list.height - list.paddingBottom)
        if (delta != 0) list.scrollBy(0, delta)
    }
}

internal fun MainActivity.schedulePeerChatBottomAlignment() {
    if (peerChatBottomAlignmentScheduled || !peerChatViewport.followLatest ||
        peerChatViewport.suspended || runtimePlaintextCleared || chatPage.visibility != View.VISIBLE) return
    peerChatBottomAlignmentScheduled = true
    messageList.post {
        peerChatBottomAlignmentScheduled = false
        if (!isDestroyed && !runtimePlaintextCleared && !peerChatViewport.suspended &&
            peerChatViewport.followLatest && chatPage.visibility == View.VISIBLE &&
            selectedContact?.id == peerChatViewport.contactId &&
            messageList.scrollState != RecyclerView.SCROLL_STATE_DRAGGING) {
            alignChatViewportToLatest(messageList)
        }
    }
}

internal fun MainActivity.capturePeerChatScrollAnchor(): ChatMessageScrollAnchor? {
    val layout = messageList.layoutManager as? LinearLayoutManager ?: return null
    val position = layout.findFirstVisibleItemPosition()
    val message = messageAdapter?.messages?.getOrNull(position) ?: return null
    val view = layout.findViewByPosition(position) ?: return null
    return ChatMessageScrollAnchor(message.id, message.historySequence,
        layout.getDecoratedTop(view) - messageList.paddingTop)
}

internal fun MainActivity.restorePeerChatScrollAnchor(anchor: ChatMessageScrollAnchor?) {
    if (anchor == null) return
    val rows = messageAdapter?.messages ?: return
    val exact = rows.indexOfFirst { it.id == anchor.messageId }
    val position = if (exact >= 0) exact else rows.indexOfFirst { it.historySequence >= anchor.sequence }
    if (position >= 0) {
        (messageList.layoutManager as? LinearLayoutManager)
            ?.scrollToPositionWithOffset(position, anchor.topOffset)
    }
}

internal fun MainActivity.onPeerChatMessageSent(contactId: String) {
    if (chatPage.visibility != View.VISIBLE || selectedContact?.id != contactId ||
        contactId == CONTACT_SYSTEM.id) return
    val needsReload = peerChatViewport.pendingAnchor != null || historyHasNewer[contactId] == true ||
        historyLoadsInFlight.any { it.startsWith("latest:$contactId:") }
    if (!peerChatViewport.sent(contactId)) return
    if (needsReload && !runtimePlaintextCleared) {
        loadLatestChatHistory(contactId, force = true, scrollAfterLoad = true)
    }
    schedulePeerChatBottomAlignment()
}
