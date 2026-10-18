package com.galaxyssi.chat.ui

import android.content.Context
import android.graphics.Rect
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
    private var blankTapPending = false
    private var longPressHandled = false
    private var paragraphSelectionPending = false
    private val expandParagraphSelection = Runnable {
        paragraphSelectionPending = false
        if (!isFocused || !hasSelection()) return@Runnable
        val range = ParagraphSelectionPolicy.rangeAt(text ?: return@Runnable, pendingAnchor)
        if (range.endExclusive > range.start) {
            setSelection(range.start, range.endExclusive)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_UP && blankTapPending &&
            !longPressHandled && event.eventTime - event.downTime < ViewConfiguration.getLongPressTimeout()) {
            // Native Editor opens insertion actions on the following UP. Do this before forwarding
            // that UP, rather than selecting a word or synthesizing another touch sequence.
            performLongClick()
        }
        val handled = super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pendingAnchor = getOffsetForPosition(event.x, event.y).coerceAtLeast(0)
                downX = event.x
                downY = event.y
                longPressHandled = false
                val onText = isTouchOnText(event.x, event.y)
                blankTapPending = isFocused && !onText
                paragraphSelectionPending = onText
                removeCallbacks(expandParagraphSelection)
                if (onText) {
                    postDelayed(
                        expandParagraphSelection,
                        ViewConfiguration.getLongPressTimeout().toLong() + SELECTION_HANDLE_SETTLE_MILLIS
                    )
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop) {
                    blankTapPending = false
                    cancelPendingParagraphSelection()
                }
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                blankTapPending = false
                cancelPendingParagraphSelection()
            }
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                blankTapPending = false
                if (paragraphSelectionPending) cancelPendingParagraphSelection()
            }
        }
        return handled
    }

    override fun performLongClick(): Boolean {
        longPressHandled = true
        return super.performLongClick()
    }

    private fun isTouchOnText(x: Float, y: Float): Boolean {
        val textLayout = layout ?: return false
        val localX = x - totalPaddingLeft + scrollX
        val localY = y - totalPaddingTop + scrollY
        if (localY < 0 || localY >= textLayout.height) return false
        val line = textLayout.getLineForVertical(localY.toInt())
        return localX >= textLayout.getLineLeft(line) && localX <= textLayout.getLineRight(line) &&
            textLayout.getLineLeft(line) < textLayout.getLineRight(line)
    }

    override fun onFocusChanged(focused: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        if (!focused) {
            blankTapPending = false
            cancelPendingParagraphSelection()
        }
        super.onFocusChanged(focused, direction, previouslyFocusedRect)
    }

    override fun onDetachedFromWindow() {
        blankTapPending = false
        cancelPendingParagraphSelection()
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
