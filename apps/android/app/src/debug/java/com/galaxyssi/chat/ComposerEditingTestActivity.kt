package com.galaxyssi.chat

import android.app.Activity
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import com.galaxyssi.chat.ui.AppleHoldToTalkController
import com.galaxyssi.chat.ui.ParagraphSelectingEditText
import com.galaxyssi.chat.ui.VoiceWaveformView

/** Debug-only, data-free host for the real composer views and hold-to-talk controller. */
class ComposerEditingTestActivity : Activity() {
    lateinit var input: ParagraphSelectingEditText
    var editing = true
    var recordingStarts = 0
    private lateinit var hold: AppleHoldToTalkController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val source = layoutInflater.inflate(R.layout.activity_main, null)
        input = source.findViewById(intent.getIntExtra("input_id", R.id.messageInput))
        (input.parent as ViewGroup).removeView(input)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 80, 24, 24)
        }
        root.addView(input, LinearLayout.LayoutParams(-1, -2))
        val other = TextView(this).apply {
            text = "Focus target"
            isFocusableInTouchMode = true
        }
        root.addView(other)
        val recording = LinearLayout(this).apply { visibility = View.GONE }
        val waveform = VoiceWaveformView(this)
        val timer = TextView(this)
        recording.addView(waveform)
        recording.addView(timer)
        root.addView(recording)
        setContentView(root)
        hold = AppleHoldToTalkController(
            activity = this, pressTarget = input, recordingGroup = recording,
            waveform = waveform, timer = timer, hasPermission = { true }, requestPermission = {},
            startRecording = { recordingStarts++; true }, currentAmplitude = { 0 }, finishRecording = {},
            onTap = { editing = true; input.requestFocus() }, holdStartDelayMillis = 280L
        )
        input.setOnTouchListener { view, event -> if (editing) false else hold.onTouch(view, event) }
        input.setText("123")
        input.requestFocus()
        input.setSelection(input.length())
    }

    override fun onDestroy() {
        hold.release()
        super.onDestroy()
    }
}
