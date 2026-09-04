package com.galaxyssi.chat.ui

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.TextView
import android.widget.Toast
import com.galaxyssi.chat.R
import java.util.Locale

class AppleHoldToTalkController(
    private val activity: Activity,
    private val pressTarget: View,
    private val instruction: TextView? = null,
    private val idleContent: View? = null,
    private val recordingGroup: View,
    private val waveform: VoiceWaveformView,
    private val transcript: TextView? = null,
    private val timer: TextView,
    private val hasPermission: () -> Boolean,
    private val requestPermission: () -> Unit,
    private val startRecording: () -> Boolean,
    private val currentAmplitude: () -> Int,
    private val finishRecording: (send: Boolean) -> Unit,
    private val onRecordingStarted: () -> Unit = {},
    private val onTap: () -> Unit = {},
    private val stableTranscriptColor: Int? = null,
    private val unstableTranscriptColor: Int? = null,
    private val idleInstructionRes: Int = R.string.input_press_to_talk,
    private val recordingInstructionRes: Int = R.string.voice_release_to_send,
    private val holdStartDelayMillis: Long = 0L
) : View.OnTouchListener {
    private val handler = Handler(Looper.getMainLooper())
    private val cancelThreshold = 56f * activity.resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(activity).scaledTouchSlop.toFloat()
    private var recording = false
    private var touchActive = false
    private var cancelPending = false
    private var downX = 0f
    private var downY = 0f
    private var startedAt = 0L

    private val startAfterHold = Runnable {
        if (!touchActive || recording) return@Runnable
        if (!hasPermission()) {
            touchActive = false
            requestPermission()
            return@Runnable
        }
        if (!startRecording()) {
            touchActive = false
            return@Runnable
        }
        recording = true
        cancelPending = false
        startedAt = SystemClock.elapsedRealtime()
        pressTarget.cancelLongPress()
        pressTarget.parent?.requestDisallowInterceptTouchEvent(true)
        pressTarget.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        onRecordingStarted()
        showRecordingUi()
        handler.post(meter)
    }

    private val meter = object : Runnable {
        override fun run() {
            if (!recording) return
            val elapsed = SystemClock.elapsedRealtime() - startedAt
            timer.text = String.format(Locale.US, "%02d:%02d", elapsed / 60_000, elapsed / 1000 % 60)
            waveform.pushAmplitude(runCatching(currentAmplitude).getOrDefault(0))
            if (elapsed >= 120_000L) complete(sendRequested = true) else handler.postDelayed(this, 50L)
        }
    }

    override fun onTouch(view: View, event: MotionEvent): Boolean = when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> {
            touchActive = true
            downX = event.rawX
            downY = event.rawY
            handler.removeCallbacks(startAfterHold)
            if (holdStartDelayMillis <= 0L) {
                startAfterHold.run()
                recording
            } else {
                handler.postDelayed(startAfterHold, holdStartDelayMillis)
                true
            }
        }
        MotionEvent.ACTION_MOVE -> {
            if (recording) {
                updateCancelState(downY - event.rawY >= cancelThreshold)
                true
            } else {
                val moved = kotlin.math.abs(event.rawX - downX) > touchSlop ||
                    kotlin.math.abs(event.rawY - downY) > touchSlop
                if (moved) {
                    touchActive = false
                    handler.removeCallbacks(startAfterHold)
                }
                holdStartDelayMillis > 0L
            }
        }
        MotionEvent.ACTION_UP -> {
            val tapCandidate = touchActive
            touchActive = false
            handler.removeCallbacks(startAfterHold)
            if (recording) {
                complete(sendRequested = true)
                true
            } else {
                if (tapCandidate && holdStartDelayMillis > 0L) {
                    pressTarget.performClick()
                    onTap()
                }
                holdStartDelayMillis > 0L
            }
        }
        MotionEvent.ACTION_CANCEL -> {
            touchActive = false
            handler.removeCallbacks(startAfterHold)
            if (recording) {
                complete(sendRequested = false)
                true
            } else {
                holdStartDelayMillis > 0L
            }
        }
        else -> recording
    }

    fun release() {
        touchActive = false
        handler.removeCallbacks(startAfterHold)
        if (recording) complete(sendRequested = false)
        handler.removeCallbacks(meter)
    }

    fun updateTranscript(stableText: String, unstableText: String) {
        val target = transcript ?: return
        val stable = stableText.trim()
        val unstable = unstableText.trim()
        if (stable.isBlank() && unstable.isBlank()) return
        val separator = if (stable.isNotBlank() && unstable.isNotBlank() &&
            stable.last().isLetterOrDigit() && unstable.first().isLetterOrDigit() &&
            !stable.last().isCjk() && !unstable.first().isCjk()
        ) " " else ""
        val value = stable + separator + unstable
        val styled = SpannableString(value)
        if (stable.isNotBlank()) {
            styled.setSpan(
                ForegroundColorSpan(stableTranscriptColor ?: activity.getColor(R.color.text_primary)),
                0,
                stable.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        val unstableStart = stable.length + separator.length
        if (unstableStart < styled.length) {
            styled.setSpan(
                ForegroundColorSpan(unstableTranscriptColor ?: activity.getColor(R.color.text_secondary)),
                unstableStart,
                styled.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        waveform.visibility = View.GONE
        target.visibility = View.VISIBLE
        target.text = styled
    }

    private fun showRecordingUi() {
        instruction?.text = activity.getString(recordingInstructionRes)
        idleContent?.apply {
            visibility = View.GONE
            isEnabled = false
        }
        recordingGroup.visibility = View.VISIBLE
        transcript?.apply {
            text = ""
            visibility = View.GONE
        }
        waveform.visibility = View.VISIBLE
        waveform.reset()
        timer.text = "00:00"
        timer.setTextColor(stableTranscriptColor ?: activity.getColor(R.color.text_secondary))
    }

    private fun updateCancelState(cancel: Boolean) {
        if (cancelPending == cancel) return
        cancelPending = cancel
        pressTarget.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        instruction?.text = activity.getString(
            if (cancel) R.string.voice_release_to_cancel else recordingInstructionRes
        )
        waveform.setCancelPending(cancel)
        timer.setTextColor(activity.getColor(if (cancel) R.color.apple_voice_cancel else R.color.text_secondary))
    }

    private fun complete(sendRequested: Boolean) {
        if (!recording) return
        handler.removeCallbacks(meter)
        val elapsed = SystemClock.elapsedRealtime() - startedAt
        val tooShort = elapsed < 800L
        val send = sendRequested && !cancelPending && !tooShort
        recording = false
        pressTarget.parent?.requestDisallowInterceptTouchEvent(false)
        recordingGroup.visibility = View.GONE
        transcript?.apply {
            text = ""
            visibility = View.GONE
        }
        waveform.visibility = View.VISIBLE
        idleContent?.apply {
            visibility = View.VISIBLE
            isEnabled = true
        }
        waveform.reset()
        timer.setTextColor(stableTranscriptColor ?: activity.getColor(R.color.text_secondary))
        instruction?.text = activity.getString(idleInstructionRes)
        finishRecording(send)
        if (tooShort && sendRequested && !cancelPending) {
            Toast.makeText(activity, R.string.voice_too_short, Toast.LENGTH_SHORT).show()
        } else if (cancelPending) {
            Toast.makeText(activity, R.string.voice_cancelled, Toast.LENGTH_SHORT).show()
        }
        cancelPending = false
    }

    private fun Char.isCjk(): Boolean = code in 0x3400..0x9fff

}
