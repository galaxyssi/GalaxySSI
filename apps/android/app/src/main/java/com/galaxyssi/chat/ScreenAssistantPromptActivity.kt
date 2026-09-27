package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference
import java.util.UUID

/** A normal input window keeps the IME's system navigation controls intact. */
class ScreenAssistantPromptActivity : Activity() {
    private var requestId = ""
    private var submittedQuestion: String? = null

    override fun attachBaseContext(base: Context) = super.attachBaseContext(AppLanguage.wrap(base))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestId = intent.getStringExtra(REQUEST_ID).orEmpty()
        val request = pending?.takeIf { it.id == requestId } ?: run { finish(); return }
        current = WeakReference(this)
        fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
        val input = EditText(this).apply {
            id = android.R.id.edit
            hint = getString(if (request.sendLabel == R.string.screen_assistant_execute) R.string.screen_assistant_task_hint else R.string.screen_assistant_question_hint)
            textSize = 15f
            minLines = 2
            maxLines = 4
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(18).toFloat()
            }
            addView(input)
            addView(TextView(this@ScreenAssistantPromptActivity).apply {
                text = getString(request.sendLabel)
                textSize = 14f
                setTextColor(0xFF20342D.toInt())
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), 0, dp(16), 0)
                minHeight = dp(48)
                setOnClickListener {
                    val question = input.text.toString().trim()
                    if (question.isBlank() && request.sendLabel == R.string.screen_assistant_follow_up_send) {
                        input.error = getString(R.string.screen_assistant_question_hint)
                    } else {
                        submittedQuestion = question
                        getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(input.windowToken, 0)
                        finish()
                    }
                }
            })
        }
        setContentView(content)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
        window.setLayout(resources.displayMetrics.widthPixels - dp(32), dp(180))
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

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations && !isFinishing) finish()
    }

    override fun onDestroy() {
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
