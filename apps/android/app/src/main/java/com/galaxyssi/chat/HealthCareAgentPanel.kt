package com.galaxyssi.chat

import android.app.Activity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView

/** Keeps the collapse control reachable while the full health context scrolls independently. */
internal class HealthCareAgentPanel(
    activity: Activity,
    title: String,
    summary: String,
    priority: String?,
    initiallyExpanded: Boolean,
    private val onExpandedChanged: (Boolean) -> Unit
) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val summaryDescription = listOfNotNull(title, summary, priority).joinToString(", ")
    val content = ui.column()
    val scroll = ScrollView(activity).apply {
        tag = "agent-health-care-scroll"
        isFillViewport = false
        addView(content)
    }
    private var expanded = initiallyExpanded
    private val toggle = ui.icon(R.drawable.ic_chevron_down, R.string.health_agent_expand) { toggle() }
        .apply { tag = "agent-health-care-expand" }

    init {
        orientation = VERTICAL
        tag = "agent-health-care-panel"
        addView(ui.line().apply {
            minimumHeight = ui.dp(48)
            addView(ui.column().apply {
                tag = "agent-health-care-concern"
                setPadding(ui.dp(4), ui.dp(6), ui.dp(4), ui.dp(6))
                addView(ui.text(title, 16f, bold = true))
                addView(ui.text(summary, 13f, muted = true))
                priority?.let { addView(ui.text(it, 13f, bold = true).apply { tag = "agent-health-care-priority" }) }
                setOnClickListener { toggle() }
                isFocusable = true
            }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(toggle)
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        updateVisibility()
    }

    private fun toggle() {
        expanded = !expanded
        updateVisibility()
        onExpandedChanged(expanded)
    }

    private fun updateVisibility() {
        scroll.visibility = if (expanded) View.VISIBLE else View.GONE
        toggle.rotation = if (expanded) 180f else 0f
        toggle.isSelected = expanded
        toggle.contentDescription = context.getString(if (expanded) R.string.health_agent_collapse else R.string.health_agent_expand)
        toggle.tooltipText = toggle.contentDescription
        findViewWithTag<View>("agent-health-care-concern").contentDescription = "$summaryDescription. ${toggle.contentDescription}"
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(heightMeasureSpec)
        val limit = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) ui.dp(300)
            else minOf(ui.dp(300), (available * .4f).toInt())
        super.onMeasure(widthMeasureSpec, if (expanded) MeasureSpec.makeMeasureSpec(limit, MeasureSpec.AT_MOST) else heightMeasureSpec)
    }
}
