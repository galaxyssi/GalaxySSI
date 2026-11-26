package com.galaxyssi.chat

import android.content.res.ColorStateList
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

internal fun MainActivity.showAgentModelSelectionPage() {
    showFeaturePage(getString(R.string.agent_model_selection_title))
    setFeatureBackAction { hideFeaturePage() }
    val page = AgentModelPickerPage(this, navigationContentGate.begin())
    featureContent.tag = page
    page.load()
    GalaxySSIMqttClient.requestCapabilityManifestRefresh(force = true)
}

internal fun MainActivity.refreshOpenAgentModelPicker() {
    featureContent.post {
        (featureContent.tag as? AgentModelPickerPage)?.load()
    }
}

internal data class AgentModelPickerSnapshot(
    val conversationId: String,
    val targets: List<AgentCallableTarget>,
    val local: List<LocalModelRuntimeProfile>
)

internal class AgentModelPickerPage(
    private val activity: MainActivity,
    private val generation: Long,
    private val preferencesContext: Context = activity
) {
    private val content = activity.featureContent
    private val footer = activity.findViewById<LinearLayout>(R.id.featurePinnedFooter)
    private val scroll = content.parent as ScrollView
    private var snapshot: AgentModelPickerSnapshot? = null
    private var selection = AgentModelSelection()
    private var source = AgentModelPickerSource.DESKTOP
    private var expandedTargetId: String? = null
    private var expandedLegacy = false
    private var loadInFlight = false
    private var reloadPending = false
    private val accent get() = activity.getColorCompat(R.color.agent_model_picker_accent)
    private val muted get() = activity.getColorCompat(R.color.agent_model_picker_muted)
    private val textColor get() = activity.getColorCompat(R.color.text_primary)
    private val selectionFill get() = activity.adjustAlpha(accent, 0.12f)

    init {
        content.setPadding(activity.dp(16), activity.dp(10), activity.dp(16), activity.dp(10))
        content.addView(text(activity.getString(R.string.navigation_content_loading), 14f, muted).apply {
            setPadding(activity.dp(8), activity.dp(10), activity.dp(8), 0)
        })
        scroll.scrollTo(0, 0)
    }

    private fun isOpen(): Boolean = activity.navigationContentGate.isCurrent(generation) &&
        activity.featurePage.visibility == View.VISIBLE && content.tag === this

    fun load() {
        if (!isOpen()) return
        if (loadInFlight) {
            reloadPending = true
            return
        }
        loadInFlight = true
        activity.navigationContentExecutor.execute {
            val next = runCatching {
                AgentModelPickerSnapshot(
                    activity.agentTranscriptStore.activeConversation().id,
                    AppStoreAgentConnectorRegistry(activity).availableTargets(),
                    LocalModelRuntimeSettings.activeProfiles(activity)
                )
            }.getOrNull()
            activity.handler.post {
                loadInFlight = false
                if (!isOpen()) return@post
                if (next == null) {
                    if (snapshot == null) renderLoadFailure()
                } else {
                    bind(next)
                }
                if (reloadPending) {
                    reloadPending = false
                    load()
                }
            }
        }
    }

    internal fun bind(next: AgentModelPickerSnapshot) {
        if (!isOpen()) return
        val nextSelection = AgentModelSelectionSettings.selection(preferencesContext, next.conversationId)
        if (snapshot == next && selection == nextSelection) return
        val fresh = snapshot?.conversationId != next.conversationId
        snapshot = next
        selection = nextSelection
        if (fresh) {
            val selectedId = selection.targetId
            val clouds = AgentModelPickerPolicy.cloudTargets(next.targets)
            val agents = AgentModelPickerPolicy.desktopTargets(next.targets, selectedId)
            source = when {
                selectedId == "local-llm" -> AgentModelPickerSource.LOCAL
                next.targets.any { it.id == selectedId && it.kind == AgentConnectorKind.MODEL } ||
                    selectedId.startsWith("cloud:") -> AgentModelPickerSource.CLOUD
                selectedId.isNotBlank() || agents.isNotEmpty() -> AgentModelPickerSource.DESKTOP
                clouds.isNotEmpty() -> AgentModelPickerSource.CLOUD
                next.local.isNotEmpty() -> AgentModelPickerSource.LOCAL
                else -> AgentModelPickerSource.DESKTOP
            }
            expandedTargetId = preferredExpandedTarget(next)
            expandedLegacy = false
        } else if (expandedTargetId == null ||
            (expandedTargetId?.isNotBlank() == true && sourceTargets(next).none { it.id == expandedTargetId })
        ) {
            expandedTargetId = preferredExpandedTarget(next)
            expandedLegacy = false
        }
        render(resetScroll = fresh)
    }

    private fun preferredExpandedTarget(data: AgentModelPickerSnapshot): String? {
        val targets = sourceTargets(data)
        return targets.firstOrNull { it.id == selection.targetId && it.invocationProfile.models.isNotEmpty() }?.id
            ?: targets.firstOrNull { it.invocationProfile.models.isNotEmpty() }?.id
    }

    private fun sourceTargets(data: AgentModelPickerSnapshot): List<AgentCallableTarget> = when (source) {
        AgentModelPickerSource.DESKTOP -> AgentModelPickerPolicy.desktopTargets(data.targets, selection.targetId)
        AgentModelPickerSource.CLOUD -> AgentModelPickerPolicy.cloudTargets(data.targets)
        AgentModelPickerSource.LOCAL -> emptyList()
    }

    private fun renderLoadFailure() {
        content.removeAllViews()
        content.addView(text(activity.getString(R.string.agent_model_picker_retry), 14f, accent, bold = true).apply {
            minHeight = activity.dp(48)
            gravity = Gravity.CENTER
            action { load() }
        }, fullWidth())
    }

    private fun render(resetScroll: Boolean = false) {
        val data = snapshot ?: return
        val previousScroll = if (resetScroll) 0 else scroll.scrollY
        content.removeAllViews()
        content.addView(summary(data), fullWidth())
        content.addView(autoRow(data), fullWidth())
        content.addView(sourceTabs(data), fullWidth().apply { bottomMargin = activity.dp(7) })

        val targets = sourceTargets(data)
        if (source == AgentModelPickerSource.LOCAL) {
            data.local.forEach { profile -> content.addView(localRow(data, profile), fullWidth()) }
        } else {
            targets.forEach { target ->
                content.addView(divider(), fullWidth(activity.dp(1)))
                content.addView(providerRow(data, target), fullWidth())
                if (target.id == expandedTargetId) renderModels(data, target)
            }
        }
        if ((source == AgentModelPickerSource.LOCAL && data.local.isEmpty()) ||
            (source != AgentModelPickerSource.LOCAL && targets.isEmpty())
        ) {
            content.addView(text(activity.getString(when (source) {
                AgentModelPickerSource.DESKTOP -> R.string.agent_model_picker_no_desktop
                AgentModelPickerSource.CLOUD -> R.string.agent_model_picker_no_cloud
                AgentModelPickerSource.LOCAL -> R.string.agent_model_picker_no_local
            }), 13f, muted).apply { setPadding(activity.dp(8), activity.dp(14), activity.dp(8), activity.dp(6)) })
        }
        renderFooter(data)
        scroll.post { if (isOpen()) scroll.scrollTo(0, previousScroll) }
    }

    private fun summary(data: AgentModelPickerSnapshot): View = column().apply {
        tag = "agent-model-summary"
        background = shape(selectionFill, 7)
        setPadding(activity.dp(11), activity.dp(7), activity.dp(11), activity.dp(7))
        addView(text(activity.getString(R.string.agent_model_picker_current), 11f, accent, bold = true))
        val automatic = selection.mode == AgentModelSelectionMode.AUTO
        val target = data.targets.firstOrNull { it.id == selection.targetId }
        val local = data.local.firstOrNull { selection.targetId == "local-llm" && it.id == selection.modelId }
        val modelId = target?.invocationProfile?.modelAliases?.get(selection.modelId) ?: selection.modelId
        val title = when {
            automatic -> activity.getString(R.string.agent_model_selection_automatic)
            local != null -> local.displayName
            modelId.isNotBlank() -> friendlyModel(modelId)
            else -> selection.displayName.ifBlank { target?.title ?: selection.targetId }
        }
        addView(row().apply {
            addView(text(title, 17f, textColor, bold = true), weighted())
            selection.reasoningEffort.takeIf { !automatic && it != AgentModelReasoningEffort.AUTO }?.let { effort ->
                addView(text(activity.getString(R.string.agent_model_picker_effort_value,
                    activity.getString(effort.labelResource())), 12f, accent, bold = true),
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                        .apply { marginStart = activity.dp(8) })
            }
        })
        val destination = when {
            automatic -> activity.getString(R.string.agent_model_picker_auto_detail)
            local != null -> activity.getString(R.string.agent_model_selection_local_section)
            target != null -> target.title
            else -> selection.displayName.ifBlank { selection.targetId }
        }
        val available = automatic || local != null || target?.status == AgentConnectorStatus.AVAILABLE
        val subtitle = if (available) destination else activity.getString(
            R.string.agent_model_picker_disconnected, destination)
        if (subtitle.isNotBlank()) addView(text(subtitle, 11.5f, muted))
    }

    private fun autoRow(data: AgentModelPickerSnapshot): View = row().apply {
        tag = "agent-model-auto"
        minimumHeight = activity.dp(48)
        setPadding(activity.dp(3), activity.dp(4), activity.dp(5), activity.dp(4))
        val chosen = selection.mode == AgentModelSelectionMode.AUTO
        val icon = activity.featureIcon(R.drawable.ic_agent_skill, Color.parseColor("#12BFA4"))
        icon.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        addView(icon, LinearLayout.LayoutParams(activity.dp(34), activity.dp(34)))
        addView(labels(activity.getString(R.string.agent_model_selection_automatic),
            activity.getString(R.string.agent_model_picker_auto_detail)), weighted(9))
        addView(selectionMark(chosen), markParams())
        isSelected = chosen
        background = ripple(Color.TRANSPARENT)
        action { save(data) { AgentModelSelectionSettings.selectAuto(preferencesContext, data.conversationId) } }
    }

    private fun sourceTabs(data: AgentModelPickerSnapshot): View = row().apply {
        background = shape(activity.getColorCompat(R.color.button_soft), 7)
        setPadding(activity.dp(3), activity.dp(3), activity.dp(3), activity.dp(3))
        AgentModelPickerSource.entries.forEach { tab ->
            val label = when (tab) {
                AgentModelPickerSource.DESKTOP -> R.string.agent_model_selection_agent_section
                AgentModelPickerSource.CLOUD -> R.string.agent_model_selection_cloud_section
                AgentModelPickerSource.LOCAL -> R.string.agent_model_selection_local_section
            }
            addView(text(activity.getString(label), 13f, if (tab == source) textColor else muted, bold = tab == source).apply {
                tag = "agent-model-source:${tab.name}"
                gravity = Gravity.CENTER
                minHeight = activity.dp(44)
                setPadding(activity.dp(3), activity.dp(3), activity.dp(3), activity.dp(3))
                isSelected = tab == source
                background = ripple(if (isSelected) activity.getColorCompat(R.color.surface_bg) else Color.TRANSPARENT)
                action {
                    if (source != tab) {
                        source = tab
                        expandedTargetId = preferredExpandedTarget(data)
                        expandedLegacy = false
                        render(resetScroll = true)
                    }
                }
            }, weighted())
        }
    }

    private fun providerRow(data: AgentModelPickerSnapshot, target: AgentCallableTarget): View = row().apply {
        tag = "agent-model-provider:${target.id}"
        minimumHeight = activity.dp(54)
        setPadding(activity.dp(3), activity.dp(5), activity.dp(5), activity.dp(5))
        val cloud = source == AgentModelPickerSource.CLOUD
        val (name, computer) = if (cloud) target.title to "" else AgentModelPickerPolicy.desktopLabel(target.title)
        val icon = if (cloud) activity.providerIcon(target.providerProfile?.providerId.orEmpty().ifBlank { name })
            else activity.controlCenterTargetIcon(target)
        val tint = if (cloud) Color.parseColor(activity.providerColor(target.providerProfile?.providerId.orEmpty().ifBlank { name }))
            else activity.featureIconColor(icon)
        addView(activity.featureIcon(icon, tint).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(activity.dp(44), activity.dp(44)))
        addView(text(name, 14f, textColor, bold = true), weighted(8))
        val location = if (cloud) activity.getString(R.string.agent_model_picker_direct) else computer
        if (location.isNotBlank()) addView(text(location, 11.5f, muted).apply {
            maxWidth = activity.dp(115)
            gravity = Gravity.END
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { marginStart = activity.dp(6) })
        val canExpand = AgentModelPickerPolicy.modelGroups(target, "").first.isNotEmpty()
        val expanded = target.id == expandedTargetId
        if (canExpand) addView(chevron(expanded), markParams()) else addView(selectionMark(target.id == selection.targetId), markParams())
        isSelected = target.id == selection.targetId
        background = ripple(Color.TRANSPARENT)
        action {
            if (canExpand) {
                expandedTargetId = if (expanded) "" else target.id
                expandedLegacy = false
                render()
            } else {
                choose(data, target, target.invocationProfile.defaultModelId.ifBlank { target.providerProfile?.modelId.orEmpty() })
            }
        }
    }

    private fun renderModels(data: AgentModelPickerSnapshot, target: AgentCallableTarget) {
        val active = target.id == selection.targetId
        val rawId = if (active) selection.modelId.ifBlank { target.invocationProfile.defaultModelId } else ""
        val selectedId = target.invocationProfile.modelAliases[rawId] ?: rawId
        val (visible, folded) = AgentModelPickerPolicy.modelGroups(target, selectedId)
        visible.forEach { addModel(data, target, it, active && it.id == selectedId) }
        if (folded.isEmpty()) return
        content.addView(row().apply {
            tag = "agent-model-older"
            minimumHeight = activity.dp(44)
            setPadding(activity.dp(9), 0, activity.dp(5), 0)
            addView(text(activity.getString(R.string.agent_model_picker_older), 12.5f, muted), weighted())
            addView(chevron(expandedLegacy), markParams())
            background = ripple(Color.TRANSPARENT)
            action { expandedLegacy = !expandedLegacy; render() }
        }, fullWidth())
        if (expandedLegacy) folded.forEach { addModel(data, target, it, false) }
    }

    private fun addModel(data: AgentModelPickerSnapshot, target: AgentCallableTarget, model: AgentModelOption, selected: Boolean) {
        val title = model.displayName.takeUnless { it == model.id }.orEmpty().ifBlank { friendlyModel(model.id) }
        val detail = when (model.id) {
            "gpt-6.2-astra" -> activity.getString(R.string.agent_model_picker_astra)
            "gpt-6.2-sol" -> activity.getString(R.string.agent_model_picker_sol)
            "gpt-6.1-terra" -> activity.getString(R.string.agent_model_picker_terra)
            "gpt-6-luna" -> activity.getString(R.string.agent_model_picker_luna)
            else -> model.description.takeUnless { it.equals(title, ignoreCase = true) }.orEmpty()
        }
        content.addView(modelRow(title, detail, selected).apply {
            tag = "agent-model-option:${target.id}:${model.id}"
            action { choose(data, target, model.id) }
        }, fullWidth())
    }

    private fun localRow(data: AgentModelPickerSnapshot, profile: LocalModelRuntimeProfile): View =
        modelRow(profile.displayName, activity.getString(R.string.agent_model_selection_local_subtitle),
            selection.targetId == "local-llm" && selection.modelId == profile.id,
            icon = R.drawable.ic_local_model).apply {
            action {
                save(data) {
                    LocalModelRuntimeSettings.setSelectedProfile(activity, profile.id)
                    AgentModelSelectionSettings.selectManual(preferencesContext, data.conversationId, "local-llm",
                        profile.id, profile.displayName)
                }
            }
        }

    private fun modelRow(title: String, detail: String, selected: Boolean, icon: Int? = null): LinearLayout = row().apply {
        minimumHeight = activity.dp(44)
        setPadding(activity.dp(9), activity.dp(4), activity.dp(5), activity.dp(4))
        if (icon != null) addView(activity.featureIcon(icon, activity.featureIconColor(icon)).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(activity.dp(44), activity.dp(44)).apply { marginEnd = activity.dp(8) })
        addView(labels(title, detail), weighted())
        addView(selectionMark(selected), markParams())
        isSelected = selected
        background = ripple(if (selected) selectionFill else Color.TRANSPARENT)
    }

    private fun choose(data: AgentModelPickerSnapshot, target: AgentCallableTarget, modelId: String) {
        save(data) {
            val saved = AgentModelSelectionSettings.configurationForTarget(preferencesContext, data.conversationId, target.id)
            val efforts = target.invocationProfile.reasoningEfforts
            val effort = saved?.reasoningEffort?.takeIf { it in efforts }
                ?: efforts.firstOrNull() ?: AgentModelReasoningEffort.AUTO
            val name = if (target.kind == AgentConnectorKind.MODEL && modelId.isNotBlank()) friendlyModel(modelId) else target.title
            AgentModelSelectionSettings.selectManual(preferencesContext, data.conversationId, target.id, modelId, name, effort)
        }
    }

    private fun save(data: AgentModelPickerSnapshot, apply: () -> Unit) {
        if (!isOpen() || snapshot !== data) return
        apply()
        selection = AgentModelSelectionSettings.selection(preferencesContext, data.conversationId)
        activity.refreshAgentConversationHeader()
        render()
    }

    private fun renderFooter(data: AgentModelPickerSnapshot) = footer.apply {
        removeAllViews()
        visibility = View.VISIBLE
        setBackgroundColor(activity.getColorCompat(R.color.bar_bg))
        setPadding(activity.dp(16), 0, activity.dp(16), activity.dp(7))
        addView(divider(), fullWidth(activity.dp(1)))
        val target = data.targets.firstOrNull { it.id == selection.targetId && it.status == AgentConnectorStatus.AVAILABLE }
        val efforts = target?.invocationProfile?.reasoningEfforts.orEmpty()
        if (selection.mode == AgentModelSelectionMode.MANUAL && efforts.isNotEmpty()) {
            addView(row().apply {
                setPadding(0, activity.dp(5), 0, activity.dp(4))
                addView(text(activity.getString(R.string.agent_model_selection_reasoning_effort), 12f, textColor, bold = true),
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.1f)
                        .apply { marginEnd = activity.dp(6) })
                addView(row().apply {
                    background = shape(activity.getColorCompat(R.color.button_soft), 7)
                    setPadding(activity.dp(2), activity.dp(2), activity.dp(2), activity.dp(2))
                    efforts.forEach { effort ->
                        val selected = effort == selection.reasoningEffort
                        addView(text(activity.getString(effort.labelResource()), 12f, if (selected) accent else textColor, bold = selected).apply {
                            tag = "agent-model-effort:${effort.wireValue}"
                            gravity = Gravity.CENTER
                            minHeight = activity.dp(44)
                            isSelected = selected
                            background = ripple(if (selected) selectionFill else Color.TRANSPARENT)
                            action {
                                save(data) {
                                    AgentModelSelectionSettings.updateAgentConfiguration(preferencesContext, data.conversationId, selection.modelId, effort)
                                }
                            }
                        }, weighted())
                    }
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 4f))
            }, fullWidth())
        }
        addView(row().apply {
            setPadding(0, activity.dp(5), 0, 0)
            addView(glyph(R.drawable.ic_attention_bookmark, muted),
                LinearLayout.LayoutParams(activity.dp(14), activity.dp(14)).apply { marginEnd = activity.dp(5) })
            addView(text(activity.getString(R.string.agent_model_picker_remember), 11.5f, muted), weighted())
        }, fullWidth())
    }

    private fun friendlyModel(id: String): String =
        AgentModelPickerPolicy.modelLabel(id) ?: activity.modelDisplayLabel(id)

    private fun labels(title: String, detail: String): View = column().apply {
        addView(text(title, 14f, textColor, bold = true))
        if (detail.isNotBlank()) addView(text(detail, 11.5f, muted))
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean = false): TextView = TextView(activity).apply {
        text = value
        textSize = size
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    private fun View.action(click: () -> Unit) {
        isFocusable = true
        setOnClickListener { click() }
    }

    private fun row() = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun column() = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private fun divider() = View(activity).apply { setBackgroundColor(activity.getColorCompat(R.color.separator)) }
    private fun fullWidth(height: Int = LinearLayout.LayoutParams.WRAP_CONTENT) =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height)
    private fun weighted(start: Int = 0) = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        .apply { marginStart = activity.dp(start) }
    private fun markParams() = LinearLayout.LayoutParams(activity.dp(18), activity.dp(18)).apply { marginStart = activity.dp(8) }
    private fun glyph(id: Int, color: Int) = ImageView(activity).apply {
        setImageResource(id)
        imageTintList = ColorStateList.valueOf(color)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private fun chevron(expanded: Boolean) = glyph(R.drawable.ic_chevron_down, muted).apply { rotation = if (expanded) 180f else 0f }
    private fun selectionMark(selected: Boolean) = ImageView(activity).apply {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setStroke(activity.dp(1).coerceAtLeast(1), if (selected) accent else muted)
            setColor(Color.TRANSPARENT)
        }
        if (selected) {
            setImageResource(R.drawable.ic_attention_check)
            imageTintList = ColorStateList.valueOf(accent)
            setPadding(activity.dp(2), activity.dp(2), activity.dp(2), activity.dp(2))
        }
    }
    private fun shape(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = activity.dp(radius).toFloat()
    }
    private fun ripple(color: Int) = RippleDrawable(
        ColorStateList.valueOf(activity.adjustAlpha(accent, 0.16f)), shape(color, 5), shape(Color.WHITE, 5))
}
