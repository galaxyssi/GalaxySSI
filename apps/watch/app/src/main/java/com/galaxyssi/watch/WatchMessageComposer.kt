package com.galaxyssi.watch

import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.InputFilter
import android.text.TextWatcher
import android.view.*
import android.widget.*
import com.galaxyssi.chat.ui.AgentComposerUiPolicy

/** Shared by Agent and person conversations: one layout and one gesture policy. */
class WatchMessageComposer(
    context: Context,
    draft: String,
    private val onDraft: (String) -> Unit,
    private val onSend: () -> Unit,
    private val onVoice: () -> Unit,
    private val onMenu: () -> Unit
) : LinearLayout(context) {
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private val secondary = Color.rgb(165, 171, 182)
    private var keyboardVisible = false
    private var keyboardVisibleAtTouchDown = false
    val input = object : EditText(context) {
        override fun onCreateInputConnection(outAttrs: android.view.inputmethod.EditorInfo): android.view.inputmethod.InputConnection? {
            val connection = super.onCreateInputConnection(outAttrs)
            // Samsung's full-screen editor copies this before IME insets arrive.
            outAttrs.hintText = context.getString(R.string.message_hint)
            return connection
        }
    }.apply {
        setText(draft); setHint(R.string.composer_hint); setTextColor(Color.WHITE); setHintTextColor(secondary)
        textSize = 12.5f; minHeight = dp(36); includeFontPadding = false; maxLines = if (draft.isBlank()) 1 else 2
        ellipsize = android.text.TextUtils.TruncateAt.END
        background = null; setPadding(0, dp(4), 0, dp(4))
        filters = arrayOf(InputFilter.LengthFilter(4000))
        inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
        setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                keyboardVisibleAtTouchDown = rootWindowInsets?.isVisible(WindowInsets.Type.ime()) ?: keyboardVisible
            }
            false
        }
        setOnLongClickListener {
            if (keyboardVisibleAtTouchDown || keyboardVisible) false
            else { onVoice(); true }
        }
    }
    // Android keeps send and more as separate controls, even when they share a layout slot.
    private val sendAction = ImageButton(context).apply {
        background = null; setPadding(dp(8), dp(8), dp(8), dp(8))
        setImageResource(R.drawable.ic_composer_send_plane)
        contentDescription = context.getString(R.string.send)
        setOnClickListener { if (!busy && input.text.isNotBlank()) onSend() }
    }
    private val menuAction = ImageButton(context).apply {
        background = null; setPadding(dp(8), dp(8), dp(8), dp(8))
        setImageResource(R.drawable.ic_input_menu_layers)
        contentDescription = context.getString(R.string.home_menu)
        setOnClickListener { if (!busy) onMenu() }
    }
    private val actionSlot = FrameLayout(context).apply {
        addView(menuAction, FrameLayout.LayoutParams(-1, -1))
        addView(sendAction, FrameLayout.LayoutParams(-1, -1))
    }
    private var busy = false

    init {
        gravity = Gravity.CENTER_VERTICAL
        addView(input, LayoutParams(0, -2, 1f))
        addView(actionSlot, LayoutParams(dp(40), dp(36)))
        setOnApplyWindowInsetsListener { _, insets ->
            keyboardVisible = insets.isVisible(WindowInsets.Type.ime())
            input.setHint(if (keyboardVisible) R.string.message_hint else R.string.composer_hint)
            insets
        }
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { onDraft(s?.toString().orEmpty()); refreshAction() }
            override fun afterTextChanged(s: Editable?) = Unit
        })
        refreshAction()
    }
    fun placement(parentHorizontalInsetDp: Int = 0): LayoutParams {
        val inset = (resources.configuration.screenWidthDp * 0.15f).toInt().coerceAtLeast(28)
        return LayoutParams(-1, -2).apply {
            topMargin = dp(2)
            leftMargin = dp((inset - parentHorizontalInsetDp).coerceAtLeast(0)); rightMargin = leftMargin
        }
    }
    private fun refreshAction() {
        input.maxLines = if (input.text.isBlank()) 1 else 2
        val state = AgentComposerUiPolicy.resolve(input.text.isNotBlank(), textModeActive = true, actionTrayRequested = false)
        sendAction.visibility = if (state.showSendButton) VISIBLE else GONE
        menuAction.visibility = if (state.showMoreButton) VISIBLE else GONE
        sendAction.isEnabled = !busy
        menuAction.isEnabled = !busy
    }
    fun sending(value: Boolean) { busy = value; input.isEnabled = !value; refreshAction() }
    fun setDraft(value: String) { if (input.text.toString() != value) input.setText(value) }
}
