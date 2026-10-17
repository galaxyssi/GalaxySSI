package com.galaxyssi.chat

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ImageSpan
import android.view.View

internal object AgentReplyUnreadPolicy {
    fun token(entry: AgentTranscriptEntry): String? {
        if (entry.role != AgentTranscriptRole.ASSISTANT ||
            AgentTranscriptRenderPolicy.isLiveStream(entry) || entry.conversationId.isBlank()) return null
        return entry.dedupeKey.ifBlank { entry.turnId.ifBlank { entry.id } }.takeIf(String::isNotBlank)
    }

    fun isNewReply(entry: AgentTranscriptEntry, previous: AgentTranscriptEntry?): Boolean =
        token(entry) != null && (previous == null || token(previous) != token(entry))

    fun remaining(pending: Set<String>, rendered: List<AgentTranscriptEntry>): Set<String> =
        pending - rendered.mapNotNull(::token).toSet()
}

/** Persist identifiers only; reply contents remain in the encrypted transcript. */
internal object AgentReplyUnreadStore {
    private fun preferences(context: Context) = context.applicationContext
        .getSharedPreferences("agent_reply_unread", Context.MODE_PRIVATE)

    @Synchronized
    fun record(context: Context, entry: AgentTranscriptEntry, previous: AgentTranscriptEntry? = null) {
        if (ConversationScheduledTasks.isQuietLegacyStatus(context, entry)) return
        val token = AgentReplyUnreadPolicy.token(entry) ?: return
        if (!AgentReplyUnreadPolicy.isNewReply(entry, previous)) return
        val prefs = preferences(context)
        val pending = prefs.getStringSet(entry.conversationId, emptySet()).orEmpty()
        if (token !in pending) prefs.edit().putStringSet(entry.conversationId, pending + token).apply()
    }

    @Synchronized
    fun read(context: Context, conversationId: String, rendered: List<AgentTranscriptEntry>) {
        val prefs = preferences(context)
        val pending = prefs.getStringSet(conversationId, emptySet()).orEmpty()
        val remaining = AgentReplyUnreadPolicy.remaining(pending, rendered.filter { it.conversationId == conversationId })
        if (pending == remaining) return
        if (remaining.isEmpty()) prefs.edit().remove(conversationId).apply()
        else prefs.edit().putStringSet(conversationId, remaining).apply()
        AgentConversationWindows.changed()
    }

    @Synchronized
    fun hasUnread(context: Context, conversationId: String): Boolean =
        count(context, conversationId) > 0

    @Synchronized
    fun count(context: Context, conversationId: String): Int =
        preferences(context).getStringSet(conversationId, emptySet()).orEmpty().size

    @Synchronized
    fun snapshot(context: Context): Map<String, Set<String>> = preferences(context).all.mapNotNull { (id, value) ->
        val tokens = (value as? Set<*>)?.filterIsInstance<String>()?.toSet().orEmpty()
        if (tokens.isEmpty()) null else id to tokens
    }.toMap()

    @Synchronized
    fun discard(context: Context, conversationId: String, tokens: Set<String>): Int {
        if (tokens.isEmpty()) return 0
        val prefs = preferences(context)
        val pending = prefs.getStringSet(conversationId, emptySet()).orEmpty()
        val remaining = pending - tokens
        if (remaining == pending) return 0
        if (remaining.isEmpty()) prefs.edit().remove(conversationId).apply()
        else prefs.edit().putStringSet(conversationId, remaining).apply()
        AgentConversationWindows.changed()
        return pending.size - remaining.size
    }

    @Synchronized
    fun hasAny(context: Context): Boolean = preferences(context).all.values.any { it is Set<*> && it.isNotEmpty() }

    @Synchronized
    fun remove(context: Context, conversationId: String) { preferences(context).edit().remove(conversationId).apply() }

    @Synchronized
    fun clear(context: Context) { preferences(context).edit().clear().apply() }
}

internal fun MainActivity.isContactChatVisible(contactId: String): Boolean =
    conversationWindow.visible && window.decorView.hasWindowFocus() &&
        chatPage.isShown && selectedContact?.id == contactId

internal fun MainActivity.refreshReplyUnreadDot() {
    if (isFinishing || isDestroyed) return
    if (conversationWindow.visible && window.decorView.hasWindowFocus() &&
        agentPage.isShown && mainPage.visibility == View.VISIBLE && activeMainTab == PAGE_AGENT) {
        AgentReplyUnreadStore.read(this, agentRenderedConversationId, renderedAgentTranscriptSourceEntries)
    }
    // Keep the marker in the text run, so right alignment cannot separate it from the title.
    val title = agentSessionTitle.text.toString().removePrefix("\uFFFC\u00A0")
    val unread = AgentReplyUnreadStore.hasAny(this) || summaries.any { (contactId, summary) ->
        summary.unreadCount > 0 && ConversationHubContactHistoryPolicy.hasUnread(
            AppStore.contactById(this, contactId), summary.unreadCount, summary.lastAt)
    }
    val alreadyUnread = agentSessionTitle.text is Spanned &&
        (agentSessionTitle.text as Spanned).getSpans(0, agentSessionTitle.length(), ImageSpan::class.java).isNotEmpty()
    if (alreadyUnread == unread) return
    agentSessionTitle.text = if (unread) SpannableStringBuilder("\uFFFC\u00A0$title").apply {
        val dot = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.BLACK)
            setBounds(0, 0, dp(6), dp(6))
        }
        setSpan(ImageSpan(dot, ImageSpan.ALIGN_CENTER), 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    } else title
}
