package com.galaxyssi.chat.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import com.galaxyssi.chat.R

internal class AgentVoicePanel(context: Context) : LinearLayout(context) {
    val status = TextView(context)
    val transcript = TextView(context)
    val waveform = VoiceWaveformView(context)
    val collapse = icon(R.drawable.ic_chevron_down, R.string.voice_call_collapse)
    val keyboard = icon(R.drawable.ic_voice_call_keyboard, R.string.voice_call_keyboard)
    val camera = icon(R.drawable.ic_agent_camera, R.string.voice_call_camera)
    val microphone = icon(R.drawable.ic_voice_call_mic, R.string.voice_call_mute)
    val screen = icon(R.drawable.ic_agent_screen, R.string.voice_call_screen)
    val hangup = icon(R.drawable.ic_voice_call_end, R.string.voice_call_end)
    val route = TextView(context)

    init {
        orientation = VERTICAL
        setBackgroundColor(context.getColor(R.color.surface_bg))
        setPadding(dp(16), dp(8), dp(16), dp(12))
        val heading = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        status.apply {
            textSize = 16f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setTextColor(context.getColor(R.color.text_primary))
            gravity = Gravity.CENTER_VERTICAL
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        heading.addView(status, LayoutParams(0, dp(48), 1f))
        route.apply {
            textSize = 14f
            maxWidth = dp(140)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL or Gravity.END
            setTextColor(context.getColor(R.color.text_secondary))
            setPadding(dp(8), 0, dp(8), 0)
            val headphones = context.getDrawable(R.drawable.ic_voice_headphones)?.apply { setBounds(0, 0, dp(18), dp(18)) }
            val chevron = context.getDrawable(R.drawable.ic_chevron_down)?.apply { setBounds(0, 0, dp(12), dp(12)) }
            setCompoundDrawablesRelative(headphones, null, chevron, null)
            compoundDrawablePadding = dp(4)
            contentDescription = context.getString(R.string.voice_control_audio_route)
            isFocusable = true
        }
        heading.addView(route, LayoutParams(LayoutParams.WRAP_CONTENT, dp(48)))
        hangup.setImageResource(R.drawable.ic_screen_prompt_voice_stop)
        hangup.background = actionBackground(0x0F808080)
        heading.addView(hangup, LayoutParams(dp(48), dp(48)))
        addView(heading, LayoutParams(-1, dp(48)))
        waveform.setColors(context.getColor(R.color.agent_voice_transcript_dot), context.getColor(R.color.unread_red))
        waveform.useDenseRecordingStyle()
        transcript.apply {
            textSize = 16f
            setTextColor(context.getColor(R.color.text_secondary))
            gravity = Gravity.TOP or Gravity.START
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(0, dp(8), 0, 0)
        }
        addView(transcript, LayoutParams(-1, dp(72)))
        microphone.background = actionBackground(0x1F18AFA0)
        microphone.imageTintList = ColorStateList.valueOf(context.getColor(R.color.agent_voice_transcript_dot))
        // Keep optional camera/keyboard controls available without a permanent button row.
        status.setOnClickListener { microphone.performClick() }
        status.setOnLongClickListener {
            val buttons = listOf(keyboard, camera, screen, collapse)
            android.app.AlertDialog.Builder(context).setItems(buttons.map { it.contentDescription }.toTypedArray()) { _, i ->
                buttons[i].performClick()
            }.show()
            true
        }
        visibility = GONE
    }

    fun setMuted(muted: Boolean) {
        microphone.setImageResource(if (muted) R.drawable.ic_voice_call_mic_off else R.drawable.ic_voice_call_mic)
        microphone.imageTintList = ColorStateList.valueOf(context.getColor(
            if (muted) R.color.text_secondary else R.color.agent_voice_transcript_dot
        ))
        microphone.isSelected = muted
        microphone.contentDescription = context.getString(if (muted) R.string.voice_call_unmute else R.string.voice_call_mute)
        microphone.tooltipText = microphone.contentDescription
        if (muted) waveform.reset()
    }

    fun setCameraActive(active: Boolean) {
        camera.isSelected = active
        camera.background = actionBackground(if (active) 0x1F18AFA0 else 0)
        camera.imageTintList = ColorStateList.valueOf(context.getColor(
            if (active) R.color.agent_voice_transcript_dot else R.color.text_primary
        ))
        camera.contentDescription = context.getString(if (active) R.string.voice_call_camera_close else R.string.voice_call_camera)
        camera.tooltipText = camera.contentDescription
    }

    private fun icon(drawable: Int, description: Int) = ImageButton(context).apply {
        setImageResource(drawable)
        imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_primary))
        setPadding(dp(11), dp(11), dp(11), dp(11))
        background = actionBackground(0)
        contentDescription = context.getString(description)
        tooltipText = contentDescription
    }

    private fun actionBackground(color: Int): RippleDrawable {
        val highlight = TypedValue()
        context.theme.resolveAttribute(android.R.attr.colorControlHighlight, highlight, true)
        return RippleDrawable(ColorStateList.valueOf(highlight.data), circle(color), circle(0xFFFFFFFF.toInt()))
    }

    private fun circle(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
