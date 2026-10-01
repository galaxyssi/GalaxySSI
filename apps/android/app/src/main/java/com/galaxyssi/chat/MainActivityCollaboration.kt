package com.galaxyssi.chat

import android.app.AlertDialog
import android.graphics.Typeface
import android.text.Annotation
import android.text.Editable
import android.text.Spanned
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListPopupWindow
import android.widget.PopupWindow
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.util.concurrent.Executors

private val collaborationIo = Executors.newSingleThreadExecutor { task ->
    Thread(task, "galaxyssi-collaboration-ui").apply { isDaemon = true }
}

internal fun MainActivity.ensureCollaborationLoaded(id: String, onLoaded: () -> Unit): Boolean {
    if (CollaborationGroupStore.isLoaded(id)) return true
    if (collaborationSubmissionLoading) return false
    collaborationSubmissionLoading = true
    collaborationIo.execute {
        val result = runCatching { CollaborationGroupStore(this).load(id) }
        runOnUiThread {
            collaborationSubmissionLoading = false
            if (!isFinishing && !isDestroyed) result.onSuccess { onLoaded() }.onFailure { collaborationFailure(it) }
        }
    }
    return false
}

internal fun MainActivity.showNewConversationChoices() {
    AlertDialog.Builder(this).setItems(arrayOf(getString(R.string.agent_session_new), getString(R.string.collaboration_title))) { _, index ->
        createAgentConversation()
        if (index == 1) {
            agentTranscriptStore.renameConversation(agentTranscriptStore.activeConversation().id, getString(R.string.collaboration_title))
            showCollaborationMembers()
        }
    }.show()
}

private fun MainActivity.collaborationLoad(done: (CollaborationGroup?) -> Unit) {
    val id = agentTranscriptStore.activeConversation().id
    collaborationIo.execute {
        val result = runCatching { CollaborationGroupStore(this).load(id) }
        runOnUiThread {
            if (!isFinishing && !isDestroyed && agentTranscriptStore.activeConversation().id == id) {
                result.onSuccess(done).onFailure { collaborationFailure(it) }
            }
        }
    }
}

private fun MainActivity.collaborationUpdate(
    id: String,
    transform: (CollaborationGroup) -> CollaborationGroup,
    done: (CollaborationGroup) -> Unit
) {
    collaborationIo.execute {
        val result = runCatching {
            CollaborationGroupStore(this).update(id, transform).also { group ->
                if (group.members.isNotEmpty()) agentTranscriptStore.append(AgentTranscriptRole.PROCESS,
                    getString(R.string.collaboration_created), dedupeKey = "collaboration-created:$id", conversationId = id)
            }
        }
        runOnUiThread {
            if (!isFinishing && !isDestroyed && agentTranscriptStore.activeConversation().id == id) {
                result.onSuccess { refreshCollaborationStrip(); done(it) }.onFailure { collaborationFailure(it) }
            }
        }
    }
}

private fun MainActivity.collaborationFailure(error: Throwable) {
    android.util.Log.w("GalaxySSICollaboration", "Collaboration operation failed", error)
    Toast.makeText(this, R.string.collaboration_failed, Toast.LENGTH_LONG).show()
}

internal fun MainActivity.maybeShowAgentMentionPicker(editable: Editable?) {
    editable ?: return
    val cursor = agentGoalInput.selectionStart
    if (cursor <= 0 || cursor > editable.length || editable[cursor - 1] != '@') return
    val start = cursor - 1
    collaborationLoad { group ->
        if (!agentGoalInput.hasFocus() || start >= editable.length || editable[start] != '@') return@collaborationLoad
        if (group == null || group.members.isEmpty()) maybeShowLegacyAgentMentionPicker(editable)
        else showCollaborationMentionPicker(group, start)
    }
}

internal fun MainActivity.collaborationSettingsEntry(onClick: () -> Unit): View = TextView(this).apply {
    text = getString(R.string.collaboration_settings)
    setTextColor(getColorCompat(R.color.text_primary))
    textSize = 14f
    gravity = Gravity.CENTER_VERTICAL
    minHeight = dp(48)
    setPadding(dp(16), dp(8), dp(16), dp(8))
    setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_hub_contacts_compact, 0, 0, 0)
    compoundDrawablePadding = dp(10)
    setOnClickListener { onClick() }
}

private fun MainActivity.showCollaborationMentionPicker(group: CollaborationGroup, start: Int) {
    val popup = ListPopupWindow(this)
    val adapter = object : ArrayAdapter<CollaborationMember>(this, 0, group.members) {
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
            collaborationMemberRow(getItem(position)!!)
    }
    popup.apply {
        anchorView = agentGoalInput
        width = minOf(dp(392), resources.displayMetrics.widthPixels - dp(24))
        height = minOf(dp(370), resources.displayMetrics.heightPixels / 2)
        horizontalOffset = agentGoalInput.width - width
        isModal = false
        inputMethodMode = PopupWindow.INPUT_METHOD_NEEDED
        setAdapter(adapter)
        setPromptView(collaborationSettingsEntry { dismiss(); showCollaborationMembers() })
        promptPosition = ListPopupWindow.POSITION_PROMPT_BELOW
        setOnItemClickListener { _, _, position, _ ->
            val member = group.members.getOrNull(position) ?: return@setOnItemClickListener
            val text = agentGoalInput.text ?: return@setOnItemClickListener
            if (start >= text.length || text[start] != '@') { dismiss(); return@setOnItemClickListener }
            AgentMentionText.insert(text, start, start + 1, member.agentId, member.name,
                getColorCompat(R.color.composer_send_icon), uniqueName = true)
            val annotation = text.getSpans(start, text.length, Annotation::class.java)
                .firstOrNull { it.key == AGENT_MENTION_ANNOTATION_KEY && text.getSpanStart(it) == start }
            annotation?.let {
                text.setSpan(Annotation(COLLABORATION_MEMBER_ANNOTATION, member.id), start,
                    text.getSpanEnd(it), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                agentGoalInput.setSelection((text.getSpanEnd(it) + 1).coerceAtMost(text.length))
            }
            dismiss()
        }
        show()
    }
}

internal fun MainActivity.collaborationMemberRow(member: CollaborationMember): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(12), dp(8), dp(12), dp(8))
    minimumHeight = dp(58)
    addView(ImageView(this@collaborationMemberRow).apply {
        setImageDrawable(GalaxySSIIdenticonDrawable(member.id))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }, LinearLayout.LayoutParams(dp(32), dp(32)).apply { marginEnd = dp(10) })
    addView(LinearLayout(this@collaborationMemberRow).apply {
        orientation = LinearLayout.VERTICAL
        addView(TextView(context).apply {
            text = "${member.name}  ${getString(R.string.collaboration_ai)}"
            textSize = 14f; setTypeface(typeface, Typeface.BOLD)
            setTextColor(getColorCompat(R.color.text_primary))
        })
        addView(TextView(context).apply {
            text = listOf(member.providerLabel, member.modelId, member.role).filter(String::isNotBlank).joinToString(" · ")
            textSize = 11f; maxLines = 2
            setTextColor(getColorCompat(R.color.text_secondary))
        })
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
}

internal fun MainActivity.showCollaborationMembers() {
    collaborationLoad { loaded ->
        val group = loaded ?: CollaborationGroup(agentTranscriptStore.activeConversation().id)
        val options = group.members.map { "${it.name} · ${it.role.ifBlank { it.providerLabel }}" } +
            getString(R.string.collaboration_add)
        AlertDialog.Builder(this).setTitle(R.string.collaboration_settings)
            .setItems(options.toTypedArray()) { _, index ->
                if (index == group.members.size) addCollaborationMember(group)
                else showCollaborationMemberSettings(group, group.members[index])
            }.setNegativeButton(R.string.common_cancel, null).show()
    }
}

private fun MainActivity.addCollaborationMember(group: CollaborationGroup) {
    if (group.members.size >= CollaborationGroup.MAX_MEMBERS) {
        Toast.makeText(this, R.string.collaboration_member_limit, Toast.LENGTH_LONG).show(); return
    }
    chooseCollaborationProvider { target, modelId ->
            collaborationUpdate(group.conversationId, { latest ->
                val member = CollaborationMember(
                    name = CollaborationNamePolicy.allocate(CollaborationGroupStore.names(this), latest.members.map { it.name }),
                    agentId = target.id, providerLabel = target.title, modelId = modelId,
                    role = if (latest.members.isEmpty()) getString(R.string.collaboration_coordinator) else ""
                )
                latest.copy(members = latest.members + member,
                    coordinatorId = latest.coordinatorId.ifBlank { member.id })
            }) { updated -> showCollaborationMemberSettings(updated, updated.members.last()) }
    }
}

private fun MainActivity.chooseCollaborationProvider(selected: (AgentCallableTarget, String) -> Unit) {
    collaborationIo.execute {
        val result = runCatching {
            val targets = AppStoreAgentConnectorRegistry(this).availableTargets()
            AgentModelSelectionPolicy.selectableAgentTargets(targets) +
                targets.filter { it.kind == AgentConnectorKind.MODEL && it.status == AgentConnectorStatus.AVAILABLE }
        }
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            val candidates = result.getOrElse { collaborationFailure(it); return@runOnUiThread }
            if (candidates.isEmpty()) {
                Toast.makeText(this, R.string.agent_mention_no_available, Toast.LENGTH_LONG).show()
                return@runOnUiThread
            }
            AlertDialog.Builder(this).setTitle(R.string.collaboration_provider)
                .setItems(candidates.map { it.title }.toTypedArray()) { _, index ->
                    val target = candidates[index]
                    val models = target.invocationProfile.models.filterNot { RetiredAgentModelPolicy.isRetired(it.id) }
                    if (models.isEmpty()) selected(target, "")
                    else AlertDialog.Builder(this).setTitle(target.title)
                        .setItems(models.map { it.displayName }.toTypedArray()) { _, model -> selected(target, models[model].id) }
                        .setNegativeButton(R.string.common_cancel, null).show()
                }.setNegativeButton(R.string.common_cancel, null).show()
        }
    }
}

private fun MainActivity.showCollaborationMemberSettings(group: CollaborationGroup, member: CollaborationMember) {
    val content = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(8))
    }
    content.addView(collaborationMemberRow(member))
    val name = EditText(this).apply {
        setText(member.name); hint = getString(R.string.collaboration_name); maxLines = 1
        filters = arrayOf(android.text.InputFilter.LengthFilter(48))
    }
    val role = EditText(this).apply {
        setText(member.role); hint = getString(R.string.collaboration_role); maxLines = 3
        filters = arrayOf(android.text.InputFilter.LengthFilter(240))
    }
    content.addView(name); content.addView(role)
    var providerMember = member
    val provider = TextView(this).apply {
        text = listOf(member.providerLabel, member.modelId).filter(String::isNotBlank).joinToString(" · ")
        minHeight = dp(48); gravity = Gravity.CENTER_VERTICAL; textSize = 14f
        setTextColor(getColorCompat(R.color.text_primary))
        setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, R.drawable.ic_chevron_down, 0)
        setOnClickListener { chooseCollaborationProvider { target, modelId ->
            providerMember = member.copy(agentId = target.id, providerLabel = target.title, modelId = modelId)
            text = listOf(target.title, modelId).filter(String::isNotBlank).joinToString(" · ")
        } }
    }
    content.addView(provider)
    val choices = RadioGroup(this).apply {
        listOf(R.string.collaboration_mention_only, R.string.collaboration_by_role, R.string.collaboration_proactive)
            .forEachIndexed { index, label -> addView(RadioButton(context).apply {
                id = index + 1; setText(label); textSize = 14f; minHeight = dp(44)
            }) }
        check(member.participation.ordinal + 1)
    }
    content.addView(choices)
    fun toggle(label: Int, checked: Boolean) = Switch(this).apply {
        setText(label); textSize = 13f; isChecked = checked; minHeight = dp(48); content.addView(this)
    }
    val observe = toggle(R.string.collaboration_observe, member.observeMessages)
    val results = toggle(R.string.collaboration_results, member.receiveResults)
    val independent = toggle(R.string.collaboration_independent, member.independentReview)
    val coordinator = toggle(R.string.collaboration_coordinator, group.coordinatorId == member.id)
    coordinator.isEnabled = group.coordinatorId != member.id
    val dialog = AlertDialog.Builder(this).setTitle(R.string.collaboration_settings)
        .setView(ScrollView(this).apply { addView(content) })
        .setNegativeButton(R.string.common_cancel, null)
        .setNeutralButton(R.string.collaboration_remove) { _, _ ->
            collaborationUpdate(group.conversationId, { latest ->
                val remaining = latest.members.filterNot { it.id == member.id }
                latest.copy(members = remaining, coordinatorId = latest.coordinatorId.takeIf { id -> remaining.any { it.id == id } }
                    ?: remaining.firstOrNull()?.id.orEmpty())
            }) { showCollaborationMembers() }
        }.setPositiveButton(R.string.collaboration_done, null).create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val newName = name.text.toString().trim()
            if (newName.isBlank() || newName.length > 48 || group.members.any { it.id != member.id && it.name.equals(newName, true) }) {
                name.error = getString(R.string.collaboration_invalid_name); return@setOnClickListener
            }
            val updated = providerMember.copy(name = newName, role = role.text.toString().trim().take(240),
                participation = CollaborationParticipation.entries[choices.checkedRadioButtonId - 1],
                observeMessages = observe.isChecked, receiveResults = results.isChecked, independentReview = independent.isChecked)
            collaborationUpdate(group.conversationId, { latest ->
                latest.copy(members = latest.members.map { if (it.id == member.id) updated else it },
                    coordinatorId = if (coordinator.isChecked) member.id else latest.coordinatorId)
            }) { dialog.dismiss() }
        }
    }
    dialog.show()
    dialog.window?.setGravity(Gravity.BOTTOM)
}

internal fun MainActivity.collaborationRequestedMembers(
    conversationId: String, explicit: List<AgentRequestedMember>, useComposer: Boolean = true
): List<AgentRequestedMember> {
    val group = CollaborationGroupStore.cached(conversationId) ?: return explicit
    val text = agentGoalInput.text.takeIf { useComposer }
    val selectedIds = text?.getSpans(0, text.length, Annotation::class.java)
        ?.filter { it.key == COLLABORATION_MEMBER_ANNOTATION }?.sortedBy { text.getSpanStart(it) }
        ?.map { it.value }.orEmpty()
    val matched = selectedIds.mapNotNull { id -> group.members.firstOrNull { it.id == id } }
        .ifEmpty { CollaborationMentionPolicy.resolve(text?.toString().orEmpty(), group.members) }
    val selected = matched
        .distinctBy { it.id }.map { member -> member.requested(conversationId,
            explicit.firstOrNull { it.agentId == member.agentId && it.displayName == member.name }?.roleHint.orEmpty()) }
    if (explicit.isNotEmpty() && selected.isEmpty()) return emptyList()
    return group.requested(selected)
}

internal fun MainActivity.refreshCollaborationStrip() {
    val strip = findViewById<TextView>(R.id.collaborationMemberStrip) ?: return
    val id = agentRenderedConversationId.ifBlank { agentTranscriptStore.activeConversation().id }
    val group = CollaborationGroupStore.cached(id)
    strip.visibility = if (group?.members?.isNotEmpty() == true) View.VISIBLE else View.GONE
    if (group != null) {
        strip.text = getString(R.string.collaboration_member_summary, group.members.size)
        collaborationHeaderLabel(group.conversationId)?.let { agentSubtitleText.text = it }
    }
    strip.setOnClickListener { showCollaborationMembers() }
}

internal fun MainActivity.loadCollaborationGroup() = collaborationLoad { refreshCollaborationStrip() }
internal fun MainActivity.collaborationHeaderLabel(id: String): String? {
    val group = CollaborationGroupStore.cached(id)?.takeIf { it.members.isNotEmpty() } ?: return null
    val name = group.members.firstOrNull { it.id == group.coordinatorId }?.name.orEmpty()
    return getString(R.string.collaboration_header, name)
}
internal const val COLLABORATION_MEMBER_ANNOTATION = "galaxyssi_collaboration_member"
