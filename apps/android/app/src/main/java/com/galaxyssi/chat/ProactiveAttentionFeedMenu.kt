package com.galaxyssi.chat

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView

internal class ProactiveAttentionFeedMenu(
    private val context: Context,
    selected: AttentionFeedFilter,
    select: (AttentionFeedFilter) -> Unit,
    settings: () -> Unit,
    dismissed: () -> Unit
) {
    val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, dp(4), 0, dp(4))
    }
    private val popup = PopupWindow(context)

    init {
        listOf(
            Triple(AttentionFeedFilter.ALL, R.string.attention_menu_all, R.drawable.ic_attention_all),
            Triple(AttentionFeedFilter.UNREAD, R.string.attention_menu_unread, R.drawable.ic_attention_unread),
            Triple(AttentionFeedFilter.SAVED, R.string.attention_menu_saved, R.drawable.ic_attention_bookmark)
        ).forEach { (filter, label, icon) ->
            content.addView(row(filter.name, label, icon, selected == filter) { select(filter) })
        }
        content.addView(View(context).apply { setBackgroundColor(context.getColor(R.color.separator)) },
            LinearLayout.LayoutParams(-1, dp(1)).apply { marginStart = dp(16); marginEnd = dp(16); topMargin = dp(4); bottomMargin = dp(4) })
        content.addView(row("SETTINGS", R.string.attention_title, R.drawable.ic_tab_settings, false, settings))
        popup.contentView = ScrollView(context).apply { isVerticalScrollBarEnabled = false; addView(content) }
        popup.height = LinearLayout.LayoutParams.WRAP_CONTENT
        popup.isFocusable = true; popup.isOutsideTouchable = true
        popup.inputMethodMode = PopupWindow.INPUT_METHOD_NOT_NEEDED
        popup.setBackgroundDrawable(GradientDrawable().apply {
            cornerRadius = dp(8).toFloat(); setColor(context.getColor(R.color.surface_bg))
        })
        popup.elevation = dp(8).toFloat()
        popup.setOnDismissListener { dismissed() }
    }

    fun show(anchor: View) {
        val frame = android.graphics.Rect().also(anchor::getWindowVisibleDisplayFrame)
        val labelWidth = (0 until content.childCount).mapNotNull { content.getChildAt(it) as? LinearLayout }
            .map { it.getChildAt(1) as TextView }.maxOf { it.paint.measureText(it.text.toString()).toInt() }
        popup.width = maxOf(dp(216), labelWidth + dp(100)).coerceAtMost((frame.width() - dp(16)).coerceAtLeast(1))
        popup.showAsDropDown(anchor, -dp(8), dp(2), Gravity.END)
    }

    fun dismiss() = popup.dismiss()

    private fun row(key: String, label: Int, drawable: Int, checked: Boolean, click: () -> Unit) = LinearLayout(context).apply {
        tag = "attention-menu:$key"; orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(48); setPadding(dp(16), dp(10), dp(16), dp(10))
        isFocusable = true; isSelected = checked; contentDescription = context.getString(label)
        val attributes = context.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground))
        background = attributes.getDrawable(0); attributes.recycle()
        addView(image(drawable), LinearLayout.LayoutParams(dp(22), dp(22)))
        addView(TextView(context).apply {
            text = context.getString(label); textSize = 15f
            setTextColor(context.getColor(R.color.text_primary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(12); marginEnd = dp(12) })
        addView(image(R.drawable.ic_attention_check).apply {
            tag = "attention-menu-check:$key"
            imageTintList = ColorStateList.valueOf(context.getColor(R.color.galaxyssi_green))
            visibility = if (checked) View.VISIBLE else View.INVISIBLE
        }, LinearLayout.LayoutParams(dp(20), dp(20)))
        setOnClickListener { dismiss(); click() }
    }

    private fun image(drawable: Int) = ImageView(context).apply {
        setImageResource(drawable); imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_primary))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
}
