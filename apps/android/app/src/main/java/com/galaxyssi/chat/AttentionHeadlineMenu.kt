package com.galaxyssi.chat

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.TextView

internal enum class AttentionHeadlineAction { COPY, SELECT, READ, NOT_RELEVANT }

internal class AttentionHeadlineMenu(
    private val context: Context,
    action: (AttentionHeadlineAction) -> Unit,
    dismissed: () -> Unit
) {
    private val popup = PopupWindow(context)
    private val labels = mutableListOf<TextView>()
    private val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(4), dp(4), dp(4), dp(4))
    }

    init {
        fun row(vararg entries: Triple<AttentionHeadlineAction, Int, Int>) {
            content.addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                entries.forEach { (key, label, icon) ->
                    addView(button(key, label, icon) {
                        // Selection must freeze the title before dismiss applies queued translations.
                        action(key)
                        dismiss()
                    }, LinearLayout.LayoutParams(0, -1, 1f))
                }
            }, LinearLayout.LayoutParams(-1, -2))
        }
        row(Triple(AttentionHeadlineAction.COPY, R.string.common_copy, R.drawable.ic_rich_copy),
            Triple(AttentionHeadlineAction.SELECT, R.string.common_select, R.drawable.ic_attention_select))
        content.addView(View(context).apply { setBackgroundColor(context.getColor(R.color.separator)) },
            LinearLayout.LayoutParams(-1, dp(1)).apply { marginStart = dp(10); marginEnd = dp(10) })
        row(Triple(AttentionHeadlineAction.READ, R.string.attention_read, R.drawable.ic_attention_check),
            Triple(AttentionHeadlineAction.NOT_RELEVANT, R.string.agent_global_feedback_not_relevant, R.drawable.ic_agent_progress_close))
        popup.contentView = content
        popup.height = LinearLayout.LayoutParams.WRAP_CONTENT
        popup.isFocusable = true
        popup.isOutsideTouchable = true
        popup.inputMethodMode = PopupWindow.INPUT_METHOD_NOT_NEEDED
        popup.setBackgroundDrawable(GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(context.getColor(R.color.surface_bg))
        })
        popup.elevation = dp(8).toFloat()
        popup.setOnDismissListener { dismissed() }
    }

    fun show(anchor: View) {
        val frame = Rect().also(anchor::getWindowVisibleDisplayFrame)
        val labelWidth = labels.maxOf { it.paint.measureText(it.text.toString()).toInt() }
        popup.width = maxOf(dp(272), (labelWidth + dp(52)) * 2 + dp(8))
            .coerceAtMost((frame.width() - dp(24)).coerceAtLeast(1))
        popup.showAsDropDown(anchor, 0, dp(4), Gravity.START)
    }

    fun dismiss() = popup.dismiss()

    private fun button(key: AttentionHeadlineAction, label: Int, drawable: Int, click: () -> Unit) =
        LinearLayout(context).apply {
            tag = "attention-headline-action:$key"
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(56)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            isFocusable = true
            contentDescription = context.getString(label)
            val attributes = context.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground))
            background = attributes.getDrawable(0)
            attributes.recycle()
            addView(ImageView(context).apply {
                setImageResource(drawable)
                imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_primary))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(20), dp(20)))
            addView(TextView(context).apply {
                text = context.getString(label)
                textSize = 14f
                setTextColor(context.getColor(R.color.text_primary))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                labels += this
            }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(8) })
            setOnClickListener { click() }
        }

    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
}
