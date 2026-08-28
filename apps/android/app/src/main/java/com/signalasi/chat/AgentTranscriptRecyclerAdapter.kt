package com.signalasi.chat

import android.os.SystemClock
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView

internal class AgentTranscriptRecyclerAdapter(
    private val activity: MainActivity
) : RecyclerView.Adapter<AgentTranscriptViewHolder>() {
    private val entries = mutableListOf<AgentTranscriptEntry>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): AgentTranscriptViewHolder =
        AgentTranscriptViewHolder(
            FrameLayout(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    bottomMargin = activity.dp(10)
                }
                isSaveEnabled = false
            }
        )

    override fun onBindViewHolder(holder: AgentTranscriptViewHolder, position: Int) {
        val bindStartedAt = SystemClock.elapsedRealtime()
        val entry = entries[position]
        holder.container.removeAllViews()
        holder.container.addView(
            activity.agentTranscriptRow(entry),
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        val elapsed = SystemClock.elapsedRealtime() - bindStartedAt
        if (elapsed >= AGENT_TRANSCRIPT_PERF_LOG_THRESHOLD_MS) {
            Log.d(
                "SignalASIPerf",
                "transcript_bind role=${entry.role} id=${entry.id.take(12)} " +
                    "rich=${entry.richOutputJson.length} elapsed_ms=$elapsed"
            )
        }
    }

    override fun onViewRecycled(holder: AgentTranscriptViewHolder) {
        holder.container.removeAllViews()
        super.onViewRecycled(holder)
    }

    override fun getItemCount(): Int = entries.size

    fun replaceAll(replacement: List<AgentTranscriptEntry>) {
        entries.clear()
        entries.addAll(replacement.filterNot(::isControlPayload))
        notifyDataSetChanged()
    }

    fun replaceAt(index: Int, entry: AgentTranscriptEntry) {
        if (isControlPayload(entry)) {
            entries.removeAt(index)
            notifyItemRemoved(index)
            return
        }
        entries[index] = entry
        notifyItemChanged(index)
    }

    fun append(appended: List<AgentTranscriptEntry>) {
        val visibleEntries = appended.filterNot(::isControlPayload)
        if (visibleEntries.isEmpty()) return
        val start = entries.size
        entries.addAll(visibleEntries)
        notifyItemRangeInserted(start, visibleEntries.size)
    }

    fun syncBackingEntries(replacement: List<AgentTranscriptEntry>) {
        val visibleEntries = replacement.filterNot(::isControlPayload)
        if (visibleEntries.size != entries.size) return
        visibleEntries.forEachIndexed { index, entry -> entries[index] = entry }
    }

    fun clear() {
        if (entries.isEmpty()) return
        val count = entries.size
        entries.clear()
        notifyItemRangeRemoved(0, count)
    }

    fun entryIdAt(position: Int): String? = entries.getOrNull(position)?.id

    fun indexOfEntry(entryId: String): Int = entries.indexOfFirst { it.id == entryId }

    private fun isControlPayload(entry: AgentTranscriptEntry): Boolean =
        AgentSupervisedProjectControlPayload.isTranscriptControlPayload(
            entry.text,
            entry.richOutputJson
        )
}
