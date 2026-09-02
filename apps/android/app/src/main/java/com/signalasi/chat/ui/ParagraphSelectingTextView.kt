package com.signalasi.chat.ui

import android.content.Context
import android.text.Selection
import android.text.Spannable
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.TextView
import kotlin.math.abs

class ParagraphSelectingTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = android.R.attr.textViewStyle
) : TextView(context, attrs, defStyleAttr) {
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
    private var pendingAnchor = 0
    private var downX = 0f
    private var downY = 0f
    private var paragraphSelectionPending = false
    private var doubleTapAnchor = -1
    private var paragraphDoubleTapListener: ((String) -> Unit)? = null
    private val doubleTapDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean = true

            override fun onDoubleTap(event: MotionEvent): Boolean {
                if (paragraphDoubleTapListener == null) return false
                doubleTapAnchor = getOffsetForPosition(event.x, event.y).coerceAtLeast(0)
                return true
            }
        }
    )
    private val expandParagraphSelection = Runnable {
        paragraphSelectionPending = false
        val selectableText = text as? Spannable ?: return@Runnable
        val range = ParagraphSelectionPolicy.rangeAt(selectableText, pendingAnchor)
        if (range.endExclusive > range.start) {
            requestFocus()
            Selection.setSelection(selectableText, range.start, range.endExclusive)
        }
    }

    init {
        setTextIsSelectable(true)
    }

    fun setOnParagraphDoubleTapListener(listener: ((String) -> Unit)?) {
        paragraphDoubleTapListener = listener
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val doubleTapHandled = paragraphDoubleTapListener != null &&
            doubleTapDetector.onTouchEvent(event)
        val handled = super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pendingAnchor = getOffsetForPosition(event.x, event.y).coerceAtLeast(0)
                downX = event.x
                downY = event.y
                paragraphSelectionPending = true
                removeCallbacks(expandParagraphSelection)
                postDelayed(
                    expandParagraphSelection,
                    ViewConfiguration.getLongPressTimeout().toLong() + SELECTION_HANDLE_SETTLE_MILLIS
                )
            }
            MotionEvent.ACTION_MOVE -> {
                if (paragraphSelectionPending &&
                    (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop)
                ) {
                    cancelPendingParagraphSelection()
                }
            }
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                if (paragraphSelectionPending) cancelPendingParagraphSelection()
                if (event.actionMasked == MotionEvent.ACTION_UP && doubleTapAnchor >= 0) {
                    val selectableText = text as? Spannable
                    val range = ParagraphSelectionPolicy.rangeAt(text, doubleTapAnchor)
                    val paragraph = text.subSequence(range.start, range.endExclusive).toString().trim()
                    doubleTapAnchor = -1
                    if (selectableText != null) Selection.removeSelection(selectableText)
                    if (paragraph.isNotBlank()) paragraphDoubleTapListener?.invoke(paragraph)
                    return true
                }
            }
        }
        return handled || doubleTapHandled
    }

    private fun cancelPendingParagraphSelection() {
        paragraphSelectionPending = false
        removeCallbacks(expandParagraphSelection)
    }

    private companion object {
        const val SELECTION_HANDLE_SETTLE_MILLIS = 32L
    }
}
