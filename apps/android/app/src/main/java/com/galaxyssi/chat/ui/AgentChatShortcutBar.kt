package com.galaxyssi.chat.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.galaxyssi.chat.R
import kotlin.math.roundToInt

/** Inline actions remain reachable at large accessibility font sizes without shrinking text. */
class AgentChatShortcutBar @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : HorizontalScrollView(context, attrs) {
    private val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
    private val actions = mutableListOf<FrameLayout>()
    private val contents = mutableListOf<LinearLayout>()
    private val unreadDots = mutableMapOf<Int, View>()

    init {
        isHorizontalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_NEVER
        isFillViewport = false
        addView(row, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addAction(R.id.agentInsightBar, R.string.chat_shortcut_feed,
            R.string.attention_discoveries, R.drawable.ic_chat_shortcut_feed, R.id.agentInsightUnreadDot)
        addAction(R.id.agentActionNewSession, R.string.chat_shortcut_new,
            R.string.agent_session_new, R.drawable.ic_hub_compose)
        addAction(R.id.agentActionSessions, R.string.chat_shortcut_sessions,
            R.string.agent_sessions_title, R.drawable.ic_chat_shortcut_list, R.id.agentSessionsUnreadDot)
        addAction(R.id.agentActionCamera, R.string.chat_shortcut_camera,
            R.string.agent_attachment_take_photo, R.drawable.ic_agent_camera)
        addAction(R.id.agentActionAddFile, R.string.chat_shortcut_file,
            R.string.agent_attachment_add_file, R.drawable.ic_chat_shortcut_file)
    }

    fun showFeedUnread(count: Int) {
        setUnread(R.id.agentInsightBar, count > 0,
            if (count > 0) context.getString(R.string.attention_unread_entry, count)
            else context.getString(R.string.attention_discoveries))
    }

    fun showSessionsUnread(unread: Boolean) {
        setUnread(R.id.agentActionSessions, unread,
            context.getString(if (unread) R.string.chat_shortcut_sessions_unread else R.string.agent_sessions_title))
    }

    private fun setUnread(actionId: Int, unread: Boolean, description: String) {
        unreadDots[actionId]?.visibility = if (unread) VISIBLE else INVISIBLE
        findViewById<View>(actionId).contentDescription = description
    }

    private fun addAction(id: Int, label: Int, description: Int, icon: Int, dotId: Int? = null) {
        val button = object : FrameLayout(context) {
            private val inkBounds = Rect()

            override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(info)
                info.className = android.widget.Button::class.java.name
            }

            override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
                super.onLayout(changed, left, top, right, bottom)
                val content = getChildAt(0) as LinearLayout
                val image = content.getChildAt(0)
                val text = content.getChildAt(1) as TextView
                val label = text.text.toString()
                text.paint.getTextBounds(label, 0, label.length, inkBounds)
                // Align the visible glyphs, not the font's extra ascent/descent space.
                val textCenter = text.top + text.baseline + inkBounds.exactCenterY()
                image.translationY = textCenter - (image.top + image.height / 2f)
                if (childCount > 1) {
                    val dot = getChildAt(1)
                    val x = if (layoutDirection == LAYOUT_DIRECTION_RTL) {
                        content.left + text.left - dp(2) - dot.measuredWidth
                    } else content.left + text.right + dp(2)
                    val y = content.top + text.top + text.baseline + inkBounds.top - dp(2)
                    dot.layout(x, y, x + dot.measuredWidth, y + dot.measuredHeight)
                }
            }
        }.apply {
            this.id = id
            isClickable = true
            isFocusable = true
            contentDescription = context.getString(description)
            tooltipText = contentDescription
            val ripple = TypedValue()
            context.theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, ripple, true)
            setBackgroundResource(ripple.resourceId)
        }
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            isBaselineAligned = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            setPaddingRelative(dp(4), dp(10), dp(if (dotId == null) 4 else 8), dp(10))
            addView(ImageView(context).apply {
                setImageResource(icon)
                imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_primary))
            }, LinearLayout.LayoutParams(dp(16), dp(16)))
            addView(TextView(context).apply {
                if (id == R.id.agentInsightBar) this.id = R.id.agentInsightText
                setText(label)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(context.getColor(R.color.text_primary))
                includeFontPadding = false
                gravity = Gravity.CENTER_VERTICAL
                setSingleLine()
            }, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(4)
            })
        }
        button.addView(content, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        if (dotId != null) {
            val dot = View(context).apply {
                this.id = dotId
                visibility = INVISIBLE
                importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(context.getColor(R.color.chat_shortcut_unread))
                }
            }
            button.addView(dot, LayoutParams(dp(4), dp(4)))
            unreadDots[id] = dot
        }
        row.addView(button, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, dp(48)))
        actions += button
        contents += content
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val unspecified = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        contents.forEach { it.measure(unspecified, unspecified) }
        val widths = contents.map { it.measuredWidth.coerceAtLeast(dp(48)) }
        val available = (MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight).coerceAtLeast(0)
        val extra = (available - widths.sum()).coerceAtLeast(0)
        val height = contents.maxOf { it.measuredHeight }.coerceAtLeast(dp(48))
        actions.forEachIndexed { index, action ->
            action.layoutParams.width = widths[index] + extra / actions.size +
                if (index < extra % actions.size) 1 else 0
            action.layoutParams.height = height
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()
}
