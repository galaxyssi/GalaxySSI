package com.signalasi.chat

import android.os.SystemClock
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView

internal class AgentTranscriptRecyclerAdapter(
    private val activity: MainActivity
) : RecyclerView.Adapter<AgentTranscriptViewHolder>() {
    private val entries = mutableListOf<AgentTranscriptEntry>()

    init {
        setHasStableIds(true)
    }

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

    override fun getItemId(position: Int): Long = stableItemId(
        AgentTranscriptRenderPolicy.identity(entries[position])
    )

    fun replaceAll(
        replacement: List<AgentTranscriptEntry>,
        forcedChangedIdentities: Set<String> = emptySet()
    ): Boolean {
        val visibleEntries = replacement.filterNot(::isControlPayload)
        val previousEntries = entries.toList()
        val changed = previousEntries.size != visibleEntries.size ||
            previousEntries.indices.any { index ->
                val previous = previousEntries[index]
                val current = visibleEntries[index]
                !AgentTranscriptRenderPolicy.sameItem(previous, current) ||
                    !AgentTranscriptRenderPolicy.sameContent(previous, current) ||
                    AgentTranscriptRenderPolicy.identity(current) in forcedChangedIdentities
            }
        if (!changed) return false

        val diff = DiffUtil.calculateDiff(
            object : DiffUtil.Callback() {
                override fun getOldListSize(): Int = previousEntries.size

                override fun getNewListSize(): Int = visibleEntries.size

                override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean =
                    AgentTranscriptRenderPolicy.sameItem(
                        previousEntries[oldItemPosition],
                        visibleEntries[newItemPosition]
                    )

                override fun areContentsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean =
                    AgentTranscriptRenderPolicy.identity(visibleEntries[newItemPosition]) !in
                        forcedChangedIdentities &&
                        AgentTranscriptRenderPolicy.sameContent(
                            previousEntries[oldItemPosition],
                            visibleEntries[newItemPosition]
                        )
            },
            true
        )
        entries.clear()
        entries.addAll(visibleEntries)
        diff.dispatchUpdatesTo(this)
        return true
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

    private fun stableItemId(identity: String): Long {
        var hash = FNV_OFFSET_BASIS
        identity.forEach { character ->
            hash = hash xor character.code.toLong()
            hash *= FNV_PRIME
        }
        return if (hash == RecyclerView.NO_ID) Long.MIN_VALUE else hash
    }

    private companion object {
        const val FNV_OFFSET_BASIS = -3750763034362895579L
        const val FNV_PRIME = 1099511628211L
    }
}
