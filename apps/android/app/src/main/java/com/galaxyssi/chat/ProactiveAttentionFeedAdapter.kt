package com.galaxyssi.chat

import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView

internal data class AttentionReaderRow(val item: GlobalProactiveInboxItem, val expanded: Boolean, val saved: Boolean)

/** Read/bookmark payloads do not reconstruct expanded article bodies. */
internal class ProactiveAttentionFeedAdapter(private val create: () -> ProactiveAttentionArticleView) :
    RecyclerView.Adapter<ProactiveAttentionFeedAdapter.Holder>() {
    var rows = emptyList<AttentionReaderRow>()
        private set

    fun submit(next: List<AttentionReaderRow>) {
        val old = rows
        val changes = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize() = old.size
            override fun getNewListSize() = next.size
            override fun areItemsTheSame(a: Int, b: Int) = old[a].item.key == next[b].item.key
            override fun areContentsTheSame(a: Int, b: Int) = old[a] == next[b]
            override fun getChangePayload(a: Int, b: Int): Any? =
                if (old[a].expanded == next[b].expanded && old[a].item.content == next[b].item.content) "status" else null
        }, false)
        rows = next
        changes.dispatchUpdatesTo(this)
    }
    override fun getItemCount() = rows.size
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(create().apply {
        layoutParams = RecyclerView.LayoutParams(-1, -2)
    })
    override fun onBindViewHolder(holder: Holder, position: Int) = holder.view.bind(rows[position])
    override fun onBindViewHolder(holder: Holder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isNotEmpty()) holder.view.updateStatus(rows[position]) else onBindViewHolder(holder, position)
    }
    class Holder(val view: ProactiveAttentionArticleView) : RecyclerView.ViewHolder(view)
}
