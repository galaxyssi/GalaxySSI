package com.galaxyssi.chat.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.galaxyssi.chat.R

internal data class PhoneAssistantLine(val translated: String, val original: String,
    val outgoing: Boolean = false, val spokenToCall: Boolean = false)

internal data class PhoneAssistantDisplay(val caller: String, val status: String,
    val hasCall: Boolean, val ringing: Boolean = false, val route: String,
    val audioAvailable: Boolean = false, val listening: Boolean = false,
    val lines: List<PhoneAssistantLine> = emptyList())

/** The same compact footer as Agent voice mode; Telecom controls remain outside the transcript. */
internal class PhoneAssistantPanel(context: Context) : LinearLayout(context) {
    val back = ImageButton(context)
    val avatar = TextView(context)
    val product = ImageView(context)
    val title = text("", 18f)
    val status = text("", 12f, secondary = true)
    val language = text(context.getString(R.string.voice_control_languages), 14f, secondary = true)
    val content = LinearLayout(context)
    val footer = AgentVoicePanel(context)
    private val dot = View(context)
    private val scroll = ScrollView(context)
    private var renderedLines: List<PhoneAssistantLine>? = null
    private var renderedAvailability: Boolean? = null

    init {
        orientation = VERTICAL
        setBackgroundColor(context.getColor(R.color.page_bg))
        val header = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), dp(16), dp(8))
            setBackgroundColor(context.getColor(R.color.surface_bg))
        }
        back.apply {
            setImageResource(R.drawable.ic_navigation_back)
            imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_primary))
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            setPadding(dp(13), dp(13), dp(13), dp(13))
            contentDescription = context.getString(R.string.voice_control_back)
        }
        header.addView(back, LayoutParams(dp(48), dp(48)))
        avatar.apply {
            gravity = Gravity.CENTER; textSize = 22f
            setTextColor(0xFF2676C9.toInt())
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(0xFFE4F1FF.toInt()) }
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        product.apply {
            setImageResource(R.drawable.galaxyssi_mark_large)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        header.addView(avatar, LayoutParams(dp(40), dp(40)))
        header.addView(product, LayoutParams(dp(40), dp(40)))
        val identity = LinearLayout(context).apply { orientation = VERTICAL }
        title.apply { setTypeface(typeface, Typeface.BOLD); maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }
        identity.addView(title, LayoutParams(-1, -2))
        val details = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        dot.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(0xFF19B78E.toInt()) }
        details.addView(dot, LayoutParams(dp(6), dp(6)).apply { marginEnd = dp(5) })
        status.maxLines = 1
        status.ellipsize = android.text.TextUtils.TruncateAt.END
        details.addView(status, LayoutParams(-1, -2))
        identity.addView(details, LayoutParams(-1, -2).apply { topMargin = dp(3) })
        header.addView(identity, LayoutParams(0, -2, 1f).apply { marginStart = dp(10) })
        addView(header, LayoutParams(-1, dp(72)))
        language.gravity = Gravity.CENTER
        addView(language, LayoutParams(-1, dp(52)))
        content.orientation = VERTICAL
        content.setPadding(dp(20), dp(4), dp(20), dp(20))
        scroll.isFillViewport = true
        scroll.addView(content, android.widget.FrameLayout.LayoutParams(-1, -2))
        addView(scroll, LayoutParams(-1, 0, 1f))
        footer.apply {
            visibility = VISIBLE
            status.setOnClickListener(null)
            status.setOnLongClickListener(null)
            hangup.setImageResource(R.drawable.ic_voice_call_end)
            hangup.imageTintList = ColorStateList.valueOf(context.getColor(R.color.unread_red))
            hangup.contentDescription = context.getString(R.string.voice_call_end)
        }
        addView(footer, LayoutParams(-1, -2))
    }

    fun render(value: PhoneAssistantDisplay) {
        title.text = value.caller
        updateStatus(value.status)
        avatar.visibility = if (value.hasCall) VISIBLE else GONE
        product.visibility = if (value.hasCall) GONE else VISIBLE
        avatar.text = value.caller.codePoints().findFirst().orElse(0).takeIf { it != 0 }
            ?.let { String(Character.toChars(it)).uppercase() }.orEmpty()
        dot.visibility = if (value.hasCall) VISIBLE else GONE
        footer.route.text = value.route
        footer.route.isEnabled = value.hasCall
        footer.route.alpha = if (value.hasCall) 1f else .55f
        footer.hangup.isEnabled = value.hasCall
        footer.hangup.alpha = if (value.hasCall) 1f else .3f
        footer.status.setText(when {
            !value.hasCall -> R.string.voice_control_dial
            value.ringing -> R.string.voice_control_answer
            value.audioAvailable && value.listening -> R.string.voice_call_listening
            else -> R.string.voice_control_call_active
        })
        if (value.hasCall && !value.ringing && !(value.audioAvailable && value.listening))
            footer.status.text = value.status.substringBefore(" ·")
        footer.status.setTextColor(context.getColor(if (!value.hasCall || value.ringing)
            R.color.agent_voice_transcript_dot else R.color.text_primary))
        footer.status.contentDescription = context.getString(if (value.hasCall && !value.ringing)
            R.string.voice_control_call_controls else if (value.ringing) R.string.voice_control_answer else R.string.voice_control_dial)
        footer.transcript.text = if (value.audioAvailable) value.lines.lastOrNull()?.translated.orEmpty() else ""
        language.alpha = if (value.audioAvailable) 1f else .6f
        val lines = if (value.audioAvailable) value.lines else emptyList()
        if (renderedLines == lines && renderedAvailability == value.audioAvailable) return
        renderedLines = lines.toList()
        renderedAvailability = value.audioAvailable
        content.removeAllViews()
        if (lines.isEmpty()) {
            content.addView(text(context.getString(if (value.audioAvailable) R.string.voice_control_waiting_speech
                else R.string.voice_control_call_audio_not_connected), 14f, secondary = true).apply {
                gravity = Gravity.CENTER; setPadding(0, dp(32), 0, 0)
            }, LayoutParams(-1, -2))
        } else lines.forEach { addLine(it) }
    }

    fun updateStatus(value: String) { status.text = value }

    private fun addLine(line: PhoneAssistantLine) {
        val row = LinearLayout(context).apply { gravity = if (line.outgoing) Gravity.END else Gravity.START }
        val block = LinearLayout(context).apply {
            orientation = VERTICAL
            if (line.outgoing) {
                background = GradientDrawable().apply {
                    cornerRadius = dp(8).toFloat(); setColor(context.getColor(R.color.agent_user_bubble_bg))
                }
                setPadding(dp(12), dp(10), dp(12), dp(10))
            }
        }
        block.addView(text(line.translated, 17f), LayoutParams(-1, -2))
        block.addView(text(line.original, 14f, secondary = true), LayoutParams(-1, -2).apply { topMargin = dp(5) })
        row.addView(block, LayoutParams(-1, -2).apply { if (line.outgoing) marginStart = dp(44) })
        content.addView(row, LayoutParams(-1, -2).apply { topMargin = dp(14) })
        if (line.outgoing && line.spokenToCall) content.addView(text(context.getString(R.string.voice_control_replied_english),
            12f, secondary = true).apply { gravity = Gravity.END }, LayoutParams(-1, -2).apply { topMargin = dp(5) })
    }

    private fun text(value: String, size: Float, secondary: Boolean = false) = TextView(context).apply {
        text = value; textSize = size
        setTextColor(context.getColor(if (secondary) R.color.text_secondary else R.color.text_primary))
        setLineSpacing(dp(2).toFloat(), 1f)
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
