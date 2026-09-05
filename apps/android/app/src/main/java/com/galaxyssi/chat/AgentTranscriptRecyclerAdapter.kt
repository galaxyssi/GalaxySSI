package com.galaxyssi.chat

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
        observeDraw(holder, entry)
        val elapsed = SystemClock.elapsedRealtime() - bindStartedAt
        if (elapsed >= AGENT_TRANSCRIPT_PERF_LOG_THRESHOLD_MS) {
            Log.d(
                "GalaxySSIPerf",
                "transcript_bind role=${entry.role} id=${entry.id.take(12)} " +
                    "rich=${entry.richOutputJson.length} elapsed_ms=$elapsed"
            )
        }
    }

    override fun onViewRecycled(holder: AgentTranscriptViewHolder) {
        holder.latencyDrawCleanup?.invoke()
        holder.latencyDrawCleanup = null
        holder.container.removeAllViews()
        super.onViewRecycled(holder)
    }

    override fun onViewAttachedToWindow(holder: AgentTranscriptViewHolder) {
        super.onViewAttachedToWindow(holder)
        entries.getOrNull(holder.adapterPosition)?.let { observeDraw(holder, it) }
    }

    override fun onViewDetachedFromWindow(holder: AgentTranscriptViewHolder) {
        holder.latencyDrawCleanup?.invoke()
        holder.latencyDrawCleanup = null
        super.onViewDetachedFromWindow(holder)
    }

    private fun observeDraw(holder: AgentTranscriptViewHolder, entry: AgentTranscriptEntry) {
        holder.latencyDrawCleanup?.invoke()
        holder.latencyDrawCleanup = if (holder.container.isAttachedToWindow &&
            entry.role == AgentTranscriptRole.ASSISTANT && entry.text.isNotBlank()
        ) com.galaxyssi.chat.metrics.AgentLatencyTelemetry.observeDraw(
            holder.container, entry.taskId, final = !entry.id.startsWith("agent-stream-")
        ) else null
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
        if (!changed) {
            // Identical final text keeps its existing View, but its live/final identity changes.
            syncBackingEntries(visibleEntries)
            observeAttachedReplies()
            return false
        }

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
        observeAttachedReplies()
        return true
    }

    private fun observeAttachedReplies() {
        val list = activity.agentOutputList
        list.post {
            for (index in 0 until list.childCount) {
                val holder = list.getChildViewHolder(list.getChildAt(index)) as? AgentTranscriptViewHolder ?: continue
                entries.getOrNull(holder.adapterPosition)?.let { observeDraw(holder, it) }
            }
        }
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
