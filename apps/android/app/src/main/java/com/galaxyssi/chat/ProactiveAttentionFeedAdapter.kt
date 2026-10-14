package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.recyclerview.widget.RecyclerView

/** Recycles visible rows; the number of retained findings does not determine the view count. */
internal class ProactiveAttentionFeedAdapter(
    private val header: () -> View,
    private val article: (GlobalProactiveInboxItem) -> View,
    private val footer: (Boolean) -> View
) : RecyclerView.Adapter<ProactiveAttentionFeedAdapter.Holder>() {
    var items: List<GlobalProactiveInboxItem> = emptyList()
        private set

    fun submit(next: List<GlobalProactiveInboxItem>) {
        items = next
        notifyDataSetChanged()
    }

    override fun getItemCount() = items.size + 2
    override fun getItemViewType(position: Int) = when (position) { 0 -> 0; itemCount - 1 -> 2; else -> 1 }
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(LinearLayout(parent.context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = RecyclerView.LayoutParams(-1, -2)
    })
    override fun onBindViewHolder(holder: Holder, position: Int) {
        holder.container.removeAllViews()
        holder.container.addView(when (getItemViewType(position)) {
            0 -> header()
            2 -> footer(items.isEmpty())
            else -> article(items[position - 1])
        })
    }

    class Holder(val container: LinearLayout) : RecyclerView.ViewHolder(container)
}
