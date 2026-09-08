package com.galaxyssi.chat.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
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

    init {
        orientation = VERTICAL
        setBackgroundColor(context.getColor(R.color.surface_bg))
        addView(View(context).apply { setBackgroundColor(context.getColor(R.color.separator)) }, LayoutParams(-1, dp(1)))
        val heading = FrameLayout(context)
        status.apply {
            textSize = 14f
            setTextColor(context.getColor(R.color.text_secondary))
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        heading.addView(status, FrameLayout.LayoutParams(-1, dp(56)).apply { marginStart = dp(48); marginEnd = dp(48) })
        heading.addView(collapse, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.END or Gravity.CENTER_VERTICAL))
        addView(heading, LayoutParams(-1, dp(56)))
        waveform.setColors(context.getColor(R.color.agent_voice_transcript_dot), context.getColor(R.color.unread_red))
        waveform.useDenseRecordingStyle()
        addView(waveform, LayoutParams(dp(152), dp(26)).apply { gravity = Gravity.CENTER_HORIZONTAL })
        transcript.apply {
            textSize = 16f
            setTextColor(context.getColor(R.color.text_primary))
            gravity = Gravity.CENTER
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(dp(20), dp(8), dp(20), dp(8))
        }
        addView(transcript, LayoutParams(-1, dp(88)))
        val controls = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(4), 0, dp(8))
        }
        listOf(keyboard, camera, microphone, screen, hangup).forEach { button ->
            val slot = FrameLayout(context)
            slot.addView(button, FrameLayout.LayoutParams(dp(if (button === microphone) 60 else 48), dp(if (button === microphone) 60 else 48), Gravity.CENTER))
            controls.addView(slot, LayoutParams(0, dp(64), 1f))
        }
        microphone.background = actionBackground(0x1F18AFA0)
        microphone.imageTintList = ColorStateList.valueOf(context.getColor(R.color.agent_voice_transcript_dot))
        hangup.background = actionBackground(0x1FFF3B30)
        hangup.imageTintList = ColorStateList.valueOf(context.getColor(R.color.unread_red))
        addView(controls, LayoutParams(-1, dp(76)))
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
