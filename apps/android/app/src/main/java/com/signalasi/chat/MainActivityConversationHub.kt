package com.signalasi.chat

import android.app.Dialog
import android.content.res.Configuration
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

internal fun MainActivity.showAgentSessionsPage(showArchived: Boolean = false) {
    showConversationHub(ConversationHubTab.CONVERSATIONS, showArchived)
}

internal fun MainActivity.showConversationHub(
    initialTab: ConversationHubTab = ConversationHubTab.CONVERSATIONS,
    showArchived: Boolean = false
) {
    agentSessionsDialog?.dismiss()
    val dialog = Dialog(this)
    agentSessionsDialog = dialog
    var selectedTab = initialTab
    var archivedMode = showArchived
    var conversations: List<AgentConversation>? = null
    var agentConversationItems: List<ConversationHubItem>? = null
    var contacts: List<Contact>? = null
    var contactConversationSummaries: List<ConversationHubContactSummary>? = null
    val contentGeneration = navigationContentGate.begin()
    val previousHostStatusBarColor = window.statusBarColor
    val previousHostSystemUiVisibility = window.decorView.systemUiVisibility
    val previousHostStatusBarContrast = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        window.isStatusBarContrastEnforced
    } else {
        null
    }
    lateinit var renderBody: () -> Unit

    val root = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(getColorCompat(R.color.page_bg))
        setOnApplyWindowInsetsListener { view, insets ->
            view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom)
            insets
        }
    }
    val searchInput = EditText(this).apply {
        hint = getString(R.string.conversation_hub_search_hint)
        setSingleLine(true)
        textSize = 14f
        setTextColor(getColorCompat(R.color.text_primary))
        setHintTextColor(getColorCompat(R.color.text_secondary))
        setPadding(dp(8), 0, 0, 0)
        background = null
    }
    val searchShell = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), 0, dp(10), 0)
        background = hubShape(Color.parseColor("#F1F2F4"), 8f)
        visibility = View.GONE
    }
    searchShell.addView(ImageView(this).apply {
        setImageResource(R.drawable.ic_hub_search)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
        scaleType = ImageView.ScaleType.CENTER_INSIDE
    }, LinearLayout.LayoutParams(dp(20), dp(20)))
    searchShell.addView(searchInput, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
    val closeSearch = {
        if (searchShell.visibility == View.VISIBLE) {
            searchShell.visibility = View.GONE
            searchInput.text?.clear()
            searchInput.clearFocus()
            getSystemService(InputMethodManager::class.java)
                .hideSoftInputFromWindow(searchInput.windowToken, 0)
        }
    }
    val header = conversationHubHeader(
        onBack = {
            if (selectedTab != ConversationHubTab.CONVERSATIONS || archivedMode) {
                closeSearch()
                selectedTab = ConversationHubTab.CONVERSATIONS
                archivedMode = false
                renderBody()
            } else {
                dialog.dismiss()
            }
        },
        onSearch = {
            val opening = searchShell.visibility != View.VISIBLE
            if (opening) {
                searchShell.visibility = View.VISIBLE
                searchInput.post {
                    searchInput.requestFocus()
                    getSystemService(InputMethodManager::class.java)
                        .showSoftInput(searchInput, InputMethodManager.SHOW_IMPLICIT)
                }
            } else {
                closeSearch()
            }
        },
        onContacts = {
            closeSearch()
            selectedTab = ConversationHubTab.CONTACTS
            archivedMode = false
            renderBody()
        },
        onNewConversation = {
            dialog.dismiss()
            createAgentConversation()
        }
    )
    root.addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)))
    root.addView(searchShell, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)).apply {
        marginStart = dp(12)
        marginEnd = dp(12)
        topMargin = dp(10)
        bottomMargin = dp(5)
    })

    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), 0, dp(16), dp(24))
    }
    root.addView(ScrollView(this).apply {
        isFillViewport = true
        clipToPadding = false
        addView(body, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

    renderBody = {
        body.removeAllViews()
        when (selectedTab) {
            ConversationHubTab.CONVERSATIONS -> conversations?.let { snapshot ->
                val agentItems = agentConversationItems
                val contactSnapshot = contactConversationSummaries
                if (agentItems == null || contactSnapshot == null) {
                    body.addView(conversationHubEmptyRow(getString(R.string.navigation_content_loading)))
                    return@let
                }
                renderConversationHubConversations(
                    body = body,
                    query = searchInput.text?.toString().orEmpty(),
                    archived = archivedMode,
                    dialog = dialog,
                    conversations = snapshot,
                    agentItems = agentItems,
                    contacts = contactSnapshot,
                    onArchivedChanged = {
                        archivedMode = it
                        renderBody()
                    },
                    onItemsChanged = {
                        dialog.dismiss()
                        showConversationHub(ConversationHubTab.CONVERSATIONS, archivedMode)
                    }
                )
            } ?: body.addView(conversationHubEmptyRow(getString(R.string.navigation_content_loading)))
            ConversationHubTab.CONTACTS -> contacts?.let { snapshot ->
                renderConversationHubContacts(
                    body,
                    searchInput.text?.toString().orEmpty(),
                    dialog,
                    snapshot
                )
            } ?: body.addView(conversationHubEmptyRow(getString(R.string.navigation_content_loading)))
        }
    }
    val contactsChangedListener: (List<Contact>) -> Unit = { latest ->
        if (dialog.isShowing) {
            contacts = latest
            val contactsById = latest.associateBy(Contact::id)
            contactConversationSummaries = summaries.mapNotNull { (contactId, summary) ->
                if (summary.lastAt <= 0L) return@mapNotNull null
                val contact = contactsById[contactId] ?: contactById(contactId)
                ConversationHubContactSummary(
                    contactId = contactId,
                    title = displayContactName(contact),
                    lastMessage = summary.lastMessage,
                    updatedAt = summary.lastAt,
                    pinned = ContactConversationPreferences.isPinned(this, contactId),
                    unreadCount = summary.unreadCount
                )
            }
            renderBody()
        }
    }
    searchInput.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = renderBody()
        override fun afterTextChanged(s: Editable?) = Unit
    })
    dialog.setContentView(root)
    dialog.setOnDismissListener {
        if (agentSessionsDialog === dialog) agentSessionsDialog = null
        if (conversationHubContactsChangedListener === contactsChangedListener) {
            conversationHubContactsChangedListener = null
        }
        navigationContentGate.invalidateIfCurrent(contentGeneration)
        window.statusBarColor = previousHostStatusBarColor
        window.decorView.systemUiVisibility = previousHostSystemUiVisibility
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && previousHostStatusBarContrast != null) {
            window.isStatusBarContrastEnforced = previousHostStatusBarContrast
        }
    }
    dialog.window?.apply {
        setBackgroundDrawable(android.graphics.drawable.ColorDrawable(getColorCompat(R.color.page_bg)))
        clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    }
    dialog.show()
    dialog.window?.apply {
        setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        applyConversationHubSystemBars(this)
    }
    applyConversationHubHostStatusBar()
    renderBody()
    conversationHubContactsChangedListener = contactsChangedListener
    navigationContentExecutor.execute {
        val loadStartedAt = System.currentTimeMillis()
        val conversationSnapshot = runCatching {
            agentTranscriptStore.conversations(includeArchived = true)
        }.getOrDefault(emptyList())
        val baseAgentItems = conversationSnapshot.map { conversation ->
            ConversationHubItem(
                id = conversation.id,
                kind = ConversationHubItemKind.AGENT,
                title = agentConversationDisplayTitle(conversation),
                subtitle = "",
                updatedAt = conversation.updatedAt,
                pinned = conversation.pinned,
                archived = conversation.status == AgentConversationStatus.ARCHIVED,
                searchableMetadata = conversation.selectedModelOrAgent
            )
        }
        handler.post {
            if (dialog.isShowing && navigationContentGate.isCurrent(contentGeneration)) {
                conversations = conversationSnapshot
                agentConversationItems = baseAgentItems
                contactConversationSummaries = emptyList()
                renderBody()
            }
        }
        val agentItemSnapshot = conversationSnapshot.map { conversation ->
            val latest = runCatching {
                agentTranscriptStore.page(conversation.id, pageSize = 1).entries.lastOrNull()
            }.getOrNull()
            ConversationHubItem(
                id = conversation.id,
                kind = ConversationHubItemKind.AGENT,
                title = agentConversationDisplayTitle(conversation),
                subtitle = latest?.text.orEmpty(),
                updatedAt = maxOf(conversation.updatedAt, latest?.timestampMillis ?: 0L),
                pinned = conversation.pinned,
                archived = conversation.status == AgentConversationStatus.ARCHIVED,
                searchableMetadata = conversation.selectedModelOrAgent
            )
        }
        handler.post {
            if (dialog.isShowing && navigationContentGate.isCurrent(contentGeneration)) {
                agentConversationItems = agentItemSnapshot
                renderBody()
            }
        }
        val contactSnapshot = runCatching(::buildDirectoryContacts).getOrDefault(emptyList())
        val contactsById = contactSnapshot.associateBy(Contact::id)
        val chatSummarySnapshot = runCatching {
            ChatHistoryStore.pruneInternalTransportMessages(this)
            ChatHistoryStore.contactSummaries(this).mapNotNull { summary ->
                val message = storedChatMessage(summary.contactId, summary.lastMessage) ?: return@mapNotNull null
                val contact = contactsById[summary.contactId] ?: contactById(summary.contactId)
                val preview = conversationHubMessagePreview(message)
                ConversationHubContactSummary(
                    contactId = summary.contactId,
                    title = displayContactName(contact),
                    lastMessage = preview,
                    updatedAt = message.timestamp,
                    pinned = ContactConversationPreferences.isPinned(this, summary.contactId),
                    unreadCount = summary.unreadCount
                )
            }
        }.getOrDefault(emptyList())
        handler.post {
            if (dialog.isShowing && navigationContentGate.isCurrent(contentGeneration)) {
                conversations = conversationSnapshot
                agentConversationItems = agentItemSnapshot
                contacts = contactSnapshot
                contactConversationSummaries = chatSummarySnapshot
                renderBody()
                Log.i(
                    "SignalASIConversationHub",
                    "loaded total_ms=${System.currentTimeMillis() - loadStartedAt} " +
                        "agents=${conversationSnapshot.size} contacts=${chatSummarySnapshot.size}"
                )
            }
        }
    }
}

private fun MainActivity.applyConversationHubHostStatusBar() {
    val nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
        Configuration.UI_MODE_NIGHT_YES
    window.statusBarColor = getColorCompat(R.color.page_bg)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        window.isStatusBarContrastEnforced = false
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        val lightStatusBar = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        window.decorView.systemUiVisibility = if (nightMode) {
            window.decorView.systemUiVisibility and lightStatusBar.inv()
        } else {
            window.decorView.systemUiVisibility or lightStatusBar
        }
    }
}

private fun MainActivity.applyConversationHubSystemBars(targetWindow: Window) {
    val pageColor = getColorCompat(R.color.page_bg)
    val nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
        Configuration.UI_MODE_NIGHT_YES
    targetWindow.apply {
        addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        clearFlags(
            WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS or
                WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            setDecorFitsSystemWindows(false)
        }
        statusBarColor = pageColor
        navigationBarColor = Color.TRANSPARENT
        decorView.setBackgroundColor(pageColor)
        decorView.elevation = 0f
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            navigationBarDividerColor = Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            isStatusBarContrastEnforced = false
            isNavigationBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            var flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            if (!nightMode) {
                flags = flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            }
            if (!nightMode && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            }
            decorView.systemUiVisibility = flags
        }
    }
}
private fun MainActivity.conversationHubHeader(
    onBack: () -> Unit,
    onSearch: () -> Unit,
    onContacts: () -> Unit,
    onNewConversation: () -> Unit
): View = FrameLayout(this).apply {
    addView(ImageButton(this@conversationHubHeader).apply {
        setImageResource(R.drawable.ic_navigation_back)
        contentDescription = getString(R.string.conversation_hub_close)
        setBackgroundColor(Color.TRANSPARENT)
        scaleType = ImageView.ScaleType.CENTER
        setPadding(dp(8), dp(8), dp(8), dp(8))
        setOnClickListener { onBack() }
    }, FrameLayout.LayoutParams(dp(40), ViewGroup.LayoutParams.MATCH_PARENT, Gravity.START))
    addView(TextView(this@conversationHubHeader).apply {
        text = getString(R.string.agent_sessions_title)
        textSize = 18f
        gravity = Gravity.CENTER
        setTextColor(getColorCompat(R.color.text_primary))
        setTypeface(typeface, Typeface.BOLD)
    }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER))
    addView(LinearLayout(this@conversationHubHeader).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(conversationHubHeaderAction(
            R.drawable.ic_hub_search,
            getString(R.string.conversation_hub_search_hint),
            onSearch
        ))
        addView(conversationHubHeaderAction(
            R.drawable.ic_hub_contacts_compact,
            getString(R.string.conversation_hub_tab_contacts),
            onContacts
        ))
        addView(conversationHubHeaderAction(
            R.drawable.ic_hub_compose,
            getString(R.string.agent_session_new),
            onNewConversation
        ))
    }, FrameLayout.LayoutParams(dp(138), ViewGroup.LayoutParams.MATCH_PARENT, Gravity.END or Gravity.CENTER_VERTICAL).apply {
        marginEnd = dp(2)
    })
}

private fun MainActivity.conversationHubHeaderAction(
    iconRes: Int,
    description: String,
    onClick: () -> Unit
): View = ImageButton(this).apply {
    setImageResource(iconRes)
    imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_primary))
    contentDescription = description
    setBackgroundColor(Color.TRANSPARENT)
    setPadding(dp(12), dp(12), dp(12), dp(12))
    setOnClickListener { onClick() }
    layoutParams = LinearLayout.LayoutParams(dp(46), dp(48))
}

private fun MainActivity.renderConversationHubConversations(
    body: LinearLayout,
    query: String,
    archived: Boolean,
    dialog: Dialog,
    conversations: List<AgentConversation>,
    agentItems: List<ConversationHubItem>,
    contacts: List<ConversationHubContactSummary>,
    onArchivedChanged: (Boolean) -> Unit,
    onItemsChanged: () -> Unit
) {
    val all = conversations
    if (archived) {
        body.addView(conversationHubActionRow(
            getString(R.string.conversation_hub_back_to_conversations),
            getString(R.string.conversation_hub_archived_subtitle),
            R.drawable.ic_hub_archive,
            iconTint = Color.parseColor("#3478F6"),
            iconBackground = Color.parseColor("#EEF4FF")
        ) { onArchivedChanged(false) })
    }

    val sections = ConversationHubModels.unifiedConversations(agentItems, contacts, query, archived)
    val items = sections.pinned + sections.recent
    if (items.isEmpty()) {
        body.addView(conversationHubEmptyRow(getString(R.string.agent_session_no_results)))
    } else {
        items.forEach { item ->
            body.addView(conversationHubConversationRow(item, dialog, conversations = all, onItemsChanged))
        }
    }
    if (!archived) {
        val archivedCount = all.count { it.status == AgentConversationStatus.ARCHIVED }
        body.addView(conversationHubActionRow(
            getString(R.string.agent_session_archived),
            "",
            R.drawable.ic_hub_archive,
            archivedCount.takeIf { it > 0 }?.toString().orEmpty(),
            iconTint = getColorCompat(R.color.text_secondary),
            iconBackground = Color.TRANSPARENT
        ) { onArchivedChanged(true) })
    }
}

private fun MainActivity.conversationHubMessagePreview(message: ChatMessage): String {
    val preview = ConversationHubPreviewPolicy.classify(
        content = message.voiceTranscript.ifBlank { message.content },
        attachments = message.attachments
    )
    return when (preview.kind) {
        ConversationHubPreviewKind.TEXT -> preview.text
        ConversationHubPreviewKind.VOICE -> getString(
            R.string.conversation_hub_preview_voice,
            preview.durationSeconds
        )
        ConversationHubPreviewKind.IMAGE -> getString(R.string.conversation_hub_preview_image)
        ConversationHubPreviewKind.FILE -> when {
            preview.name.isNotBlank() && preview.sizeBytes > 0L -> getString(
                R.string.conversation_hub_preview_file_named_size,
                preview.name,
                formatBytes(preview.sizeBytes)
            )
            preview.name.isNotBlank() -> getString(R.string.conversation_hub_preview_file_named, preview.name)
            else -> getString(R.string.conversation_hub_preview_file)
        }
    }
}

private fun MainActivity.conversationHubConversationRow(
    item: ConversationHubItem,
    dialog: Dialog,
    conversations: List<AgentConversation>,
    onItemsChanged: () -> Unit
): View {
    val contact = item.takeIf { it.kind == ConversationHubItemKind.CONTACT }
        ?.let { contactById(it.id) }
    return conversationHubListRow(
        title = item.title,
        subtitle = item.subtitle,
        trailing = item.updatedAt.takeIf { it > 0L }?.let(::listTime).orEmpty(),
        iconRes = if (contact != null) {
            contactAvatarRes(contact)
        } else {
            R.drawable.ic_agent_history
        },
        contact = contact,
        tintIcon = item.kind != ConversationHubItemKind.CONTACT,
        unreadCount = item.unreadCount,
        onClick = {
            if (item.kind == ConversationHubItemKind.CONTACT) {
                dialog.dismiss()
                showChatPage(contactById(item.id))
                return@conversationHubListRow
            }
            val conversation = conversations.firstOrNull { it.id == item.id } ?: return@conversationHubListRow
            val destination = agentTranscriptStore.resolveMergedConversationId(conversation.id) ?: conversation.id
            if (destination == conversation.id && conversation.status == AgentConversationStatus.ARCHIVED) {
                agentTranscriptStore.restoreConversation(conversation.id)
            }
            agentTranscriptStore.switchConversation(destination)
            resetAgentTranscriptRendering(destination)
            refreshAgentConversationHeader()
            refreshAgentTranscriptWindow()
            dialog.dismiss()
        },
        onLongClick = {
            showConversationHubConversationActions(item, conversations, onItemsChanged)
            true
        }
    )
}

private fun MainActivity.showConversationHubConversationActions(
    item: ConversationHubItem,
    conversations: List<AgentConversation>,
    onItemsChanged: () -> Unit
) {
    val pinLabel = getString(if (item.pinned) R.string.agent_session_unpin else R.string.agent_session_pin)
    val actions = arrayOf(getString(R.string.agent_session_delete), pinLabel)
    android.app.AlertDialog.Builder(this)
        .setTitle(item.title)
        .setItems(actions) { _, which ->
            when (which) {
                0 -> confirmConversationHubDelete(item, conversations, onItemsChanged)
                1 -> {
                    if (item.kind == ConversationHubItemKind.AGENT) {
                        agentTranscriptStore.setPinned(item.id, !item.pinned)
                    } else {
                        ContactConversationPreferences.setPinned(this, item.id, !item.pinned)
                    }
                    onItemsChanged()
                }
            }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

private fun MainActivity.confirmConversationHubDelete(
    item: ConversationHubItem,
    conversations: List<AgentConversation>,
    onItemsChanged: () -> Unit
) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_session_delete))
        .setMessage(getString(R.string.agent_session_delete_confirm))
        .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
            if (item.kind == ConversationHubItemKind.AGENT) {
                conversations.firstOrNull { it.id == item.id }?.let(::deleteAgentConversationData)
                refreshAgentConversationHeader()
                refreshAgentTranscriptWindow()
            } else {
                deleteChatConversationData(contactById(item.id))
                android.widget.Toast.makeText(this, getString(R.string.delete_chat_toast), android.widget.Toast.LENGTH_SHORT).show()
            }
            onItemsChanged()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

private fun MainActivity.renderConversationHubContacts(
    body: LinearLayout,
    query: String,
    dialog: Dialog,
    contactsSnapshot: List<Contact>
) {
    body.addView(conversationHubActionRow(
        getString(R.string.new_friends),
        getString(R.string.conversation_hub_new_friends_subtitle),
        R.drawable.ic_hub_new_friends,
        unreadCount = AppStore.unreadFriendRequestCount(this),
        iconTint = Color.parseColor("#08A66C"),
        iconBackground = Color.parseColor("#EAF8F2")
    ) {
        dialog.dismiss()
        showFriendRequestsDialog()
    })
    body.addView(conversationHubActionRow(
        getString(R.string.conversation_hub_tab_groups),
        getString(R.string.conversation_hub_groups_subtitle),
        R.drawable.ic_hub_groups,
        iconTint = Color.parseColor("#8A4DF0"),
        iconBackground = Color.parseColor("#F4EDFF")
    ) {
        dialog.dismiss()
        showGroupFeaturePage()
    })
    body.addView(conversationHubActionRow(
        getString(R.string.conversation_hub_add_cloud_model),
        getString(R.string.add_cloud_model_subtitle),
        R.drawable.ic_hub_cloud_model,
        iconTint = Color.parseColor("#536DFE"),
        iconBackground = Color.parseColor("#EEF1FF")
    ) {
        dialog.dismiss()
        showCloudProviderPage(returnToContacts = true)
    })
    body.addView(conversationHubActionRow(
        getString(R.string.conversation_hub_add_smart_device),
        getString(R.string.conversation_hub_add_smart_device_subtitle),
        R.drawable.ic_device_node,
        iconTint = Color.parseColor("#E68A2E"),
        iconBackground = Color.parseColor("#FFF4E8")
    ) {
        dialog.dismiss()
        showDeviceFeaturePage(returnToContacts = true)
    })
    body.addView(conversationHubActionRow(
        getString(R.string.conversation_hub_scan_add),
        getString(R.string.conversation_hub_scan_add_subtitle),
        R.drawable.ic_hub_scan,
        iconTint = Color.parseColor("#12A8C4"),
        iconBackground = Color.parseColor("#EAF9FC")
    ) {
        dialog.dismiss()
        scanMode = "contact"
        startSecurityScan()
    })

    val contacts = ConversationHubModels.contacts(contactsSnapshot, query)
    if (contacts.isEmpty()) {
        addConversationHubSection(body, getString(R.string.conversation_hub_contacts_section))
        body.addView(conversationHubEmptyRow(getString(R.string.conversation_hub_no_contacts)))
        return
    }
    contacts.groupBy { ConversationHubModels.contactSection(it.name) }.forEach { (section, members) ->
        addConversationHubSection(body, section)
        members.forEach { contact ->
            body.addView(conversationHubListRow(
                title = contact.name,
                iconRes = contactAvatarRes(contact),
                contact = contact,
                tintIcon = false,
                onClick = {
                    dialog.dismiss()
                    showContactDetail(contact)
                    setFeatureBackAction {
                        hideFeaturePage()
                        showConversationHub(ConversationHubTab.CONTACTS)
                    }
                },
                onLongClick = {
                    confirmDeleteContact(contact)
                    true
                }
            ))
        }
    }
}

private fun MainActivity.conversationHubActionRow(
    title: String,
    subtitle: String,
    iconRes: Int,
    trailing: String = "",
    unreadCount: Int = 0,
    iconTint: Int = getColorCompat(R.color.signalasi_green),
    iconBackground: Int = Color.parseColor("#ECF9F2"),
    onClick: () -> Unit
): View = conversationHubBaseRow(
    title = title,
    subtitle = subtitle,
    iconRes = iconRes,
    contact = null,
    tintIcon = true,
    trailing = trailing,
    unreadCount = unreadCount,
    iconTint = iconTint,
    iconBackground = iconBackground,
    showChevron = true,
    onClick = onClick,
    onLongClick = null
)

private fun MainActivity.conversationHubListRow(
    title: String,
    subtitle: String = "",
    trailing: String = "",
    iconRes: Int,
    contact: Contact? = null,
    tintIcon: Boolean = true,
    unreadCount: Int = 0,
    onClick: () -> Unit,
    onLongClick: (() -> Boolean)? = null
): View = conversationHubBaseRow(
    title = title,
    subtitle = subtitle,
    iconRes = iconRes,
    contact = contact,
    tintIcon = tintIcon,
    trailing = trailing,
    unreadCount = unreadCount,
    iconTint = getColorCompat(R.color.signalasi_green),
    iconBackground = Color.parseColor("#ECF9F2"),
    showChevron = false,
    onClick = onClick,
    onLongClick = onLongClick
)

private fun MainActivity.conversationHubBaseRow(
    title: String,
    subtitle: String,
    iconRes: Int,
    contact: Contact?,
    tintIcon: Boolean,
    trailing: String,
    unreadCount: Int,
    iconTint: Int,
    iconBackground: Int,
    showChevron: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Boolean)?
): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    val contentRow = LinearLayout(this@conversationHubBaseRow).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(if (subtitle.isBlank()) 62 else 76)
        setPadding(dp(4), dp(8), dp(2), dp(8))
        background = conversationHubSelectableBackground()
        addView(FrameLayout(this@conversationHubBaseRow).apply {
            background = hubShape(if (tintIcon) iconBackground else Color.TRANSPARENT, 8f)
            addView(ImageView(this@conversationHubBaseRow).apply {
                if (contact != null) {
                    bindContactAvatar(this, contact)
                } else {
                    setImageResource(iconRes)
                    if (tintIcon) imageTintList = ColorStateList.valueOf(iconTint)
                }
                scaleType = ImageView.ScaleType.CENTER_INSIDE
            }, FrameLayout.LayoutParams(dp(36), dp(36), Gravity.CENTER))
        }, LinearLayout.LayoutParams(dp(48), dp(48)).apply { marginEnd = dp(12) })
        addView(LinearLayout(this@conversationHubBaseRow).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@conversationHubBaseRow).apply {
                text = title
                textSize = 16f
                setTextColor(getColorCompat(R.color.text_primary))
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            if (subtitle.isNotBlank()) addView(TextView(this@conversationHubBaseRow).apply {
                text = subtitle
                textSize = 13f
                setTextColor(getColorCompat(R.color.text_secondary))
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(0, dp(3), 0, 0)
            })
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(LinearLayout(this@conversationHubBaseRow).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            if (trailing.isNotBlank()) addView(TextView(this@conversationHubBaseRow).apply {
                text = trailing
                textSize = 13f
                gravity = Gravity.CENTER
                setTextColor(getColorCompat(R.color.text_secondary))
                setPadding(dp(4), 0, dp(4), 0)
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(36)))
            if (unreadCount > 0) addView(TextView(this@conversationHubBaseRow).apply {
                text = if (unreadCount > 99) "99+" else unreadCount.toString()
                textSize = 11f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                minWidth = dp(20)
                background = hubShape(getColorCompat(R.color.signalasi_blue), 10f)
                setPadding(dp(5), 0, dp(5), 0)
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(20)).apply {
                marginStart = dp(5)
            })
            if (showChevron) addView(ImageView(this@conversationHubBaseRow).apply {
                setImageResource(R.drawable.ic_arrow_right)
                imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
                scaleType = ImageView.ScaleType.CENTER_INSIDE
            }, LinearLayout.LayoutParams(dp(24), dp(36)).apply { marginStart = dp(2) })
        })
        setOnClickListener { onClick() }
        onLongClick?.let { handler -> setOnLongClickListener { handler() } }
    }
    addView(contentRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    addView(View(this@conversationHubBaseRow).apply {
        setBackgroundColor(getColorCompat(R.color.separator))
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply {
        marginStart = dp(64)
    })
}

private fun MainActivity.conversationHubSelectableBackground() = TypedValue().let { value ->
    theme.resolveAttribute(android.R.attr.selectableItemBackground, value, true)
    getDrawable(value.resourceId)
}

private fun MainActivity.conversationHubEmptyRow(label: String): View = TextView(this).apply {
    text = label
    textSize = 14f
    gravity = Gravity.CENTER
    setTextColor(getColorCompat(R.color.text_secondary))
    setPadding(dp(12), dp(28), dp(12), dp(28))
}

private fun MainActivity.addConversationHubSection(parent: LinearLayout, title: String) {
    parent.addView(TextView(this).apply {
        text = title
        textSize = 12f
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(getColorCompat(R.color.text_secondary))
        setPadding(dp(2), dp(15), 0, dp(7))
    })
}

private fun MainActivity.hubShape(fill: Int, radiusDp: Float, stroke: Int? = null, strokeWidth: Int = 0): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(fill)
        cornerRadius = dp(radiusDp.toInt()).toFloat()
        if (stroke != null && strokeWidth > 0) setStroke(dp(strokeWidth), stroke)
    }
