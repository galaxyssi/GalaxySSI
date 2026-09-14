package com.galaxyssi.watch

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.Editable
import android.text.InputFilter
import android.text.TextWatcher
import android.view.*
import android.widget.*

/** Fixed Android-style brand/composer around an independently scrolling transcript. */
class WatchConversationView(
    context: Context,
    draft: String,
    private val onDraft: (String) -> Unit,
    private val onSend: () -> Unit,
    private val onVoice: () -> Unit,
    private val onMenu: () -> Unit,
    private val onSessions: () -> Unit,
    private val onModel: () -> Unit,
    private val onStop: (WatchTask) -> Unit,
    private val onRead: (String) -> Unit,
    private val onConnect: () -> Unit
) : LinearLayout(context) {
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private val secondary = Color.rgb(165, 171, 182)
    private fun text(value: String, size: Float = 14f) = TextView(context).apply {
        this.text = value; textSize = size; setTextColor(Color.WHITE); includeFontPadding = false
    }
    private val heading = text("", 11f)
    private val model = text("", 9f).apply { setTextColor(secondary) }
    private val transcript = LinearLayout(context).apply { orientation = VERTICAL }
    private val transcriptScroll = ScrollView(context).apply {
        isFillViewport = true; isVerticalScrollBarEnabled = true
        addView(transcript, LayoutParams(-1, -2))
        setOnGenericMotionListener { _, event ->
            if (event.action == MotionEvent.ACTION_SCROLL) {
                scrollBy(0, (-event.getAxisValue(MotionEvent.AXIS_SCROLL) * ViewConfiguration.get(context).scaledVerticalScrollFactor).toInt()); true
            } else false
        }
    }
    private val newReply = text(context.getString(R.string.new_reply), 11f).apply {
        gravity = Gravity.CENTER; setTextColor(Color.rgb(101, 217, 203)); visibility = GONE
        minHeight = dp(48)
        setOnClickListener { transcriptScroll.fullScroll(View.FOCUS_DOWN); visibility = GONE }
    }
    val input = EditText(context).apply {
        setText(draft); setHint(R.string.composer_hint); setTextColor(Color.WHITE); setHintTextColor(secondary)
        textSize = 12.5f; minHeight = dp(36); includeFontPadding = false; maxLines = if (draft.isBlank()) 1 else 2
        ellipsize = android.text.TextUtils.TruncateAt.END
        background = null; setPadding(0, dp(4), 0, dp(4))
        filters = arrayOf(InputFilter.LengthFilter(4000))
        inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
        setOnLongClickListener { onVoice(); true }
    }
    private val action = ImageButton(context).apply {
        background = null; setPadding(dp(8), dp(8), dp(8), dp(8))
        setOnClickListener { if (input.text.isNotBlank()) onSend() else onMenu() }
    }
    private var busy = false
    private var lastTurns = emptyList<WatchTask>()
    private var lastReady: Boolean? = null
    private val waitingLabels = mutableListOf<Pair<WatchTask, TextView>>()
    private val ticker = object : Runnable {
        override fun run() {
            waitingLabels.forEach { (task, label) ->
                label.text = statusText(task)
            }
            postDelayed(this, 1000)
        }
    }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); post(ticker) }
    override fun onDetachedFromWindow() { removeCallbacks(ticker); super.onDetachedFromWindow() }

    init {
        orientation = VERTICAL; setBackgroundColor(Color.BLACK)
        isFocusableInTouchMode = true
        val headerInset = (resources.configuration.screenWidthDp * 0.125f).toInt().coerceAtLeast(24)
        val transcriptInset = (resources.configuration.screenWidthDp * 0.065f).toInt().coerceAtLeast(12)
        val composerInset = (resources.configuration.screenWidthDp * 0.15f).toInt().coerceAtLeast(28)
        setPadding(0, dp(10), 0, dp(18))
        addView(text(java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date()), 10f).apply {
            gravity = Gravity.CENTER; setTextColor(secondary)
        }, LayoutParams(-1, dp(12)))
        val header = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(headerInset), 0, dp(headerInset), 0) }
        val brand = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(40)
            contentDescription = context.getString(R.string.home_menu)
            setOnClickListener { onMenu() }
            addView(ImageView(context).apply { setImageResource(R.mipmap.ic_launcher) }, LayoutParams(dp(22), dp(22)))
            addView(LinearLayout(context).apply {
                orientation = VERTICAL; setPadding(dp(4), 0, 0, 0)
                addView(text(context.getString(R.string.app_name), 10.5f).apply { setTypeface(typeface, Typeface.BOLD) })
                addView(text(context.getString(R.string.agent_brand), 8f).apply {
                    setTextColor(secondary)
                    // Match the visible left edge of the Latin title glyphs.
                    setPadding(dp(1), 0, 0, 0)
                })
            })
        }
        header.addView(brand, LayoutParams(0, dp(40), 1.15f))
        header.addView(LinearLayout(context).apply {
            orientation = VERTICAL; gravity = Gravity.CENTER_VERTICAL or Gravity.END
            contentDescription = context.getString(R.string.recent)
            setOnClickListener { onSessions() }; setOnLongClickListener { onModel(); true }
            heading.maxLines = 1; heading.ellipsize = android.text.TextUtils.TruncateAt.END
            model.maxLines = 1; model.ellipsize = android.text.TextUtils.TruncateAt.END
            addView(heading); addView(model)
        }, LayoutParams(0, dp(40), 1f))
        addView(header)
        addView(FrameLayout(context).apply {
            addView(transcriptScroll, FrameLayout.LayoutParams(-1, -1))
            addView(newReply, FrameLayout.LayoutParams(-1, dp(48), Gravity.BOTTOM))
        }, LayoutParams(-1, 0, 1f).apply { leftMargin = dp(transcriptInset); rightMargin = dp(transcriptInset) })
        addView(LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(input, LayoutParams(0, -2, 1f)); addView(action, LayoutParams(dp(40), dp(36)))
        }, LayoutParams(-1, -2).apply { topMargin = dp(2); leftMargin = dp(composerInset); rightMargin = dp(composerInset) })
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { onDraft(s?.toString().orEmpty()); refreshAction() }
            override fun afterTextChanged(s: Editable?) = Unit
        })
        refreshAction()
        requestFocus()
    }

    private fun refreshAction() {
        input.maxLines = if (input.text.isBlank()) 1 else 2
        action.setImageResource(if (input.text.isNotBlank()) R.drawable.ic_composer_send_plane else R.drawable.ic_input_menu_layers)
        action.contentDescription = context.getString(if (input.text.isNotBlank()) R.string.send else R.string.home_menu)
        action.isEnabled = !busy
    }
    fun sending(value: Boolean) { busy = value; input.isEnabled = !value; refreshAction() }
    fun setDraft(value: String) { if (input.text.toString() != value) input.setText(value) }
    private fun statusText(task: WatchTask): String {
        val seconds = ((System.currentTimeMillis() - task.sourceId) / 1000).coerceAtLeast(0)
        val status = context.getString(R.string.waiting_elapsed, context.getString(task.state.label()), seconds)
        return if (task.state == TaskState.STOP_REQUESTED) status else "$status\n${context.getString(R.string.stop_task)}"
    }

    fun update(turns: List<WatchTask>, modelName: String, ready: Boolean, resetScroll: Boolean = false) {
        heading.text = turns.firstOrNull()?.prompt?.take(18) ?: context.getString(R.string.new_conversation)
        model.text = modelName
        if (turns == lastTurns && ready == lastReady && !resetScroll) return
        val oldOffset = transcriptScroll.scrollY
        val nearBottom = oldOffset + transcriptScroll.height >= transcript.height - dp(30)
        lastTurns = turns.toList(); lastReady = ready
        transcript.removeAllViews()
        waitingLabels.clear()
        if (turns.isEmpty()) {
            transcript.addView(text(context.getString(if (ready) R.string.home_empty_conversation else R.string.home_setup), 14f).apply {
                setTextColor(secondary); setPadding(0, dp(10), 0, dp(10))
            })
            if (!ready) transcript.addView(Button(context).apply {
                setText(R.string.connect_service); isAllCaps = false; minHeight = dp(48)
                setOnClickListener { onConnect() }
            })
        }
        for (turn in turns) {
            bubble(turn.prompt, true)
            if (turn.reply.isNotBlank()) {
                bubble(turn.reply, false).setOnLongClickListener { onRead(turn.reply); true }
                WatchReplyImages.views(context, turn.reply).forEach {
                    transcript.addView(it, LayoutParams(-1, dp(110)).apply { bottomMargin = dp(6) })
                }
            }
            else if (turn.progress.isNotBlank()) bubble(turn.progress, false)
            else if (turn.state.terminal) bubble(context.getString(turn.state.label()), false)
            if (turn.state == TaskState.WAITING_APPROVAL) bubble(context.getString(R.string.approval_help), false)
            if (!turn.state.terminal) {
                val status = bubble(statusText(turn), false).apply {
                    minHeight = dp(48); gravity = Gravity.CENTER_VERTICAL; textSize = 12f; setTextColor(secondary)
                    if (turn.state != TaskState.STOP_REQUESTED) setOnClickListener { onStop(turn) }
                }
                waitingLabels.add(turn to status)
            }
        }
        transcriptScroll.post {
            if (turns.isEmpty()) { transcriptScroll.scrollTo(0, 0); newReply.visibility = GONE }
            else if (resetScroll || nearBottom) { transcriptScroll.fullScroll(View.FOCUS_DOWN); newReply.visibility = GONE }
            else { transcriptScroll.scrollTo(0, oldOffset); newReply.visibility = VISIBLE }
        }
    }
    private fun bubble(value: String, outgoing: Boolean): TextView {
        val row = LinearLayout(context).apply { gravity = if (outgoing) Gravity.END else Gravity.START }
        val message = text(value, 14f).apply {
            setPadding(0, dp(4), 0, dp(4))
            if (outgoing) setTextColor(Color.rgb(151, 224, 207))
            maxWidth = (resources.configuration.screenWidthDp * resources.displayMetrics.density * 0.87f).toInt()
        }
        if (!outgoing) {
            message.text = com.galaxyssi.chat.AgentRichInlineMarkdownRenderer.render(value.replace("![", "["))
            message.movementMethod = android.text.method.LinkMovementMethod.getInstance()
        }
        row.addView(message, LayoutParams(-2, -2))
        transcript.addView(row, LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
        return message
    }
}
