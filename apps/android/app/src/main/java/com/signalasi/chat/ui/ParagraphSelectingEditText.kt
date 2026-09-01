package com.signalasi.chat.ui

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.EditText
import kotlin.math.abs

internal data class ParagraphTextRange(
    val start: Int,
    val endExclusive: Int
)

internal object ParagraphSelectionPolicy {
    fun rangeAt(text: CharSequence, requestedOffset: Int): ParagraphTextRange {
        if (text.isEmpty()) return ParagraphTextRange(0, 0)

        var anchor = requestedOffset.coerceIn(0, text.length)
        if (anchor == text.length) anchor--
        if (text[anchor] == '\n' && anchor > 0) anchor--

        val start = (anchor downTo 0)
            .firstOrNull { text[it] == '\n' }
            ?.plus(1)
            ?: 0
        var end = (anchor until text.length)
            .firstOrNull { text[it] == '\n' }
            ?: text.length
        if (end > start && text[end - 1] == '\r') end--
        return ParagraphTextRange(start, end.coerceAtLeast(start))
    }
}

class ParagraphSelectingEditText @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = android.R.attr.editTextStyle
) : EditText(context, attrs, defStyleAttr) {
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
    private var pendingAnchor = 0
    private var downX = 0f
    private var downY = 0f
    private var paragraphSelectionPending = false
    private val expandParagraphSelection = Runnable {
        paragraphSelectionPending = false
        if (!isFocused) return@Runnable
        val range = ParagraphSelectionPolicy.rangeAt(text ?: return@Runnable, pendingAnchor)
        if (range.endExclusive > range.start) {
            setSelection(range.start, range.endExclusive)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
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
            }
        }
        return handled
    }

    private fun cancelPendingParagraphSelection() {
        paragraphSelectionPending = false
        removeCallbacks(expandParagraphSelection)
    }

    private companion object {
        const val SELECTION_HANDLE_SETTLE_MILLIS = 32L
    }
}
