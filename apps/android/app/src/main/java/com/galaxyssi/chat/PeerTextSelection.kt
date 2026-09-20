package com.galaxyssi.chat

import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.widget.TextView

internal fun TextView.attachPeerTextSelectionActions(onActions: (() -> Unit)?) {
    setOnLongClickListener(null)
    setTextIsSelectable(true)
    customSelectionActionModeCallback = object : ActionMode.Callback {
        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
            if (onActions != null) menu.add(0, R.id.peer_selection_more, 100, R.string.common_more)
            return true
        }

        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean = false

        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            if (item.itemId != R.id.peer_selection_more) return false
            mode.finish()
            onActions?.invoke()
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) = Unit
    }
}
