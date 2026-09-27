package com.galaxyssi.chat

import android.app.Activity
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import com.galaxyssi.chat.ui.ParagraphSelectingEditText
import java.lang.ref.WeakReference
import java.util.UUID

/** A normal input window keeps the IME's system navigation controls intact. */
class ScreenAssistantPromptActivity : Activity() {
    private var requestId = ""
    private var submittedQuestion: String? = null
    private lateinit var input: ParagraphSelectingEditText
    private lateinit var voice: ImageButton
    private lateinit var send: ImageButton
    private lateinit var status: TextView
    private var dictation: ScreenAssistantDictation? = null
    private var dictationState = ScreenAssistantDictationState.IDLE
    private var promptTitle = R.string.screen_assistant_ask

    override fun attachBaseContext(base: Context) = super.attachBaseContext(AppLanguage.wrap(base))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestId = intent.getStringExtra(REQUEST_ID).orEmpty()
        val request = pending?.takeIf { it.id == requestId } ?: run { finish(); return }
        current = WeakReference(this)
        promptTitle = when (request.sendLabel) {
            R.string.screen_assistant_execute -> R.string.screen_assistant_execute
            R.string.screen_assistant_follow_up_send -> R.string.screen_assistant_follow_up
            else -> R.string.screen_assistant_ask
        }
        fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
        input = ParagraphSelectingEditText(this).apply {
            id = android.R.id.edit
            hint = getString(if (request.sendLabel == R.string.screen_assistant_execute) R.string.screen_assistant_task_hint else R.string.screen_assistant_question_hint)
            textSize = 15f
            minLines = 1
            maxLines = 6
            minHeight = dp(54)
            gravity = Gravity.TOP or Gravity.START
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            imeOptions = EditorInfo.IME_FLAG_NO_ENTER_ACTION
            setBackgroundColor(Color.TRANSPARENT)
            setTextColor(getColor(R.color.text_primary))
            setHintTextColor(getColor(R.color.text_secondary))
            setPadding(dp(12), dp(14), dp(6), dp(14))
            isVerticalScrollBarEnabled = true
            setText(savedInstanceState?.getString(DRAFT).orEmpty())
            setSelection(text?.length ?: 0)
        }
        status = TextView(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            text = getString(promptTitle)
            textSize = 13f
            setTextColor(getColor(R.color.text_secondary))
            setPadding(dp(12), 0, 0, 0)
        }
        voice = action(R.id.screenPromptVoice, R.drawable.ic_voice_call_wave,
            R.string.screen_assistant_voice_input, 12).apply {
            setOnClickListener { toggleDictation() }
        }
        send = action(R.id.screenPromptSend, R.drawable.ic_composer_send_plane,
            request.sendLabel, 11).apply {
            setOnClickListener {
                val question = input.text.toString().trim()
                if (ScreenAssistantComposerPolicy.canSubmit(question, dictationState)) {
                    submittedQuestion = question
                    dictation?.close()
                    getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(input.windowToken, 0)
                    finish()
                }
            }
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(4), 0, dp(4), dp(8))
            setBackgroundResource(R.drawable.agent_input_shell_background)
            addView(LinearLayout(this@ScreenAssistantPromptActivity).apply {
                gravity = Gravity.CENTER_VERTICAL
                addView(status, LinearLayout.LayoutParams(0, dp(40), 1f).apply { gravity = Gravity.CENTER_VERTICAL })
                addView(action(R.id.screenPromptCancel, R.drawable.ic_agent_progress_close,
                    R.string.common_cancel, 13).apply { setOnClickListener { finish() } },
                    LinearLayout.LayoutParams(dp(40), dp(40)))
            })
            addView(LinearLayout(this@ScreenAssistantPromptActivity).apply {
                gravity = Gravity.BOTTOM
                minimumHeight = dp(72)
                addView(input, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                addView(voice, LinearLayout.LayoutParams(dp(48), dp(54)))
                addView(send, LinearLayout.LayoutParams(dp(54), dp(54)))
            })
        }
        setContentView(content)
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = updateActions()
            override fun afterTextChanged(s: Editable?) = Unit
        })
        updateActions()
        window.setBackgroundDrawableResource(android.R.color.transparent)
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
        window.setLayout(resources.displayMetrics.widthPixels - dp(32), WindowManager.LayoutParams.WRAP_CONTENT)
        window.attributes = window.attributes.apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(8)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setFitInsetsTypes(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                setFitInsetsIgnoringVisibility(false)
            }
        }
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(WindowInsets.Type.navigationBars())
        }
        input.requestFocus()
    }

    private fun action(id: Int, icon: Int, label: Int, padding: Int) = ImageButton(this).apply {
        this.id = id
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(getColor(R.color.text_primary))
        setBackgroundColor(Color.TRANSPARENT)
        contentDescription = getString(label)
        val inset = (padding * resources.displayMetrics.density + 0.5f).toInt()
        setPadding(inset, inset, inset, inset)
        tooltipText = contentDescription
    }

    private fun updateActions() {
        send.isEnabled = ScreenAssistantComposerPolicy.canSubmit(input.text?.toString().orEmpty(), dictationState)
        send.alpha = if (send.isEnabled) 1f else 0.3f
        voice.isEnabled = dictationState != ScreenAssistantDictationState.RECOGNIZING
        voice.setImageResource(if (dictationState == ScreenAssistantDictationState.RECORDING)
            R.drawable.ic_screen_prompt_voice_stop else R.drawable.ic_voice_call_wave)
        voice.contentDescription = getString(if (dictationState == ScreenAssistantDictationState.RECORDING)
            R.string.screen_assistant_voice_finish else R.string.screen_assistant_voice_input)
        voice.tooltipText = voice.contentDescription
        input.isEnabled = dictationState == ScreenAssistantDictationState.IDLE
    }

    private fun toggleDictation() {
        if (dictationState == ScreenAssistantDictationState.RECORDING) {
            dictation?.stop()
            return
        }
        if (dictationState != ScreenAssistantDictationState.IDLE) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MICROPHONE_PERMISSION)
            return
        }
        val runner = AgentConversationWindows.screenAssistantRunner()
        if (runner == null) {
            status.setText(R.string.screen_assistant_open_app)
            return
        }
        dictation?.close()
        dictation = ScreenAssistantDictation(runner,
            onState = { state ->
                dictationState = state
                status.setText(when (state) {
                    ScreenAssistantDictationState.RECORDING -> R.string.voice_status_recording
                    ScreenAssistantDictationState.RECOGNIZING -> R.string.voice_status_recognizing
                    ScreenAssistantDictationState.IDLE -> promptTitle
                })
                updateActions()
            },
            onText = { text ->
                val start = input.selectionStart.coerceAtLeast(0)
                val end = input.selectionEnd.coerceAtLeast(start)
                input.text?.replace(start, end, text)
                input.setSelection((start + text.length).coerceAtMost(input.length()))
                input.requestFocus()
            },
            onError = { status.setText(it) }
        )
        if (runCatching { dictation?.start() == true }.getOrDefault(false).not()) {
            dictation?.close()
            dictationState = ScreenAssistantDictationState.IDLE
            updateActions()
            status.setText(R.string.screen_assistant_voice_busy)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MICROPHONE_PERMISSION && !isFinishing &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) toggleDictation()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        if (::input.isInitialized) outState.putString(DRAFT, input.text.toString())
        super.onSaveInstanceState(outState)
    }

    override fun onStop() {
        dictation?.close()
        super.onStop()
        if (!isChangingConfigurations && !isFinishing) finish()
    }

    override fun onDestroy() {
        dictation?.close()
        super.onDestroy()
        if (current?.get() === this) current = null
        if (isFinishing && pending?.id == requestId) {
            val request = pending
            pending = null
            submittedQuestion?.let { question -> request?.onSubmit?.invoke(question) }
        }
    }

    companion object {
        private const val REQUEST_ID = "screen_prompt_request_id"
        private const val DRAFT = "screen_prompt_draft"
        private const val MICROPHONE_PERMISSION = 481
        private data class Request(val id: String, val sendLabel: Int, val onSubmit: (String) -> Unit)
        private var pending: Request? = null
        private var current: WeakReference<ScreenAssistantPromptActivity>? = null

        internal fun isOpen(): Boolean = pending != null || current?.get() != null

        internal fun show(context: Context, sendLabel: Int, onSubmit: (String) -> Unit) {
            dismissIfOpen()
            val request = Request(UUID.randomUUID().toString(), sendLabel, onSubmit)
            pending = request
            try {
                context.startActivity(Intent(context, ScreenAssistantPromptActivity::class.java)
                    .putExtra(REQUEST_ID, request.id)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS))
            } catch (error: RuntimeException) {
                if (pending?.id == request.id) pending = null
                throw error
            }
        }

        internal fun dismissIfOpen(): Boolean {
            val open = pending != null || current?.get() != null
            pending = null
            current?.get()?.finish()
            current = null
            return open
        }
    }
}
