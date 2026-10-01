package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

internal class CollaborationTranscriptRecyclerAdapter(private val host: MainActivity) : AgentTranscriptRecyclerAdapter(host) {
    override fun createRow(entry: AgentTranscriptEntry): View {
        CollaborationTranscriptMetadata.decode(entry.collaborationJson)?.let { return host.collaborationTranscriptRow(entry, it) }
        if (entry.role == AgentTranscriptRole.USER) return host.agentUserTranscriptRow(entry)
        return LinearLayout(host).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(host).apply {
                setText(R.string.collaboration_system_message)
                textSize = 12f
                setTextColor(host.getColorCompat(R.color.text_secondary))
            })
            // Keep errors and permission requests accessible without a global process/timer row.
            addView(host.agentAssistantTranscriptRow(entry.copy(role = AgentTranscriptRole.ASSISTANT)))
        }
    }
}

internal fun MainActivity.selectConversationOutputPage(collaboration: Boolean) {
    val target = findViewById<RecyclerView>(if (collaboration) R.id.collaborationOutputList else R.id.agentOutputList)
    val previous = agentOutputList
    findViewById<View>(R.id.agentOutputList).visibility = if (collaboration) View.GONE else View.VISIBLE
    findViewById<View>(R.id.collaborationOutputList).visibility = if (collaboration) View.VISIBLE else View.GONE
    agentOutputList = target
    agentOutputLayout = target.layoutManager as LinearLayoutManager
    agentTranscriptAdapter = if (collaboration) collaborationTranscriptAdapter else singleAgentTranscriptAdapter
    if (target !== previous) {
        dismissAgentPlanProgressOverlay()
        renderedAgentTranscriptIds.clear()
        renderedAgentTranscriptSignatures.clear()
        renderedAgentTranscriptSourceEntries = emptyList()
    }
}
