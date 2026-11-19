package com.galaxyssi.chat

import android.app.AlertDialog
import android.view.View
import android.widget.Toast

internal fun MainActivity.showConversationHubConversationActions(
    anchor: View,
    item: ConversationHubItem,
    conversations: List<AgentConversation>,
    onItemsChanged: () -> Unit,
    onRenamed: (String) -> Unit
) {
    val host = agentSessionsDialog
    val contact = item.kind == ConversationHubItemKind.CONTACT
    val rawContact = if (contact) AppStore.contactById(this, item.id) else null
    val initialName = if (contact) rawContact?.optString("name")?.takeIf(String::isNotBlank) ?: item.title
        else conversations.firstOrNull { it.id == item.id }?.title ?: item.title
    val canRename = !contact || rawContact?.let { !it.optBoolean("deleted", false) && it.optString("trust_state") != "deleted" } == true
    val rename: ((String, (Boolean) -> Unit) -> Unit)? = if (!canRename) null else { name, done ->
        navigationContentExecutor.execute {
            val saved = runCatching {
                if (!contact) agentTranscriptStore.renameConversation(item.id, name)
                else AppStore.contactById(applicationContext, item.id)?.let { current ->
                    !current.optBoolean("deleted", false) && current.optString("trust_state") != "deleted" &&
                        AppStore.renameContact(applicationContext, item.id, name)
                } == true
            }.getOrDefault(false)
            handler.post {
                if (saved && !isFinishing && !isDestroyed && !runtimePlaintextCleared &&
                    host != null && agentSessionsDialog === host && host.isShowing) {
                    if (contact) {
                        selectedContact?.takeIf { it.id == item.id }?.let { previous ->
                            val updated = previous.copy(name = name)
                            selectedContact = updated
                            chatTitle.text = displayContactName(updated)
                        }
                        refreshDirectoryContacts()
                    } else refreshAgentConversationHeader()
                    onRenamed(name)
                }
                done(saved)
            }
        }
    }
    ConversationHubActionMenu(this, item.title, contact, item.pinned, rename, pin = {
        if (contact) ContactConversationPreferences.setPinned(this, item.id, !item.pinned)
        else agentTranscriptStore.setPinned(item.id, !item.pinned)
        onItemsChanged()
    }, delete = {
        confirmConversationHubDelete(item, conversations, onItemsChanged)
    }, initialName = initialName).show(anchor)
}

private fun MainActivity.confirmConversationHubDelete(
    item: ConversationHubItem,
    conversations: List<AgentConversation>,
    onItemsChanged: () -> Unit
) {
    val dialog = AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_session_delete))
        .setMessage(getString(R.string.agent_session_delete_confirm))
        .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
            if (item.kind == ConversationHubItemKind.AGENT) {
                conversations.firstOrNull { it.id == item.id }?.let(::deleteAgentConversationData)
                refreshAgentConversationHeader()
                refreshAgentTranscriptWindow()
            } else {
                deleteChatConversationData(contactById(item.id))
                Toast.makeText(this, getString(R.string.delete_chat_toast), Toast.LENGTH_SHORT).show()
            }
            onItemsChanged()
        }.setNegativeButton(getString(R.string.common_cancel), null).show()
    dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(getColor(R.color.conversation_action_destructive))
}
