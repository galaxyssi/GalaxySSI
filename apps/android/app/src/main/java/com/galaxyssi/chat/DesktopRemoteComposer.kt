package com.galaxyssi.chat

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.method.PasswordTransformationMethod
import android.view.LayoutInflater
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.ImageButton
import android.widget.PopupMenu
import android.widget.TextView
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.galaxyssi.chat.ui.AgentComposerUiPolicy
import com.galaxyssi.chat.ui.AppleHoldToTalkController
import com.galaxyssi.chat.ui.ParagraphSelectingEditText
import com.galaxyssi.chat.ui.VoiceWaveformView

internal class DesktopRemoteComposer(
    private val activity: Activity,
    private val onSend: (String) -> Unit
) {
    val view: View = LayoutInflater.from(activity).inflate(R.layout.view_desktop_remote_composer, null)
    val editor: ParagraphSelectingEditText = view.findViewById(R.id.remoteDraftInput)
    private val more: ImageButton = view.findViewById(R.id.remoteDraftMore)
    private val send: ImageButton = view.findViewById(R.id.remoteDraftSend)
    private val voiceButton: ImageButton = view.findViewById(R.id.remoteDraftVoice)
    private val status: TextView = view.findViewById(R.id.remoteDraftStatus)
    private val submission = DesktopDraftSubmission()
    private var textMode = true
    private var recognizing = false
    private var menu: PopupMenu? = null
    private val voice by lazy {
        DesktopDraftVoice(activity,
            onBusy = { busy ->
                recognizing = busy
                if (busy) showStatus(activity.getString(R.string.desktop_remote_draft_transcribing))
                else if (status.text == activity.getString(R.string.desktop_remote_draft_transcribing)) showStatus("")
                render()
            },
            onTranscript = ::appendTranscript,
            onFailure = {
                hold.release()
                showStatus(activity.getString(R.string.desktop_remote_draft_voice_failed))
            })
    }
    private val hold: AppleHoldToTalkController

    init {
        view.visibility = View.GONE
        val waveform: VoiceWaveformView = view.findViewById(R.id.remoteDraftWaveform)
        waveform.useDenseRecordingStyle()
        hold = AppleHoldToTalkController(
            activity = activity, pressTarget = editor,
            instruction = view.findViewById(R.id.remoteDraftInstruction),
            idleContent = view.findViewById(R.id.remoteDraftRow),
            recordingGroup = view.findViewById(R.id.remoteDraftRecording), waveform = waveform,
            timer = view.findViewById(R.id.remoteDraftTimer),
            hasPermission = { activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED },
            requestPermission = { activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 6381) },
            startRecording = { submission.pendingId == null && !recognizing && voice.start() },
            currentAmplitude = { voice.amplitude() },
            finishRecording = { voice.finish(it) },
            onRecordingStarted = { hideKeyboard(); showStatus("") },
            onTap = ::showKeyboard,
            idleInstructionRes = R.string.desktop_remote_draft_recording,
            recordingInstructionRes = R.string.desktop_remote_draft_recording,
            holdStartDelayMillis = 280
        )
        editor.setOnTouchListener { touched, event -> if (textMode) false else hold.onTouch(touched, event) }
        voiceButton.setOnTouchListener { touched, event -> hold.onTouch(touched, event) }
        editor.setOnFocusChangeListener { _, focused -> if (focused) { textMode = true; render() } }
        editor.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { submission.edited(); render() }
            override fun afterTextChanged(s: Editable?) = Unit
        })
        send.setOnClickListener {
            if (submission.pendingId == null && !recognizing && !editor.text.isNullOrBlank()) onSend(editor.text.toString())
        }
        more.setOnClickListener { anchor ->
            menu?.dismiss()
            menu = PopupMenu(activity, anchor).apply {
                menu.add(R.string.desktop_remote_draft_voice)
                setOnMenuItemClickListener { hideKeyboard(); true }
                setOnDismissListener { more.renderComposerMoreButton(false) }
                more.renderComposerMoreButton(true)
                show()
            }
        }
        render()
    }

    fun open(password: Boolean = false) {
        view.visibility = View.VISIBLE
        if ((editor.transformationMethod is PasswordTransformationMethod) != password) editor.text?.clear()
        editor.setRawInputType(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
            if (password) InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_TEXT_FLAG_CAP_SENTENCES)
        editor.transformationMethod = if (password) PasswordTransformationMethod.getInstance() else null
        showKeyboard()
    }

    fun constrainHeight(availableHeight: Int) {
        if (availableHeight <= 0) return
        val room = availableHeight / 2 - editor.compoundPaddingTop - editor.compoundPaddingBottom - status.measuredHeight
        val lines = (room / editor.lineHeight.coerceAtLeast(1)).coerceIn(1, 8)
        if (editor.maxLines != lines) editor.maxLines = lines
    }

    fun showKeyboard() {
        textMode = true
        render()
        editor.requestFocus()
        editor.post {
            if (view.isShown && editor.hasFocus()) WindowInsetsControllerCompat(activity.window, editor).show(WindowInsetsCompat.Type.ime())
        }
    }

    fun onKeyboardVisibilityChanged(visible: Boolean) {
        if (!view.isShown) return
        textMode = visible
        if (!visible) editor.clearFocus()
        render()
    }

    fun hideKeyboard() {
        activity.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(editor.windowToken, 0)
        editor.clearFocus()
        textMode = false
        render()
    }

    fun appendTranscript(text: String) {
        val combined = AgentVoiceTranscriptPolicy.mergeDraftWithTranscript(editor.text.toString(), text)
        editor.setText(combined)
        editor.setSelection(editor.length())
        showKeyboard()
    }

    fun beginSend(actionId: String) {
        if (submission.begin(actionId)) { showStatus(activity.getString(R.string.desktop_remote_draft_sending)); render() }
    }

    fun received(actionId: String, succeeded: Boolean) {
        if (submission.pendingId != actionId) return
        if (submission.complete(actionId, succeeded)) editor.text?.clear()
        showStatus("")
        render()
    }

    fun failed(message: String) {
        val wasSending = submission.pendingId != null
        submission.cancel()
        if (view.isShown) showStatus(if (wasSending) activity.getString(R.string.desktop_remote_draft_failed, message) else message)
        render()
    }

    fun pause() {
        hold.release()
        voice.cancel()
        menu?.dismiss()
        hideKeyboard()
        if (submission.pendingId != null) failed(activity.getString(R.string.desktop_remote_input_timeout))
    }

    fun hide() { pause(); view.visibility = View.GONE }

    fun background() {
        hide()
        // Never put a remote draft (which may be a password) in saved state or on disk.
        voice.cancel()
        submission.cancel()
        editor.text?.clear()
        showStatus("")
    }

    fun close() { background(); voice.close() }

    private fun showStatus(message: String) {
        status.text = message
        status.visibility = if (message.isBlank()) View.GONE else View.VISIBLE
    }

    private fun render() {
        val ui = AgentComposerUiPolicy.resolve(!editor.text.isNullOrBlank(), textMode, false, true)
        send.visibility = if (ui.showSendButton) View.VISIBLE else View.GONE
        send.isEnabled = submission.pendingId == null && !recognizing
        send.alpha = if (send.isEnabled) 1f else 0.4f
        more.visibility = if (ui.showMoreButton) View.VISIBLE else View.GONE
        more.isEnabled = !recognizing && submission.pendingId == null
        voiceButton.visibility = if (ui.showVoiceButton) View.VISIBLE else View.GONE
        voiceButton.isEnabled = more.isEnabled
    }
}
