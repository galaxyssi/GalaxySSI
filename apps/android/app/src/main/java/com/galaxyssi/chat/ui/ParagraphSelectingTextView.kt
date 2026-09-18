package com.galaxyssi.chat.ui

import android.content.Context
import android.text.Selection
import android.text.Spannable
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.TextView
import kotlin.math.abs

data class ParagraphDoubleTapSelection(
    val paragraph: String,
    val sourceText: String,
    val startOffset: Int
)

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
    /** Opt in where native double-tap word selection conflicts with paragraph playback. */
    var exclusiveParagraphDoubleTap = false
    private var consumingDoubleTap = false
    private var paragraphDoubleTapListener: ((ParagraphDoubleTapSelection) -> Unit)? = null
    private val doubleTapDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean = true

            override fun onDoubleTap(event: MotionEvent): Boolean {
                if (paragraphDoubleTapListener == null) return false
                doubleTapAnchor = getOffsetForPosition(event.x, event.y).coerceAtLeast(0)
                consumingDoubleTap = exclusiveParagraphDoubleTap
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

    fun setOnParagraphDoubleTapListener(listener: ((ParagraphDoubleTapSelection) -> Unit)?) {
        paragraphDoubleTapListener = listener
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val doubleTapHandled = paragraphDoubleTapListener != null &&
            doubleTapDetector.onTouchEvent(event)
        if (consumingDoubleTap) {
            cancelPendingParagraphSelection()
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x; downY = event.y
                    // Do not let Samsung's Editor start word selection on the second tap.
                    val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
                    super.onTouchEvent(cancel)
                    cancel.recycle()
                }
                MotionEvent.ACTION_MOVE -> if (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop) doubleTapAnchor = -1
                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_CANCEL -> doubleTapAnchor = -1
                MotionEvent.ACTION_UP -> dispatchParagraphDoubleTap()
            }
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) consumingDoubleTap = false
            return true
        }
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
                if (event.actionMasked == MotionEvent.ACTION_CANCEL) doubleTapAnchor = -1
                if (event.actionMasked == MotionEvent.ACTION_UP && doubleTapAnchor >= 0) {
                    dispatchParagraphDoubleTap()
                    return true
                }
            }
        }
        return handled || doubleTapHandled
    }

    private fun dispatchParagraphDoubleTap() {
        if (doubleTapAnchor < 0) return
        val range = ParagraphSelectionPolicy.rangeAt(text, doubleTapAnchor)
        doubleTapAnchor = -1
        val sourceText = text.toString()
        val rawParagraph = sourceText.substring(range.start, range.endExclusive)
        val paragraph = rawParagraph.trim()
        val leadingWhitespace = rawParagraph.indexOfFirst { !it.isWhitespace() }.takeIf { it >= 0 } ?: 0
        (text as? Spannable)?.let { Selection.removeSelection(it) }
        if (paragraph.isNotBlank()) paragraphDoubleTapListener?.invoke(
            ParagraphDoubleTapSelection(paragraph, sourceText, range.start + leadingWhitespace)
        )
    }

    override fun onDetachedFromWindow() {
        cancelPendingParagraphSelection()
        doubleTapAnchor = -1; consumingDoubleTap = false
        super.onDetachedFromWindow()
    }

    private fun cancelPendingParagraphSelection() {
        paragraphSelectionPending = false
        removeCallbacks(expandParagraphSelection)
    }

    private companion object {
        const val SELECTION_HANDLE_SETTLE_MILLIS = 32L
    }
}
