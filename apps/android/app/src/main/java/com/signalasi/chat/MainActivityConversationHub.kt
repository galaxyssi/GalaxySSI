package com.signalasi.chat

import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
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

    val root = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(getColorCompat(R.color.page_bg))
        setOnApplyWindowInsetsListener { view, insets ->
            view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom)
            insets
        }
    }
    val header = conversationHubHeader { dialog.dismiss() }
    root.addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)))

    val tabStrip = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(dp(2), dp(2), dp(2), dp(2))
        background = hubShape(Color.parseColor("#ECEEF1"), 8f)
    }
    root.addView(tabStrip, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)).apply {
        marginStart = dp(12)
        marginEnd = dp(12)
        topMargin = dp(2)
    })

    val searchShell = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), 0, dp(10), 0)
        background = hubShape(Color.parseColor("#ECEEF1"), 8f)
    }
    searchShell.addView(ImageView(this).apply {
        setImageResource(android.R.drawable.ic_menu_search)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
        scaleType = ImageView.ScaleType.CENTER_INSIDE
    }, LinearLayout.LayoutParams(dp(20), dp(20)))
    val searchInput = EditText(this).apply {
        hint = getString(R.string.conversation_hub_search_hint)
        setSingleLine(true)
        textSize = 14f
        setTextColor(getColorCompat(R.color.text_primary))
        setHintTextColor(getColorCompat(R.color.text_secondary))
        setPadding(dp(8), 0, 0, 0)
        background = null
    }
    searchShell.addView(searchInput, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
    root.addView(searchShell, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)).apply {
        marginStart = dp(12)
        marginEnd = dp(12)
        topMargin = dp(10)
        bottomMargin = dp(5)
    })

    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(12), 0, dp(12), dp(24))
    }
    root.addView(ScrollView(this).apply {
        isFillViewport = true
        clipToPadding = false
        addView(body, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

    lateinit var renderTabs: () -> Unit
    lateinit var renderBody: () -> Unit
    renderTabs = {
        tabStrip.removeAllViews()
        val tabs = listOf(
            ConversationHubTab.CONVERSATIONS to getString(R.string.conversation_hub_tab_conversations),
            ConversationHubTab.CONTACTS to getString(R.string.conversation_hub_tab_contacts),
            ConversationHubTab.GROUPS to getString(R.string.conversation_hub_tab_groups)
        )
        tabs.forEach { (tab, label) ->
            val selected = tab == selectedTab
            tabStrip.addView(TextView(this).apply {
                text = label
                textSize = 14f
                gravity = Gravity.CENTER
                setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
                setTextColor(if (selected) getColorCompat(R.color.signalasi_green) else getColorCompat(R.color.text_primary))
                background = if (selected) hubShape(Color.WHITE, 6f) else null
                setOnClickListener {
                    if (selectedTab != tab) {
                        selectedTab = tab
                        archivedMode = false
                        renderTabs()
                        renderBody()
                    }
                }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        }
    }
    renderBody = {
        body.removeAllViews()
        when (selectedTab) {
            ConversationHubTab.CONVERSATIONS -> renderConversationHubConversations(
                body = body,
                query = searchInput.text?.toString().orEmpty(),
                archived = archivedMode,
                dialog = dialog,
                onArchivedChanged = {
                    archivedMode = it
                    renderBody()
                }
            )
            ConversationHubTab.CONTACTS -> renderConversationHubContacts(
                body,
                searchInput.text?.toString().orEmpty(),
                dialog
            )
            ConversationHubTab.GROUPS -> renderConversationHubGroups(body)
        }
    }
    searchInput.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = renderBody()
        override fun afterTextChanged(s: Editable?) = Unit
    })
    renderTabs()
    renderBody()

    dialog.setContentView(root)
    dialog.setOnDismissListener { if (agentSessionsDialog === dialog) agentSessionsDialog = null }
    dialog.window?.apply {
        setBackgroundDrawable(android.graphics.drawable.ColorDrawable(getColorCompat(R.color.page_bg)))
        statusBarColor = getColorCompat(R.color.page_bg)
        navigationBarColor = getColorCompat(R.color.page_bg)
        clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
    }
    dialog.show()
    dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
}

private fun MainActivity.conversationHubHeader(onClose: () -> Unit): View = FrameLayout(this).apply {
    addView(ImageButton(this@conversationHubHeader).apply {
        setImageResource(R.drawable.ic_arrow_right)
        rotation = 180f
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_primary))
        contentDescription = getString(R.string.conversation_hub_close)
        setBackgroundColor(Color.TRANSPARENT)
        setPadding(dp(14), dp(14), dp(14), dp(14))
        setOnClickListener { onClose() }
    }, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.START or Gravity.CENTER_VERTICAL).apply {
        marginStart = dp(2)
    })
    addView(TextView(this@conversationHubHeader).apply {
        text = getString(R.string.agent_sessions_title)
        textSize = 18f
        gravity = Gravity.CENTER
        setTextColor(getColorCompat(R.color.text_primary))
        setTypeface(typeface, Typeface.BOLD)
    }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER))
}

private fun MainActivity.renderConversationHubConversations(
    body: LinearLayout,
    query: String,
    archived: Boolean,
    dialog: Dialog,
    onArchivedChanged: (Boolean) -> Unit
) {
    val all = agentTranscriptStore.conversations(includeArchived = true)
    if (archived) {
        body.addView(conversationHubActionRow(
            getString(R.string.conversation_hub_back_to_conversations),
            getString(R.string.conversation_hub_archived_subtitle),
            R.drawable.ic_agent_history
        ) { onArchivedChanged(false) })
        addConversationHubSection(body, getString(R.string.agent_session_archived))
    } else {
        body.addView(conversationHubActionRow(
            getString(R.string.agent_session_new),
            getString(R.string.conversation_hub_new_subtitle),
            R.drawable.ic_input_plus
        ) {
            dialog.dismiss()
            createAgentConversation()
        })
        val archivedCount = all.count { it.status == AgentConversationStatus.ARCHIVED }
        body.addView(conversationHubActionRow(
            getString(R.string.agent_session_archived),
            getString(R.string.conversation_hub_archived_subtitle),
            R.drawable.ic_agent_history,
            archivedCount.takeIf { it > 0 }?.toString().orEmpty()
        ) { onArchivedChanged(true) })
    }

    val sections = ConversationHubModels.conversations(all, query, archived)
    if (sections.pinned.isNotEmpty()) {
        addConversationHubSection(body, getString(R.string.conversation_hub_pinned))
        sections.pinned.forEach { conversation ->
            body.addView(conversationHubConversationRow(conversation, dialog, pinned = true))
        }
    }
    addConversationHubSection(
        body,
        if (archived) getString(R.string.agent_session_archived) else getString(R.string.conversation_hub_recent)
    )
    if (sections.recent.isEmpty()) {
        body.addView(conversationHubEmptyRow(getString(R.string.agent_session_no_results)))
    } else {
        sections.recent.forEach { conversation ->
            body.addView(conversationHubConversationRow(conversation, dialog, pinned = false))
        }
    }
}

private fun MainActivity.conversationHubConversationRow(
    conversation: AgentConversation,
    dialog: Dialog,
    pinned: Boolean
): View = conversationHubListRow(
    title = agentConversationDisplayTitle(conversation),
    iconRes = R.drawable.ic_agent_history,
    showPin = pinned,
    onClick = {
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
        showAgentConversationActions(conversation)
        true
    }
)

private fun MainActivity.renderConversationHubContacts(body: LinearLayout, query: String, dialog: Dialog) {
    body.addView(conversationHubActionRow(
        getString(R.string.new_friends),
        getString(R.string.conversation_hub_new_friends_subtitle),
        R.drawable.ic_tab_contacts
    ) { showFriendRequestsDialog() })
    body.addView(conversationHubActionRow(
        getString(R.string.conversation_hub_scan_add),
        getString(R.string.conversation_hub_scan_add_subtitle),
        R.drawable.ic_scan
    ) {
        scanMode = "contact"
        startSecurityScan()
    })

    val contacts = ConversationHubModels.contacts(buildDirectoryContacts(), query)
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

private fun MainActivity.renderConversationHubGroups(body: LinearLayout) {
    val empty = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(dp(24), dp(72), dp(24), dp(40))
        addView(ImageView(this@renderConversationHubGroups).apply {
            setImageResource(R.drawable.ic_avatar_group)
            imageTintList = ColorStateList.valueOf(getColorCompat(R.color.signalasi_green))
            scaleType = ImageView.ScaleType.CENTER_INSIDE
        }, LinearLayout.LayoutParams(dp(54), dp(54)).apply { bottomMargin = dp(16) })
        addView(TextView(this@renderConversationHubGroups).apply {
            text = getString(R.string.conversation_hub_groups_empty)
            textSize = 17f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(getColorCompat(R.color.text_primary))
            gravity = Gravity.CENTER
        })
        addView(TextView(this@renderConversationHubGroups).apply {
            text = getString(R.string.conversation_hub_groups_empty_subtitle)
            textSize = 13f
            setTextColor(getColorCompat(R.color.text_secondary))
            gravity = Gravity.CENTER
            setPadding(0, dp(7), 0, 0)
        })
    }
    body.addView(empty, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
}

private fun MainActivity.conversationHubActionRow(
    title: String,
    subtitle: String,
    iconRes: Int,
    trailing: String = "",
    onClick: () -> Unit
): View = conversationHubBaseRow(title, subtitle, iconRes, true, trailing, false, onClick, null)

private fun MainActivity.conversationHubListRow(
    title: String,
    iconRes: Int,
    tintIcon: Boolean = true,
    showPin: Boolean = false,
    onClick: () -> Unit,
    onLongClick: (() -> Boolean)? = null
): View = conversationHubBaseRow(title, "", iconRes, tintIcon, "", showPin, onClick, onLongClick)

private fun MainActivity.conversationHubBaseRow(
    title: String,
    subtitle: String,
    iconRes: Int,
    tintIcon: Boolean,
    trailing: String,
    showPin: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Boolean)?
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    minimumHeight = dp(if (subtitle.isBlank()) 58 else 64)
    setPadding(dp(10), dp(7), dp(4), dp(7))
    background = hubShape(Color.WHITE, 0f, Color.parseColor("#E4E6E8"), 1)
    addView(FrameLayout(this@conversationHubBaseRow).apply {
        background = hubShape(if (tintIcon) Color.parseColor("#ECF9F2") else Color.TRANSPARENT, 8f)
        addView(ImageView(this@conversationHubBaseRow).apply {
            setImageResource(iconRes)
            if (tintIcon) imageTintList = ColorStateList.valueOf(getColorCompat(R.color.signalasi_green))
            scaleType = ImageView.ScaleType.CENTER_INSIDE
        }, FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
    }, LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginEnd = dp(10) })
    addView(LinearLayout(this@conversationHubBaseRow).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_VERTICAL
        addView(TextView(this@conversationHubBaseRow).apply {
            text = title
            textSize = 15f
            setTextColor(getColorCompat(R.color.text_primary))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        if (subtitle.isNotBlank()) addView(TextView(this@conversationHubBaseRow).apply {
            text = subtitle
            textSize = 12f
            setTextColor(getColorCompat(R.color.text_secondary))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(0, dp(2), 0, 0)
        })
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
    if (showPin) addView(ImageView(this@conversationHubBaseRow).apply {
        setImageResource(android.R.drawable.star_big_on)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        contentDescription = getString(R.string.agent_session_pin)
    }, LinearLayout.LayoutParams(dp(26), dp(30)))
    if (trailing.isNotBlank()) addView(TextView(this@conversationHubBaseRow).apply {
        text = trailing
        textSize = 13f
        gravity = Gravity.CENTER
        setTextColor(getColorCompat(R.color.text_secondary))
        setPadding(dp(4), 0, dp(4), 0)
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(36)))
    addView(ImageView(this@conversationHubBaseRow).apply {
        setImageResource(R.drawable.ic_arrow_right)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
        scaleType = ImageView.ScaleType.CENTER_INSIDE
    }, LinearLayout.LayoutParams(dp(28), dp(36)))
    setOnClickListener { onClick() }
    onLongClick?.let { handler -> setOnLongClickListener { handler() } }
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
