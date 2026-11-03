package com.galaxyssi.chat

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.RelativeLayout
import android.widget.TextView

internal class ProactiveAttentionHeader(
    context: Context,
    back: () -> Unit,
    more: () -> Unit
) : RelativeLayout(context) {
    val title = TextView(context).apply {
        id = View.generateViewId(); tag = "attention-page-title"
        textSize = 18f; setTypeface(null, Typeface.BOLD)
        setTextColor(context.getColor(R.color.text_primary))
        gravity = Gravity.CENTER; maxLines = 1; ellipsize = TextUtils.TruncateAt.END
    }
    val unread = TextView(context).apply {
        tag = "attention-header-unread"; textSize = 12f
        setTextColor(context.getColor(R.color.text_secondary))
        gravity = Gravity.START or Gravity.CENTER_VERTICAL
        maxLines = 1; ellipsize = TextUtils.TruncateAt.END
    }
    val action = icon(R.drawable.ic_attention_more, R.string.attention_feed_menu, more).apply {
        id = View.generateViewId(); tag = "attention-feed-menu"
        setPadding(dp(14), dp(14), dp(14), dp(14))
    }

    init {
        setBackgroundColor(context.getColor(R.color.surface_bg))
        addView(icon(R.drawable.ic_navigation_back, android.R.string.cancel, back),
            LayoutParams(dp(48), dp(48)).apply { addRule(ALIGN_PARENT_START); addRule(CENTER_VERTICAL) })
        addView(action, LayoutParams(dp(48), dp(48)).apply { addRule(ALIGN_PARENT_END); addRule(CENTER_VERTICAL) })
        addView(title, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT).apply { addRule(CENTER_IN_PARENT) })
        addView(unread, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            addRule(END_OF, title.id); addRule(START_OF, action.id); addRule(CENTER_VERTICAL)
            marginStart = dp(8); marginEnd = dp(4)
        })
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // Only the title determines its center. Counts must never move it toward the back button.
        val maxTitleWidth = (View.MeasureSpec.getSize(widthMeasureSpec) - dp(112)).coerceAtLeast(0)
        if (title.maxWidth != maxTitleWidth) title.maxWidth = maxTitleWidth
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (unread.visibility == View.GONE) return
        if (layoutDirection == View.LAYOUT_DIRECTION_RTL) {
            val start = action.right + dp(4)
            unread.layout(start, unread.top, (title.left - dp(8)).coerceAtLeast(start), unread.bottom)
        } else {
            val end = action.left - dp(4)
            unread.layout((title.right + dp(8)).coerceAtMost(end), unread.top, end, unread.bottom)
        }
    }

    fun render(settings: Boolean, count: Int?) {
        val color = context.getColor(if (settings) R.color.surface_bg else R.color.page_bg)
        if ((background as? ColorDrawable)?.color != color) setBackgroundColor(color)
        val label = context.getString(if (settings) R.string.attention_title else R.string.attention_discoveries)
        if (title.text.toString() != label) title.text = label
        unread.visibility = if (!settings && count != null && count > 0) View.VISIBLE else View.GONE
        val countLabel = count?.takeIf { it > 0 }?.let { context.getString(R.string.attention_header_unread, it) }.orEmpty()
        if (unread.text.toString() != countLabel) unread.text = countLabel
        unread.contentDescription = unread.text; unread.tooltipText = unread.text
        title.contentDescription = if (unread.visibility == View.VISIBLE) "${title.text}, ${unread.text}" else title.text
        action.setImageResource(if (settings) android.R.drawable.ic_input_add else R.drawable.ic_attention_more)
        action.contentDescription = context.getString(if (settings) R.string.attention_add else R.string.attention_feed_menu)
        action.tooltipText = action.contentDescription
    }

    private fun icon(drawable: Int, label: Int, click: () -> Unit) = ImageButton(context).apply {
        setImageResource(drawable); contentDescription = context.getString(label); tooltipText = contentDescription
        imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_primary))
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        setPadding(dp(12), dp(12), dp(12), dp(12)); setOnClickListener { click() }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
