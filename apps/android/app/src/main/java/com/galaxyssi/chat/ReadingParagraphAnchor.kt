package com.galaxyssi.chat

import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import androidx.recyclerview.widget.RecyclerView
import com.galaxyssi.chat.ui.ParagraphSelectingTextView

/** A WebView can resize inside a single stable message without an adapter update. */
internal class ReadingParagraphAnchor(private val list: RecyclerView, private val holding: () -> Boolean) :
    ViewTreeObserver.OnPreDrawListener, View.OnAttachStateChangeListener {
    private var paragraph: View? = null
    private var row: View? = null
    private var offset = 0
    private val bounds = Rect()

    fun install() {
        list.addOnAttachStateChangeListener(this)
        if (list.isAttachedToWindow) onViewAttachedToWindow(list)
    }
    override fun onViewAttachedToWindow(v: View) { list.viewTreeObserver.addOnPreDrawListener(this) }
    override fun onViewDetachedFromWindow(v: View) {
        if (list.viewTreeObserver.isAlive) list.viewTreeObserver.removeOnPreDrawListener(this)
        paragraph = null; row = null
    }
    private fun visibleText(view: View): View? {
        if (view.visibility != View.VISIBLE || !view.getGlobalVisibleRect(bounds)) return null
        if (view is ParagraphSelectingTextView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) visibleText(view.getChildAt(i))?.let { return it }
        return null
    }
    private fun relative(group: ViewGroup, target: View): Int {
        bounds.setEmpty()
        group.offsetDescendantRectToMyCoords(target, bounds)
        return bounds.top
    }
    override fun onPreDraw(): Boolean {
        if (!holding() || !list.isShown || list.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
            paragraph = null; row = null; return true
        }
        val target = paragraph
        val holder = row as? ViewGroup
        if (target != null && holder != null && holder.parent === list && list.findContainingItemView(target) === holder) {
            val next = relative(holder, target)
            val delta = next - offset
            offset = next
            if (delta != 0 && !list.isComputingLayout) list.scrollBy(0, delta)
            if (target.getGlobalVisibleRect(bounds)) return true
        }
        paragraph = null; row = null
        for (i in 0 until list.childCount) {
            val item = list.getChildAt(i) as? ViewGroup ?: continue
            val text = visibleText(item) ?: continue
            row = item; paragraph = text; offset = relative(item, text); break
        }
        return true
    }
}
