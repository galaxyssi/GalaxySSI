package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

internal sealed class ConversationHubRow {
    abstract val stableId: String

    data class Conversation(
        val item: ConversationHubItem
    ) : ConversationHubRow() {
        override val stableId: String = "conversation:${item.kind}:${item.id}"
    }

    data class Action(
        override val stableId: String,
        val title: String,
        val subtitle: String,
        val iconRes: Int,
        val trailing: String,
        val iconTint: Int,
        val iconBackground: Int,
        val action: ConversationHubAction
    ) : ConversationHubRow()

    data class Empty(
        val message: String
    ) : ConversationHubRow() {
        override val stableId: String = "empty:$message"
    }
}

internal enum class ConversationHubAction {
    SHOW_ACTIVE,
    SHOW_ARCHIVED
}

internal class ConversationHubListAdapter(
    private val createRowView: (ConversationHubRow) -> View
) : ListAdapter<ConversationHubRow, ConversationHubListAdapter.RowHolder>(DiffCallback) {
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RowHolder = RowHolder(
        FrameLayout(parent.context).apply {
            layoutParams = RecyclerView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
    )

    override fun onBindViewHolder(holder: RowHolder, position: Int) {
        holder.bind(createRowView(getItem(position)))
    }

    override fun onViewRecycled(holder: RowHolder) {
        holder.clear()
    }

    internal class RowHolder(
        private val container: FrameLayout
    ) : RecyclerView.ViewHolder(container) {
        fun bind(view: View) {
            container.removeAllViews()
            container.addView(
                view,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }

        fun clear() {
            container.removeAllViews()
        }
    }

    private companion object DiffCallback : DiffUtil.ItemCallback<ConversationHubRow>() {
        override fun areItemsTheSame(oldItem: ConversationHubRow, newItem: ConversationHubRow): Boolean =
            oldItem.stableId == newItem.stableId

        override fun areContentsTheSame(oldItem: ConversationHubRow, newItem: ConversationHubRow): Boolean =
            oldItem == newItem
    }
}
