package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal fun MainActivity.agentResearchTraceRow(entry: AgentTranscriptEntry, answer: String = entry.text): View {
    val stateKey = "research:${entry.conversationId}:${entry.turnId}"
    val container = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        visibility = View.GONE
        layoutParams = LinearLayout.LayoutParams(-1, -2)
    }
    var expanded = agentResponseSectionExpansion[stateKey] == true
    var current: AgentResearchTrace? = null
    var sourceLimit = 50
    var scope: CoroutineScope? = null
    val citedUrls = AgentResearchTrace.citedUrls(answer)
    fun render(trace: AgentResearchTrace) {
        container.removeAllViews()
        container.visibility = if (trace.visible) View.VISIBLE else View.GONE
        if (!trace.visible) return
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(40)
            isClickable = true
            isFocusable = true
        }
        val title = getString(
            if (trace.remote && trace.sources.isEmpty()) R.string.research_trace_remote_pending
            else R.string.research_trace_summary, trace.queries.size, trace.displayedSourceCount
        ) + if (trace.truncated) getString(R.string.research_trace_recorded_subset) else ""
        header.addView(TextView(this).apply {
            text = title
            textSize = 13f
            setTextColor(getColorCompat(R.color.text_secondary))
            includeFontPadding = false
        }, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(ImageView(this).apply {
            setImageResource(R.drawable.ic_chevron_down)
            imageTintList = android.content.res.ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
            rotation = if (expanded) 180f else 0f
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(18), dp(18)))
        header.contentDescription = title + ", " + getString(
            if (expanded) R.string.research_trace_collapse else R.string.research_trace_expand)
        header.setOnClickListener {
            expanded = !expanded
            agentResponseSectionExpansion[stateKey] = expanded
            while (agentResponseSectionExpansion.size > 200) {
                agentResponseSectionExpansion.remove(agentResponseSectionExpansion.keys.first())
            }
            render(current ?: trace)
        }
        container.addView(header)
        if (!expanded) return
        if (trace.queries.isNotEmpty()) container.addView(TextView(this).apply {
            text = trace.queries.joinToString("\n")
            textSize = 13f
            setTextColor(getColorCompat(R.color.text_secondary))
            setTextIsSelectable(true)
            setPadding(0, dp(6), 0, dp(8))
        })
        trace.sources.take(sourceLimit).forEachIndexed { index, source ->
            container.addView(TextView(this).apply {
                text = "${index + 1}. ${source.title.ifBlank { Uri.parse(source.url).host.orEmpty() }}"
                textSize = 14f
                setTextColor(getColorCompat(R.color.accent_green))
                setPadding(0, dp(8), 0, dp(8))
                minHeight = dp(44)
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                isFocusable = true
                contentDescription = text.toString() + ", " + Uri.parse(source.url).host
                setOnClickListener {
                    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(source.url))) }.onFailure {
                        Toast.makeText(this@agentResearchTraceRow, R.string.research_trace_open_failed, Toast.LENGTH_SHORT).show()
                    }
                }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            container.addView(TextView(this).apply {
                text = getString(when (source.status) {
                    "body_retrieved" -> R.string.research_trace_body
                    "open_reported" -> R.string.research_trace_open_reported
                    "unavailable" -> R.string.research_trace_unavailable
                    else -> R.string.research_trace_discovered
                }) + if (source.url in citedUrls)
                    " · " + getString(R.string.research_trace_cited) else ""
                textSize = 12f
                setTextColor(getColorCompat(R.color.text_secondary))
                setPadding(0, 0, 0, dp(6))
            })
        }
        if (trace.displayedSourceCount > sourceLimit) container.addView(TextView(this).apply {
            text = getString(R.string.research_trace_more, trace.displayedSourceCount - sourceLimit)
            textSize = 13f
            minHeight = dp(44)
            gravity = Gravity.CENTER_VERTICAL
            setTextColor(getColorCompat(R.color.accent_green))
            isFocusable = true
            setOnClickListener {
                sourceLimit += 50
                scope?.launch {
                    val next = withContext(Dispatchers.IO) {
                        AgentResearchTraceStore.read(applicationContext, entry.conversationId, entry.turnId, sourceLimit)
                    }
                    current = next
                    render(next)
                }
            }
        })
    }
    container.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) {
            scope?.cancel()
            scope = CoroutineScope(Dispatchers.Main.immediate + Job()).also { active ->
                active.launch {
                    AgentResearchTraceStore.revision.collectLatest {
                        val trace = withContext(Dispatchers.IO) {
                            AgentResearchTraceStore.read(applicationContext, entry.conversationId, entry.turnId, sourceLimit)
                        }
                        if (trace != current) { current = trace; render(trace) }
                    }
                }
            }
        }
        override fun onViewDetachedFromWindow(view: View) { scope?.cancel(); scope = null }
    })
    return container
}
