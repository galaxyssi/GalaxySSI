package com.galaxyssi.chat

import android.content.Context
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

internal class CollaborationTeamPanelView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {
    private lateinit var host: MainActivity
    private var conversationId = ""
    private var rows = emptyList<CollaborationTeamPanelMember>()
    private var expanded = false
    private var status: ConversationHubAgentStatus? = null
    private val header = LinearLayout(context).apply {
        orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; minimumHeight = dip(48)
        isClickable = true; isFocusable = true; tag = "collaboration-team-toggle"
    }
    private val iconSlot = LinearLayout(context)
    private val title = label(13f).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END }
    private val counts = label(11f).apply { maxWidth = dip(146); maxLines = 2; gravity = Gravity.END }
    private val chevron = ImageView(context).apply {
        setImageResource(R.drawable.ic_chevron_down)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val adapter = MemberAdapter()
    private val list = RecyclerView(context).apply {
        tag = "collaboration-team-members"
        layoutManager = LinearLayoutManager(context)
        adapter = this@CollaborationTeamPanelView.adapter
        itemAnimator = null
        visibility = GONE
    }
    private val settings = label(14f).apply {
        tag = "collaboration-team-settings"
        setText(R.string.collaboration_settings)
        gravity = Gravity.CENTER_VERTICAL; minimumHeight = dip(48)
        setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_tab_settings, 0, R.drawable.ic_chevron_down, 0)
        compoundDrawablePadding = dip(10)
        visibility = GONE
        isFocusable = true
        setOnClickListener { host.showCollaborationMembers() }
    }

    init {
        orientation = VERTICAL
        header.addView(iconSlot, LayoutParams(dip(22), dip(22)).apply { marginEnd = dip(8) })
        header.addView(title, LayoutParams(0, -2, 1f))
        header.addView(counts, LayoutParams(-2, -2).apply { marginStart = dip(8) })
        header.addView(chevron, LayoutParams(dip(24), dip(24)).apply { marginStart = dip(8) })
        addView(header, LayoutParams(-1, -2))
        addView(list, LayoutParams(-1, -2))
        addView(settings, LayoutParams(-1, -2))
        header.setOnClickListener {
            expanded = !expanded
            host.agentResponseSectionExpansion[stateKey()] = expanded
            updateExpanded()
        }
        val selectable = android.util.TypedValue()
        context.theme.resolveAttribute(android.R.attr.selectableItemBackground, selectable, true)
        header.setBackgroundResource(selectable.resourceId)
        settings.setBackgroundResource(selectable.resourceId)
    }

    fun bind(activity: MainActivity, group: CollaborationGroup, history: List<AgentTranscriptEntry>,
        current: List<AgentTranscriptEntry>) {
        host = activity
        val changedConversation = conversationId != group.conversationId
        if (changedConversation) {
            conversationId = group.conversationId
            expanded = host.agentResponseSectionExpansion[stateKey()] == true
            list.scrollToPosition(0)
        }
        val next = CollaborationTeamPanelPolicy.rows(group, history, current)
        val nextStatus = CollaborationTeamPanelPolicy.status(next)
        if (changedConversation || nextStatus != status || iconSlot.childCount == 0) {
            status = nextStatus
            iconSlot.removeAllViews()
            if (nextStatus != null) iconSlot.addView(ConversationHubStatusIcon(context, nextStatus), LayoutParams(-1, -1))
            else iconSlot.addView(ImageView(context).apply { setImageResource(R.drawable.ic_hub_contacts_compact) }, LayoutParams(-1, -1))
        }
        val state = when (nextStatus) {
            null -> context.getString(R.string.collaboration_team_idle)
            ConversationHubAgentStatus.READ -> context.getString(R.string.agent_team_state_succeeded)
            else -> context.getString(nextStatus.labelRes())
        }
        title.text = context.getString(R.string.collaboration_team_summary, next.size, state)
        counts.text = context.getString(R.string.collaboration_team_counts,
            CollaborationTeamPanelPolicy.running(next), CollaborationTeamPanelPolicy.waiting(next))
        rows = next
        updateExpanded()
    }

    private fun updateExpanded() {
        list.visibility = if (expanded) VISIBLE else GONE
        settings.visibility = if (expanded) VISIBLE else GONE
        chevron.rotation = if (expanded) 180f else 0f
        header.contentDescription = "${title.text}, ${counts.text}, " + context.getString(
            if (expanded) R.string.research_trace_collapse else R.string.research_trace_expand)
        if (expanded) adapter.submit(rows) else adapter.submit(emptyList())
        requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // Keep the composer and conversation reachable even with 1,024 members or an open keyboard.
        val available = MeasureSpec.getSize(heightMeasureSpec).takeIf {
            it > 0 && MeasureSpec.getMode(heightMeasureSpec) != MeasureSpec.UNSPECIFIED
        } ?: (parent as? View)?.height?.takeIf { it > 0 } ?: resources.displayMetrics.heightPixels
        val height = minOf(rows.size * dip(118), (available * 0.50f).toInt()).coerceAtLeast(dip(96))
        if (list.layoutParams.height != height) list.layoutParams.height = height
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun stateKey() = "collaboration-team:$conversationId"
    private fun dip(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
    private fun label(size: Float) = TextView(context).apply {
        textSize = size; setTextColor(context.getColor(R.color.text_secondary))
    }

    private inner class MemberAdapter : RecyclerView.Adapter<MemberHolder>() {
        private var items = emptyList<CollaborationTeamPanelMember>()
        fun submit(next: List<CollaborationTeamPanelMember>) {
            if (items == next) return
            val before = items
            val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
                override fun getOldListSize() = before.size
                override fun getNewListSize() = next.size
                override fun areItemsTheSame(old: Int, new: Int) = before[old].member.id == next[new].member.id
                override fun areContentsTheSame(old: Int, new: Int) = before[old] == next[new]
            })
            items = next
            diff.dispatchUpdatesTo(this)
        }
        override fun getItemCount() = items.size
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = MemberHolder(LinearLayout(context).apply {
            orientation = VERTICAL; layoutParams = RecyclerView.LayoutParams(-1, -2)
        })
        override fun onBindViewHolder(holder: MemberHolder, position: Int) {
            val item = items[position]
            holder.container.removeAllViews()
            val metadata = item.metadata
            if (metadata != null && item.entry != null) {
                val presentation = metadata.copy(result = false, current = true, activity = false, summary = "",
                    name = item.member.name, provider = CollaborationLabelPolicy.provider(item.member.providerLabel, item.member.modelId),
                    role = item.member.role.ifBlank { metadata.role })
                val row = host.collaborationTranscriptRow(item.entry, presentation, showStageInHeader = false) as LinearLayout
                val action = host.collaborationStageLabel(metadata.researchStage).ifBlank {
                    item.entry.text.lineSequence().firstOrNull { it.isNotBlank() }.orEmpty().ifBlank {
                        context.getString(R.string.collaboration_team_unassigned)
                    }
                }
                row.addView(label(14f).apply {
                    tag = "collaboration-member-action"
                    text = action; maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
                    setTextColor(context.getColor(R.color.text_primary)); setTypeface(typeface, Typeface.BOLD)
                }, 1, LayoutParams(-1, -2))
                if (metadata.summary.isNotBlank()) row.addView(label(12f).apply {
                    tag = "collaboration-member-progress"; text = metadata.summary
                    maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(0, 0, 0, dip(6))
                }, 3, LayoutParams(-1, -2))
                holder.container.addView(row)
            } else {
                holder.container.addView(host.collaborationMemberRow(item.member, compact = true))
                holder.container.addView(label(13f).apply {
                    setText(R.string.collaboration_team_unassigned); setPadding(0, 0, 0, dip(12))
                })
            }
        }
    }
    private class MemberHolder(val container: LinearLayout) : RecyclerView.ViewHolder(container)
}
