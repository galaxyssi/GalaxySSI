package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.Toast
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class ConversationWindowActivity : MainActivity()

/** No Activity is retained by a window handle or an in-flight handoff. */
internal object AgentConversationWindows {
    const val WINDOW_KEY = "galaxyssi_conversation_window"
    const val CONVERSATION = "galaxyssi_window_conversation"
    const val HANDOFF = "galaxyssi_window_handoff"
    private val windows = ConcurrentHashMap<String, WeakReference<AgentConversationWindowController>>()
    private val pending = ConcurrentHashMap<String, Pair<WeakReference<AgentConversationWindowController>, String>>()
    private val opening = ConcurrentHashMap<String, String>()
    private val main = Handler(Looper.getMainLooper())
    private var changePosted = false

    fun register(controller: AgentConversationWindowController) { windows[controller.key] = WeakReference(controller) }
    fun unregister(controller: AgentConversationWindowController) {
        if (windows[controller.key]?.get() === controller) windows.remove(controller.key)
    }
    fun isOpen(conversation: String): Boolean = opening.containsKey(conversation) ||
        windows.values.any { it.get()?.conversationId == conversation }
    fun hasOtherVisible(controller: AgentConversationWindowController): Boolean = windows.values.any {
        it.get()?.let { other -> other !== controller && other.visible } == true
    }
    fun isHandoffPending(): Boolean = opening.isNotEmpty()

    fun changed() {
        main.post {
            if (!changePosted) {
                changePosted = true
                main.postDelayed({
                    changePosted = false
                    windows.values.mapNotNull { it.get() }.forEach { it.onDataChanged() }
                }, 200L)
            }
        }
    }

    fun open(source: AgentConversationWindowController) {
        val activity = source.activity
        if (activity.initialAgentHydrationPending || source.openingWindow) return
        source.save()
        val conversation = activity.agentTranscriptStore.activeConversation()
        val target = windows.values.mapNotNull { it.get() }
            .firstOrNull { it !== source && it.conversationId == conversation.id && !it.activity.isDestroyed }
        if (target != null) {
            val task = activity.getSystemService(ActivityManager::class.java).appTasks
                .firstOrNull { it.taskInfo.taskId == target.activity.taskId }
            if (task != null) {
                focusExisting(source, task, conversation.id)
                return
            }
        }
        if (opening.containsKey(conversation.id)) return
        val states = AgentWindowStateStore(activity)
        val existingTask = activity.getSystemService(ActivityManager::class.java).appTasks.firstOrNull {
            val taskKey = it.taskInfo.baseIntent.getStringExtra(WINDOW_KEY).orEmpty()
            it.taskInfo.taskId != activity.taskId && taskKey.isNotBlank() && states.selected(taskKey) == conversation.id
        }
        if (existingTask != null) {
            focusExisting(source, existingTask, conversation.id)
            return
        }
        val key = UUID.randomUUID().toString()
        val token = UUID.randomUUID().toString()
        source.openingWindow = true
        opening[conversation.id] = token
        pending[token] = WeakReference(source) to conversation.id
        try {
            activity.agentTranscriptStore.persistForWindow(conversation.id)
            AgentWindowStateStore(activity).save(key, conversation.id, source.snapshot())
            states.select(key, conversation.id)
            activity.startActivity(Intent(activity, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(WINDOW_KEY, key).putExtra(CONVERSATION, conversation.id).putExtra(HANDOFF, token)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_RETAIN_IN_RECENTS))
            main.postDelayed({
                pending.remove(token)?.first?.get()?.let {
                    it.openingWindow = false
                    Toast.makeText(it.activity, R.string.conversation_window_failed, Toast.LENGTH_LONG).show()
                }
                opening.remove(conversation.id, token)
            }, 30_000L)
        } catch (error: Exception) {
            pending.remove(token)
            opening.remove(conversation.id, token)
            source.openingWindow = false
            Toast.makeText(activity, R.string.conversation_window_failed, Toast.LENGTH_LONG).show()
        }
    }

    fun ready(token: String) {
        val transfer = pending.remove(token) ?: return
        opening.remove(transfer.second, token)
        transfer.first.get()?.opened(transfer.second)
    }

    private fun focusExisting(source: AgentConversationWindowController, task: ActivityManager.AppTask, id: String) {
        val token = UUID.randomUUID().toString()
        source.openingWindow = true
        opening[id] = token
        pending[token] = WeakReference(source) to id
        try {
            task.moveToFront()
            windows.values.mapNotNull { it.get() }.filter { it !== source }.forEach(::readyWindow)
            main.postDelayed({
                pending.remove(token)?.first?.get()?.let {
                    it.openingWindow = false
                    Toast.makeText(it.activity, R.string.conversation_window_failed, Toast.LENGTH_LONG).show()
                }
                opening.remove(id, token)
            }, 30_000L)
        } catch (_: Exception) {
            pending.remove(token)
            opening.remove(id, token)
            source.openingWindow = false
            Toast.makeText(source.activity, R.string.conversation_window_failed, Toast.LENGTH_LONG).show()
        }
    }

    fun readyWindow(controller: AgentConversationWindowController) {
        if (!controller.visible || controller.activity.initialAgentHydrationPending) return
        pending.entries.filter { it.value.first.get() !== controller && it.value.second == controller.conversationId }
            .map { it.key }.forEach(::ready)
    }
}

internal class AgentConversationWindowController(val activity: MainActivity) {
    val key: String = activity.intent?.getStringExtra(AgentConversationWindows.WINDOW_KEY)
        ?.takeIf { it.isNotBlank() } ?: "main"
    var conversationId = ""
        private set
    var visible = false
    var openingWindow = false
    var refreshList: (() -> Unit)? = null
    private var restoring = false
    private var lastTitle = ""
    private var pendingScroll: AgentWindowDraft? = null
    private val states = AgentWindowStateStore(activity)
    private val saveRunnable = Runnable { save() }

    fun attach() {
        AgentConversationWindows.register(this)
        activity.agentBrandLogo.setOnClickListener { AgentConversationWindows.open(this) }
        activity.findViewById<View>(R.id.agentBrandNewConversation).setOnClickListener {
            if (!activity.initialAgentHydrationPending && !openingWindow) activity.createAgentConversation()
        }
        activity.agentGoalInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                if (!restoring) {
                    activity.handler.removeCallbacks(saveRunnable)
                    activity.handler.postDelayed(saveRunnable, 250L)
                }
            }
            override fun afterTextChanged(s: android.text.Editable?) = Unit
        })
        awaitReady()
    }

    private fun awaitReady() {
        if (activity.isFinishing || activity.isDestroyed) return
        if (activity.initialAgentHydrationPending) {
            activity.handler.postDelayed({ awaitReady() }, 50L)
            return
        }
        selected(activity.agentTranscriptStore.activeConversation().id)
        if (activity is ConversationWindowActivity) {
            activity.findViewById<View>(R.id.startupConnectingView).apply {
                animate().cancel()
                visibility = View.GONE
            }
        }
        // Let the destination draw before releasing the source and its Recents snapshot.
        activity.window.decorView.postOnAnimation { activity.window.decorView.postOnAnimation {
            restoreScroll()
            val token = activity.intent.getStringExtra(AgentConversationWindows.HANDOFF).orEmpty()
            activity.intent.removeExtra(AgentConversationWindows.HANDOFF)
            AgentConversationWindows.ready(token)
            AgentConversationWindows.readyWindow(this)
        } }
    }

    fun snapshot(): AgentWindowDraft {
        val anchor = activity.captureAgentTranscriptScrollAnchor()
        return AgentWindowDraft(activity.agentGoalInput.text?.toString().orEmpty(),
            activity.agentInputAttachments.toList(), anchor?.entryId.orEmpty(), anchor?.topOffset ?: 0,
            activity.agentTranscriptAutoFollow)
    }

    fun save() {
        if (conversationId.isBlank() || restoring || activity.initialAgentHydrationPending) return
        states.save(key, conversationId, snapshot())
    }

    fun beforeSelection() { save() }

    fun selected(id: String) {
        if (activity.initialAgentHydrationPending || id == conversationId) return
        conversationId = id
        states.select(key, id)
        val draft = states.load(key, id)
        restoring = true
        try {
            activity.agentGoalInput.setText(draft.text)
            activity.agentGoalInput.setSelection(activity.agentGoalInput.length())
            activity.agentInputAttachments.clear()
            activity.agentInputAttachments.addAll(draft.attachments)
            activity.renderAgentInputAttachments()
            activity.agentTranscriptAutoFollow = draft.autoFollow
            pendingScroll = draft
        } finally { restoring = false }
        describe()
    }

    fun describe() {
        if (activity.initialAgentHydrationPending || activity.isDestroyed) return
        val conversation = activity.agentTranscriptStore.activeConversation()
        val title = activity.agentConversationDisplayTitle(conversation)
        if (title == lastTitle) return
        lastTitle = title
        @Suppress("DEPRECATION")
        activity.setTaskDescription(ActivityManager.TaskDescription(
            title, android.graphics.BitmapFactory.decodeResource(
                activity.resources, activity.applicationInfo.icon), activity.getColor(R.color.page_bg)))
    }

    fun restoreScroll() {
        val draft = pendingScroll ?: return
        if (draft.entryId.isBlank()) { pendingScroll = null; return }
        if (!activity.isAgentTranscriptAdapterInitialized()) return
        if (activity.agentTranscriptAdapter.indexOfEntry(draft.entryId) < 0) {
            if (!activity.agentTranscriptAllLoaded) activity.loadOlderAgentTranscriptEntries()
            else pendingScroll = null
            return
        }
        activity.restoreAgentTranscriptScrollAnchor(AgentTranscriptScrollAnchor(draft.entryId, draft.topOffset))
        pendingScroll = null
    }

    fun opened(id: String) {
        openingWindow = false
        if (activity.isDestroyed || activity.isFinishing || activity.agentTranscriptStore.activeConversation().id != id) return
        activity.createAgentConversation()
        if (activity.runtimePlaintextCleared) {
            activity.runtimePlaintextConversationId = activity.agentTranscriptStore.activeConversation().id
        }
    }

    fun resume() {
        visible = true
        if (conversationId.isNotBlank()) pendingScroll = states.load(key, conversationId)
        onDataChanged()
        AgentConversationWindows.readyWindow(this)
    }

    fun pause() { save(); visible = false }

    fun onDataChanged() {
        if (!visible || activity.isDestroyed || activity.isFinishing || activity.initialAgentHydrationPending) return
        refreshList?.invoke()
        val current = activity.agentTranscriptStore.activeConversation().id
        if (current != conversationId) selected(current)
        activity.refreshAgentConversationHeader()
        activity.refreshAgentTranscriptWindow(current)
    }

    fun destroy() {
        activity.handler.removeCallbacks(saveRunnable)
        AgentConversationWindows.unregister(this)
        refreshList = null
    }
}
