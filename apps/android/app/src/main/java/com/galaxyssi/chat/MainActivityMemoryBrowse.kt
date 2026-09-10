package com.galaxyssi.chat

import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.Toast

internal fun MainActivity.renderPagedAgentMemory(content: AgentMemoryPageContent, kinds: Set<AgentMemoryKind>) {
    val page = content.page
    featureContent.addView(featureHeroCard(getString(R.string.agent_memory_hero_title),
        getString(R.string.agent_memory_hero_subtitle, page.counts.active, page.counts.conflicts, page.counts.history),
        R.drawable.ic_agent_node, "#5B6CFF", getString(if (content.captureEnabled) R.string.common_on else R.string.common_off)))

    val tabs = RadioGroup(this).apply { orientation = LinearLayout.HORIZONTAL }
    AgentMemorySection.entries.forEach { section ->
        val button = RadioButton(this).apply {
            id = View.generateViewId()
            text = getString(when (section) {
                AgentMemorySection.ACTIVE -> R.string.agent_memory_section_saved
                AgentMemorySection.CONFLICTS -> R.string.agent_memory_section_conflicts
                AgentMemorySection.HISTORY -> R.string.agent_memory_section_history
            })
            layoutParams = RadioGroup.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            isChecked = section == content.request.section
            setOnClickListener { if (section != content.request.section) showAgentMemoryPage(kinds,
                content.request.copy(section = section, cursor = null, backwards = false)) }
        }
        tabs.addView(button)
    }
    featureContent.addView(tabs)
    if (page.entries.isEmpty()) featureContent.addView(featureRow(
        getString(if (content.request.section == AgentMemorySection.CONFLICTS) R.string.agent_memory_no_conflicts else R.string.agent_memory_empty),
        "", R.drawable.ic_agent_node, ""))
    page.entries.forEach { entry ->
        val item = entry.item
        val isConflict = content.request.section == AgentMemorySection.CONFLICTS
        val title = if (isConflict) item.key.ifBlank { memoryKindLabel(item.kind) } else item.value.replace(Regex("\\s+"), " ").take(80)
        val subtitle = if (isConflict) getString(R.string.agent_memory_conflict_subtitle, memoryKindLabel(item.kind), entry.conflictSize)
            else getString(R.string.agent_memory_browse_item_subtitle, memoryKindLabel(item.kind), item.version, memorySourceLabel(item.source),
                (item.confidence.coerceIn(0.0, 1.0) * 100).toInt(), item.evidenceCount, item.key.ifBlank { getString(R.string.agent_memory_key_none) })
        val action = getString(when {
            isConflict -> R.string.agent_memory_review
            item.privateMemory -> R.string.agent_memory_private
            item.important -> R.string.agent_memory_pinned
            else -> R.string.common_edit
        })
        featureContent.addView(featureRow(title, subtitle, if (isConflict) R.drawable.ic_security_shield else R.drawable.ic_agent_node, action).apply {
            setOnClickListener {
                if (!isConflict) showAgentMemoryItemActions(item, kinds)
                else runAgentMemoryMutation({ mobileNativeAgent.memoryStore.browseConflict(item) }) { conflict ->
                    if (conflict != null) showAgentMemoryConflictDialog(conflict, kinds)
                    else {
                        Toast.makeText(this@renderPagedAgentMemory, getString(R.string.agent_memory_conflict_resolution_failed), Toast.LENGTH_SHORT).show()
                        showAgentMemoryPage(kinds, content.request.copy(cursor = null, backwards = false))
                    }
                }
            }
        })
    }
    val navigation = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.END }
    fun button(icon: Int, label: Int, request: AgentMemoryBrowseRequest) = ImageButton(this).apply {
        setImageResource(icon); contentDescription = getString(label); tooltipText = contentDescription
        val density = resources.displayMetrics.density
        val padding = (12 * density).toInt()
        setPadding(padding, padding, padding, padding)
        scaleType = ImageView.ScaleType.FIT_CENTER
        val background = android.util.TypedValue()
        theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, background, true)
        setBackgroundResource(background.resourceId)
        layoutParams = LinearLayout.LayoutParams((48 * density).toInt(), (48 * density).toInt())
        setOnClickListener { showAgentMemoryPage(kinds, request) }
    }
    page.previous?.let { navigation.addView(button(R.drawable.ic_navigation_back, R.string.agent_memory_page_previous,
        content.request.copy(cursor = it, backwards = true))) }
    page.next?.let { navigation.addView(button(R.drawable.ic_arrow_right, R.string.agent_memory_page_next,
        content.request.copy(cursor = it, backwards = false))) }
    if (navigation.childCount > 0) featureContent.addView(navigation)
}
