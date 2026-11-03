package com.galaxyssi.chat

import android.content.Context
import android.view.View
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.galaxyssi.chat.ui.ParagraphSelectingTextView

internal class AgentTranscriptLayoutManager(context: Context) : LinearLayoutManager(context) {
    override fun onRequestChildFocus(parent: RecyclerView, state: RecyclerView.State, child: View, focused: View?): Boolean =
        // A selectable paragraph may be taller than the viewport. Focus must not reveal its top.
        focused is ParagraphSelectingTextView || super.onRequestChildFocus(parent, state, child, focused)
}
