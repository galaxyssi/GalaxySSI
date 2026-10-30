package com.galaxyssi.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.text.TextUtils
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.view.textclassifier.TextClassifier
import android.widget.TextView
import androidx.core.view.doOnLayout

/** Copy, native selection and article feedback share one anchored menu. */
internal class AttentionHeadlineView(context: Context, private val openArticle: () -> Unit,
    private val feedback: (AttentionHeadlineAction) -> Unit) : TextView(context) {
    private var popup: AttentionHeadlineMenu? = null
    private var selectionMode: ActionMode? = null
    private var selecting = false
    private var pendingHeadline: String? = null
    private var originalLines = 2
    private var originalEllipsize: TextUtils.TruncateAt? = null
    private var originalHeight = ViewGroup.LayoutParams.WRAP_CONTENT
    private val finishSelection = Runnable { endSelection() }

    init {
        // Select exact title ranges without async smart-selection callbacks outliving recycled rows.
        setTextClassifier(TextClassifier.NO_OP)
        setOnClickListener { if (!selecting) openArticle() }
        setOnLongClickListener {
            if (selecting) false else {
                showHeadlineActions()
                true
            }
        }
        customSelectionActionModeCallback = object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                if (!selecting || !isAttachedToWindow) return false
                selectionMode = mode
                return true
            }
            override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
            override fun onActionItemClicked(mode: ActionMode, item: MenuItem) = false
            override fun onDestroyActionMode(mode: ActionMode) {
                selectionMode = null
                post(finishSelection)
            }
        }
    }

    fun updateHeadline(value: String) {
        // Read receipts and late translations must not replace text under selection handles.
        if (selecting || popup != null) pendingHeadline = value
        else if (text.toString() != value) text = value
    }

    fun showHeadlineActions() {
        if (text.isEmpty() || !isAttachedToWindow || popup != null) return
        popup = AttentionHeadlineMenu(context, action = { action ->
            when (action) {
                AttentionHeadlineAction.COPY -> context.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText(null, text.toString()))
                AttentionHeadlineAction.SELECT -> beginSelection()
                else -> feedback(action)
            }
        }, dismissed = {
            popup = null
            applyPendingHeadline()
        }).also { it.show(this) }
    }

    private fun beginSelection() {
        if (selecting || text.isEmpty()) return
        removeCallbacks(finishSelection)
        selecting = true
        originalLines = maxLines
        originalEllipsize = ellipsize
        originalHeight = layoutParams.height
        maxLines = Int.MAX_VALUE
        ellipsize = null
        layoutParams = layoutParams.apply { height = ViewGroup.LayoutParams.WRAP_CONTENT }
        setTextIsSelectable(true)
        requestFocus()
        doOnLayout {
            if (selecting && isAttachedToWindow) {
                // This public TextView action starts native selection, including both handles.
                val started = performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, Bundle().apply {
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, text.length)
                })
                if (!started) endSelection()
            }
        }
    }

    private fun endSelection() {
        removeCallbacks(finishSelection)
        if (!selecting) return
        selecting = false
        val mode = selectionMode
        selectionMode = null
        mode?.finish()
        setTextIsSelectable(false)
        clearFocus()
        maxLines = originalLines
        ellipsize = originalEllipsize
        layoutParams = layoutParams.apply { height = originalHeight }
        // TextView changes these flags when selectable text is disabled.
        isClickable = true
        isLongClickable = true
        applyPendingHeadline()
    }

    private fun applyPendingHeadline() {
        if (selecting || popup != null) return
        val value = pendingHeadline ?: return
        pendingHeadline = null
        updateHeadline(value)
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility != VISIBLE) {
            popup?.dismiss()
            endSelection()
        }
    }

    override fun onDetachedFromWindow() {
        popup?.dismiss()
        endSelection()
        super.onDetachedFromWindow()
        removeCallbacks(finishSelection)
    }
}
