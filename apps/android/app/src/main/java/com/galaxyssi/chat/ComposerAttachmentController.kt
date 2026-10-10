package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.Toast
import java.util.WeakHashMap
import java.util.concurrent.Executors

internal const val REQUEST_COMPOSER_ATTACHMENT_EDIT = 2040
private const val ROUTE_AGENT = "agent"
private const val ROUTE_PEER = "peer"
private const val STATE_KEY = "composer_attachment_state"
private val draftPersistence = Executors.newSingleThreadExecutor { Thread(it, "composer-draft-store").apply { isDaemon = true } }
private data class ComposerAttachmentState(
    var route: String = "",
    var target: String = "",
    val peers: MutableMap<String, List<ComposerAttachmentItem>> = mutableMapOf(),
    val revisions: MutableMap<String, Long> = mutableMapOf()
)
private val states = WeakHashMap<MainActivity, ComposerAttachmentState>()
private fun MainActivity.composerAttachments() = states.getOrPut(this) { ComposerAttachmentState() }

internal fun MainActivity.rememberAttachmentPickerTarget(agent: Boolean) {
    composerAttachments().apply {
        route = if (agent) ROUTE_AGENT else ROUTE_PEER
        target = if (agent) agentTranscriptStore.activeConversation().id else selectedContact?.id.orEmpty()
    }
}

internal fun MainActivity.hasPendingPeerAttachmentPicker(): Boolean =
    composerAttachments().let { it.route == ROUTE_PEER && it.target.isNotBlank() }

internal fun MainActivity.previewPickedAttachments(uris: List<Uri>, camera: Boolean = false,
                                                 contactId: String? = null) {
    val state = composerAttachments()
    val route = if (contactId != null) ROUTE_PEER else state.route
    val target = contactId ?: state.target
    if (target.isBlank() || uris.isEmpty()) return
    val activeAgentTarget = route == ROUTE_AGENT && target == agentTranscriptStore.activeConversation().id
    val current = if (activeAgentTarget) agentInputAttachments.map { ComposerAttachmentItem.from(it.draftDescriptor()) }
        else state.peers[target].orEmpty()
    val app = applicationContext
    val owner = java.lang.ref.WeakReference(this)
    draftPersistence.execute {
        val base = if (route == ROUTE_AGENT && !activeAgentTarget) {
            val activity = owner.get() ?: return@execute
            AgentWindowStateStore(app).load(activity.conversationWindow.key, target).attachments
                .map { ComposerAttachmentItem.from(it.draftDescriptor()) }
        } else current
        val limit = if (route == ROUTE_AGENT) MAX_AGENT_ATTACHMENTS else 12
        val files = uris.distinct().take(limit).mapNotNull { uri ->
            runCatching { app.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            runCatching { owner.get()?.agentAttachmentMetadata(uri)?.let { ComposerAttachmentItem.from(it.descriptor()) } }.getOrNull()
        }
        owner.get()?.runOnUiThread {
            val activity = owner.get()?.takeUnless { it.isFinishing || it.isDestroyed } ?: return@runOnUiThread
            if (files.isEmpty()) return@runOnUiThread
            val combined = (base + files).distinctBy { it.uri }.take(limit)
            if (combined.size < (base + files).distinctBy { it.uri }.size || uris.distinct().size > limit) {
                Toast.makeText(activity, R.string.agent_attachment_rejected, Toast.LENGTH_LONG).show()
            }
            activity.launchComposerEditor(combined, route, target, combined.indexOfFirst { it.id == files[0].id }.coerceAtLeast(0), camera)
        }
    }
}

private fun MainActivity.launchComposerEditor(items: List<ComposerAttachmentItem>, route: String,
                                             target: String, index: Int, camera: Boolean = false,
                                             cropImmediately: Boolean = false) {
    startActivityForResult(Intent(this, ComposerAttachmentEditorActivity::class.java)
        .putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(items))
        .putExtra(ComposerAttachmentEditorActivity.ROUTE, route)
        .putExtra(ComposerAttachmentEditorActivity.TARGET, target)
        .putExtra(ComposerAttachmentEditorActivity.INDEX, index)
        .putExtra(ComposerAttachmentEditorActivity.CAMERA, camera)
        .putExtra("crop_immediately", cropImmediately), REQUEST_COMPOSER_ATTACHMENT_EDIT)
}

internal fun MainActivity.editAgentInputAttachment(attachment: AgentInputAttachment, cropImmediately: Boolean = false) {
    val files = agentInputAttachments.map { ComposerAttachmentItem.from(it.draftDescriptor()) }
    val index = files.indexOfFirst { it.id == attachment.id }
    if (index >= 0) launchComposerEditor(files, ROUTE_AGENT, agentTranscriptStore.activeConversation().id, index,
        cropImmediately = cropImmediately)
}

internal fun MainActivity.handleComposerAttachmentResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST_COMPOSER_ATTACHMENT_EDIT) return false
    if (resultCode != Activity.RESULT_OK || data == null) return true
    val route = data.getStringExtra(ComposerAttachmentEditorActivity.ROUTE)
    val target = data.getStringExtra(ComposerAttachmentEditorActivity.TARGET).orEmpty()
    if (data.getBooleanExtra("retake", false)) {
        if (route == ROUTE_AGENT && target == agentTranscriptStore.activeConversation().id) openAgentCamera()
        else if (route == ROUTE_PEER && target == selectedContact?.id) openChatCamera()
        return true
    }
    val files = runCatching { ComposerAttachmentItem.decode(data.getStringExtra(ComposerAttachmentEditorActivity.ITEMS) ?: "[]") }
        .getOrElse { return true }
    if (route == ROUTE_AGENT) {
        val accepted = files.filter { it.size in 0..MAX_AGENT_ATTACHMENT_BYTES }.take(MAX_AGENT_ATTACHMENTS)
        if (accepted.size != files.size) Toast.makeText(this, R.string.agent_attachment_rejected, Toast.LENGTH_LONG).show()
        val attachments = accepted.map { it.inputAttachment() }
        if (target == agentTranscriptStore.activeConversation().id) {
            agentInputAttachments.clear(); agentInputAttachments.addAll(attachments)
            renderAgentInputAttachments()
            conversationWindow.save()
        } else {
            val store = AgentWindowStateStore(this)
            val old = store.load(conversationWindow.key, target)
            store.save(conversationWindow.key, target, old.copy(attachments = attachments))
        }
    } else if (route == ROUTE_PEER && target.isNotBlank()) {
        setPeerComposerAttachments(target, files.take(12))
    }
    return true
}

internal fun ComposerAttachmentItem.inputAttachment() = AgentInputAttachment(id, Uri.parse(uri), name, mime, size, originalUri)

internal fun MainActivity.peerComposerAttachments(contactId: String = selectedContact?.id.orEmpty()): List<AgentInputAttachment> =
    composerAttachments().peers[contactId].orEmpty().map { it.inputAttachment() }

internal fun MainActivity.setPeerComposerAttachments(contactId: String, files: List<ComposerAttachmentItem>) {
    val state = composerAttachments()
    state.peers[contactId] = files.toList()
    state.revisions[contactId] = (state.revisions[contactId] ?: 0L) + 1L
    val app = applicationContext
    val encoded = ComposerAttachmentItem.encode(files)
    draftPersistence.execute {
        runCatching { AgentEncryptedDatabase(app, "peer_composer_drafts_v1").writeString(contactId, encoded) }
            .onFailure { android.util.Log.w("GalaxySSIComposer", "Could not persist attachment draft", it) }
    }
    if (selectedContact?.id == contactId) { renderPeerComposerAttachments(); updateInputActions() }
}

internal fun MainActivity.loadPeerComposerAttachments(contactId: String) {
    val state = composerAttachments()
    if (state.peers.containsKey(contactId)) { renderPeerComposerAttachments(); return }
    state.peers[contactId] = emptyList()
    val initialRevision = state.revisions[contactId] ?: 0L
    val app = applicationContext
    val owner = java.lang.ref.WeakReference(this)
    draftPersistence.execute {
        val files = runCatching { ComposerAttachmentItem.decode(
            AgentEncryptedDatabase(app, "peer_composer_drafts_v1").readString(contactId, "[]")) }.getOrDefault(emptyList())
        owner.get()?.runOnUiThread {
            val activity = owner.get()?.takeUnless { it.isFinishing || it.isDestroyed } ?: return@runOnUiThread
            if ((state.revisions[contactId] ?: 0L) != initialRevision) return@runOnUiThread
            state.peers[contactId] = files
            if (activity.selectedContact?.id == contactId) { activity.renderPeerComposerAttachments(); activity.updateInputActions() }
        }
    }
    renderPeerComposerAttachments()
}

internal fun MainActivity.renderPeerComposerAttachments() {
    if (runtimePlaintextCleared) return
    val scroll = findViewById<HorizontalScrollView>(R.id.chatAttachmentPreviewScroll)
    val row = findViewById<LinearLayout>(R.id.chatAttachmentPreviewList)
    row.removeAllViews()
    val contactId = selectedContact?.id.orEmpty()
    val files = composerAttachments().peers[contactId].orEmpty()
    scroll.visibility = if (files.isEmpty()) View.GONE else View.VISIBLE
    files.forEachIndexed { index, item ->
        row.addView(agentInputAttachmentCard(item.inputAttachment(),
            onPreview = { launchComposerEditor(files, ROUTE_PEER, contactId, index) },
            onCrop = { launchComposerEditor(files, ROUTE_PEER, contactId, index, cropImmediately = true) },
            onRemove = {
                setPeerComposerAttachments(contactId, files.filterNot { it.id == item.id })
            }))
    }
}

internal fun MainActivity.saveComposerAttachmentState(out: Bundle) {
    savePendingChatCamera(out)
    val state = composerAttachments()
    out.putBundle(STATE_KEY, Bundle().apply {
        putString("route", state.route); putString("target", state.target)
        putString("camera", pendingAgentCameraUri?.toString())
        // Other contacts are restored lazily from encrypted storage, not one large Binder bundle.
        val contactId = selectedContact?.id.orEmpty()
        putString("contact", contactId)
        putString("attachments", ComposerAttachmentItem.encode(state.peers[contactId].orEmpty()))
    })
}

internal fun MainActivity.restoreComposerAttachmentState(saved: Bundle?) {
    restorePendingChatCamera(saved)
    val bundle = saved?.getBundle(STATE_KEY) ?: return
    composerAttachments().apply {
        route = bundle.getString("route").orEmpty(); target = bundle.getString("target").orEmpty()
        val contactId = bundle.getString("contact").orEmpty()
        if (contactId.isNotBlank()) peers[contactId] = runCatching {
            ComposerAttachmentItem.decode(bundle.getString("attachments") ?: "[]")
        }.getOrDefault(emptyList())
    }
    pendingAgentCameraUri = bundle.getString("camera")?.let(Uri::parse)
}
