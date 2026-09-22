package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

/** Reparents existing controls without recreating managers, bindings or download state. */
internal fun MainActivity.arrangeMyAgentResourceSections(priority: List<Int>, collapsed: Set<Int>) {
    if (!myAgentSurfaceActive()) return
    val children = (0 until featureContent.childCount).map(featureContent::getChildAt)
    val prefix = mutableListOf<View>()
    val sections = mutableListOf<Pair<TextView, MutableList<View>>>()
    children.forEach { child ->
        if (child is TextView && child.tag?.toString()?.startsWith("my-agent-section:") == true) {
            sections += child to mutableListOf<View>()
        } else if (sections.isEmpty()) prefix += child
        else sections.last().second += child
    }
    val order = priority.map(::getString)
    val folded = collapsed.map(::getString).toSet()
    featureContent.removeAllViews()
    prefix.forEach(featureContent::addView)
    sections.sortedBy { order.indexOf(it.first.text.toString()).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }
        .forEach { (title, views) ->
            featureContent.addView(title)
            val group = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                views.forEach(::addView)
            }
            if (title.text.toString() in folded) {
                val key = "resource:${title.text}"
                group.visibility = if (key in myAgentExpandedSections) View.VISIBLE else View.GONE
                title.minimumHeight = dp(48)
                title.isClickable = true
                title.isFocusable = true
                title.setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, R.drawable.ic_arrow_right, 0)
                title.setOnClickListener {
                    val expanded = group.visibility != View.VISIBLE
                    group.visibility = if (expanded) View.VISIBLE else View.GONE
                    if (expanded) myAgentExpandedSections.add(key) else myAgentExpandedSections.remove(key)
                }
            }
            featureContent.addView(group)
        }
}
