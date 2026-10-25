package com.galaxyssi.chat

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.View
import java.lang.ref.WeakReference
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

/** UI binding only. Tool work and storage stay off the main thread; no Activity is retained globally. */
internal object AppVoiceControlBridge {
    private val main = Handler(Looper.getMainLooper())
    private var owner = WeakReference<MainActivity>(null)
    @Volatile private var snapshot: AgentNativeJsonObject = mapOf("voice_active" to false)
    private val anchors = VoiceAppContextStore()

    fun bind(activity: MainActivity) { owner = WeakReference(activity) }
    fun usesCommunicationAudio(): Boolean = owner.get()?.agentVoiceConversation?.communicationAudio?.active == true
    fun update(activity: MainActivity) {
        if (owner.get() !== activity) return
        val voice = activity.agentVoiceConversation
        val news = voice?.hasExternalForegroundHost() == true
        val contactVisible = !news && activity.chatPage.visibility == View.VISIBLE
        snapshot = mapOf("voice_active" to (voice?.session?.active == true),
            "conversation_id" to voice?.session?.conversationId?.takeIf { voice.session.active }
                .orEmpty().ifBlank { activity.agentTranscriptStore.activeConversation().id },
            "contact_id" to activity.selectedContact?.id.orEmpty().takeIf { contactVisible }.orEmpty(),
            "surface" to if (news) "news" else if (contactVisible) "contact" else "agent",
            "article_id" to voice?.contextArticleId.orEmpty(), "playback_state" to voice?.newsPlaybackState.orEmpty(),
            "playback_article_id" to voice?.newsArticleId.orEmpty())
    }
    fun capture(activity: MainActivity, traceId: String) { update(activity); anchors.capture(traceId, snapshot) }
    fun bindTurn(traceId: String, conversationId: String, turnId: String) = anchors.bind(traceId, conversationId, turnId)
    fun context(conversationId: String, turnId: String): AgentNativeJsonObject {
        val live = snapshot.takeIf { conversationId.isNotBlank() && it["conversation_id"] == conversationId }
        val origin = anchors.get(conversationId, turnId) ?: live?.takeIf { turnId.isBlank() }
            ?: return mapOf("voice_active" to false, "context_matches" to false)
        return origin + mapOf("playback" to mapOf("state" to (live?.get("playback_state") ?: "unavailable"),
            "article_id" to (live?.get("playback_article_id") ?: "")))
    }
    fun release(activity: MainActivity) {
        if (owner.get() === activity) { owner.clear(); snapshot = mapOf("voice_active" to false); anchors.clear() }
    }

    fun execute(operation: String, input: AgentNativeJsonObject, invocation: AgentNativeToolInvocation): AgentNativeJsonObject {
        check(Looper.myLooper() != Looper.getMainLooper()) { "App tools must not block the UI thread" }
        val activity = owner.get() ?: throw AppControlFailure("app_not_open", "Open GalaxySSI before navigating or controlling voice.")
        val contactId = input["contact_id"]?.toString().orEmpty()
        val contact = if (operation == "navigate" && input["destination"] == "contact") {
            if (!AppStore.isDirectPeerContact(activity, contactId))
                throw AppControlFailure("not_a_peer", "Choose an observed paired person/device ID.")
            AppStore.contactById(activity, contactId)?.let { Contact(contactId, it.optString("name"), it.optString("avatar")) }
                ?: throw AppControlFailure("contact_not_found", "Choose an observed contact ID.")
        } else null
        val task = FutureTask<AgentNativeJsonObject> {
            invocation.checkpoint()
            if (owner.get() !== activity || activity.isDestroyed || activity.isFinishing ||
                activity.agentVoiceConversation?.hasForegroundHost() != true)
                throw AppControlFailure("app_not_foreground", "Return to GalaxySSI before changing its page or playback.")
            if (invocation.context.conversationId.isBlank() ||
                invocation.context.conversationId != activity.agentTranscriptStore.activeConversation().id)
                throw AppControlFailure("app_conversation_changed", "The visible conversation changed. Do not redirect another session's UI.")
            val session = activity.agentVoiceConversation?.session
            if (session?.active == true && !session.acceptsAppControlTurn(invocation.context.turnId))
                throw AppControlFailure("voice_turn_changed", "A newer utterance owns the voice controls. Do not interrupt it with an older UI action.")
            if (operation == "playback") {
                val voice = activity.agentVoiceConversation!!
                if (!voice.session.active) throw AppControlFailure("voice_not_started", "Start voice mode using its microphone entry first.")
                voice.controlPlayback(input)
            } else {
                val destination = input["destination"]?.toString().orEmpty()
                val message = input["message"]?.toString().orEmpty()
                if (message.isNotBlank() && destination != "new_conversation")
                    throw AppControlFailure("invalid_navigation_message", "message is only valid for new_conversation.")
                if (destination != "news") activity.agentVoiceConversation?.returnToMainSurface()
                when (destination) {
                    "agent" -> activity.showAgentHomeFromChat()
                    "new_conversation" -> {
                        val active = activity.agentVoiceConversation?.session?.active == true
                        activity.agentVoiceConversation?.end()
                        activity.showAgentHomeFromChat()
                        activity.createAgentConversation()
                        if (active) activity.agentVoiceConversation?.startWhenForeground(message)
                        else if (message.isNotBlank()) activity.submitAgentGoal(goalOverride = message,
                            pendingVoiceConversationId = activity.agentTranscriptStore.activeConversation().id,
                            attachmentsOverride = emptyList())
                    }
                    "contact" -> {
                        activity.showChatPage(requireNotNull(contact))
                    }
                    "news" -> activity.startActivity(Intent(activity, ProactiveAttentionActivity::class.java))
                    "phone" -> {
                        activity.agentVoiceConversation?.end()
                        activity.startActivity(Intent(activity, PhoneAssistantActivity::class.java))
                    }
                    else -> throw AppControlFailure("invalid_destination", destination)
                }
                update(activity)
                mapOf("opened" to destination, "conversation_id" to activity.agentTranscriptStore.activeConversation().id,
                    "message_scheduled" to message.isNotBlank())
            }
        }
        main.post(task)
        try { return task.get(invocation.remainingTimeMillis.coerceAtMost(10_000), TimeUnit.MILLISECONDS) }
        catch (error: java.util.concurrent.ExecutionException) { throw (error.cause ?: error) }
        finally { task.cancel(false); main.removeCallbacks(task) }
    }

    fun refreshContact(contactId: String) { main.post {
        owner.get()?.takeIf { !it.isDestroyed && it.isContactChatVisible(contactId) }?.reloadChatHistoryIfChanged()
    } }
    fun interruptForCall() { main.post { owner.get()?.agentVoiceConversation?.end() } }

    fun attachNews(activity: ProactiveAttentionActivity, container: android.widget.LinearLayout) {
        owner.get()?.agentVoiceConversation?.attachExternalSurface(activity, container)
    }
    fun detachNews(activity: ProactiveAttentionActivity) { owner.get()?.agentVoiceConversation?.detachExternalSurface(activity) }
}
