package com.galaxyssi.watch

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.Editable
import android.text.InputFilter
import android.text.TextWatcher
import android.view.*
import android.widget.*
import com.galaxyssi.chat.ui.AgentComposerUiPolicy
import com.galaxyssi.chat.ui.ParagraphSelectingTextView

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
    private val onConnect: () -> Unit,
    private val onStopReading: () -> Boolean = { false },
    private val onReadFrom: ((String, String, Int) -> Unit)? = null
) : LinearLayout(context) {
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private val secondary = Color.rgb(165, 171, 182)
    private fun text(value: String, size: Float = 14f) = TextView(context).apply {
        this.text = value; textSize = size; setTextColor(Color.WHITE); includeFontPadding = false
    }
    private var wakeStatus = ""
    fun setWakeStatus(value: String) { wakeStatus = value; updateClock() }
    private fun updateClock() {
        val time = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date())
        clockLabel.text = if (wakeStatus.isBlank()) time else "$time · $wakeStatus"
    }
    private val clockLabel = text("", 10f).apply { gravity = Gravity.CENTER; setTextColor(secondary) }
    private val heading = text("", 11f)
    private val model = text("", 9f).apply { setTextColor(secondary) }
    private val transcript = LinearLayout(context).apply { orientation = VERTICAL }
    private val transcriptScroll = object : ScrollView(context) {
        private var swallow = false
        private var downY = 0f
        private val stopDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent) = true
            override fun onDoubleTap(event: MotionEvent): Boolean {
                swallow = onStopReading()
                return swallow
            }
        })
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_DOWN) { swallow = false; downY = event.y; scrollAnimation?.cancel() }
            if (event.actionMasked == MotionEvent.ACTION_MOVE &&
                kotlin.math.abs(event.y - downY) > ViewConfiguration.get(context).scaledTouchSlop) pauseSpeechFollow()
            stopDetector.onTouchEvent(event)
            if (swallow) {
                val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
                super.dispatchTouchEvent(cancel)
                cancel.recycle()
                if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) swallow = false
                return true
            }
            return super.dispatchTouchEvent(event)
        }
        override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
            if (event.action == MotionEvent.ACTION_SCROLL) {
                pauseSpeechFollow()
                val axis = if (event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) MotionEvent.AXIS_SCROLL else MotionEvent.AXIS_VSCROLL
                scrollBy(0, (-event.getAxisValue(axis) * ViewConfiguration.get(context).scaledVerticalScrollFactor).toInt())
                return true
            }
            return super.dispatchGenericMotionEvent(event)
        }
    }.apply {
        isFillViewport = true; isVerticalScrollBarEnabled = true
        addView(transcript, LayoutParams(-1, -2))
    }
    private val newReply = text(context.getString(R.string.new_reply), 11f).apply {
        gravity = Gravity.CENTER; setTextColor(Color.rgb(101, 217, 203)); visibility = GONE
        minHeight = dp(24)
        setOnClickListener {
            if (speaking != null) resumeSpeechFollow()
            else { scrollToReplyStart(); visibility = GONE }
        }
    }
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
    private var lastTurns = emptyList<WatchTask>()
    private var lastReady: Boolean? = null
    private data class RenderedTurn(val task: WatchTask, val container: LinearLayout, val status: TextView?, val reply: TextView?)
    private val renderedTurns = mutableMapOf<String, RenderedTurn>()
    private data class Speaking(val id: String, val start: Int, val end: Int)
    private var speaking: Speaking? = null
    private var followSpeech = true
    private var manualScroll = false
    private var scrollAnimation: android.animation.ValueAnimator? = null
    private var renderRevision = 0
    private var highlighted: TextView? = null
    private val speechColor = android.text.style.ForegroundColorSpan(Color.rgb(151, 224, 207))
    private val waitingLabels = mutableListOf<Pair<WatchTask, TextView>>()
    private val ticker = object : Runnable {
        override fun run() {
            updateClock()
            waitingLabels.forEach { (task, label) ->
                label.text = statusText(task)
            }
            postDelayed(this, 1000)
        }
    }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); post(ticker) }
    override fun onDetachedFromWindow() { removeCallbacks(ticker); scrollAnimation?.cancel(); super.onDetachedFromWindow() }

    init {
        setOnApplyWindowInsetsListener { _, insets ->
            keyboardVisible = insets.isVisible(WindowInsets.Type.ime())
            input.setHint(if (keyboardVisible) R.string.message_hint else R.string.composer_hint)
            insets
        }
        orientation = VERTICAL; setBackgroundColor(Color.BLACK)
        isFocusableInTouchMode = true
        val headerInset = (resources.configuration.screenWidthDp * 0.125f).toInt().coerceAtLeast(24)
        val transcriptInset = (resources.configuration.screenWidthDp * 0.055f).toInt().coerceAtLeast(10)
        val composerInset = (resources.configuration.screenWidthDp * 0.15f).toInt().coerceAtLeast(28)
        setPadding(0, dp(10), 0, dp(18))
        addView(clockLabel, LayoutParams(-1, dp(12)))
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
                    // Center the shorter subtitle under the full GalaxySSI wordmark.
                    gravity = Gravity.CENTER_HORIZONTAL
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
        addView(header, LayoutParams(-1, -2).apply { topMargin = dp(1) })
        addView(FrameLayout(context).apply {
            addView(transcriptScroll, FrameLayout.LayoutParams(-1, -1))
            addView(newReply, FrameLayout.LayoutParams(-1, dp(24), Gravity.BOTTOM))
        }, LayoutParams(-1, 0, 1f).apply { leftMargin = dp(transcriptInset); rightMargin = dp(transcriptInset) })
        addView(LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(input, LayoutParams(0, -2, 1f))
            addView(actionSlot, LayoutParams(dp(40), dp(36)))
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
        val state = AgentComposerUiPolicy.resolve(input.text.isNotBlank(), textModeActive = true, actionTrayRequested = false)
        sendAction.visibility = if (state.showSendButton) VISIBLE else GONE
        menuAction.visibility = if (state.showMoreButton) VISIBLE else GONE
        sendAction.isEnabled = !busy
        menuAction.isEnabled = !busy
    }
    fun sending(value: Boolean) { busy = value; input.isEnabled = !value; refreshAction() }
    fun setDraft(value: String) { if (input.text.toString() != value) input.setText(value) }
    private fun statusText(task: WatchTask): String {
        val seconds = ((System.currentTimeMillis() - task.sourceId) / 1000).coerceAtLeast(0)
        val status = context.getString(R.string.waiting_elapsed, context.getString(task.state.label()), seconds)
        return if (task.state == TaskState.STOP_REQUESTED) status else "$status\n${context.getString(R.string.stop_task)}"
    }

    fun update(turns: List<WatchTask>, modelName: String, ready: Boolean, resetScroll: Boolean = false) {
        val title = turns.firstOrNull()?.prompt?.take(18) ?: context.getString(R.string.new_conversation)
        if (heading.text.toString() != title) heading.text = title
        if (model.text.toString() != modelName) model.text = modelName
        if (turns == lastTurns && ready == lastReady && !resetScroll) return
        val oldOffset = transcriptScroll.scrollY
        val changedTurn = turns.lastOrNull()?.id != lastTurns.lastOrNull()?.id
        if (resetScroll || changedTurn) { stopSpeaking(); followSpeech = true; manualScroll = false }
        val revision = ++renderRevision
        lastTurns = turns.toList(); lastReady = ready
        if (turns.isEmpty() || renderedTurns.isEmpty()) transcript.removeAllViews()
        val ids = turns.map { it.id }.toSet()
        renderedTurns.keys.filter { it !in ids }.forEach { id ->
            renderedTurns.remove(id)?.let { transcript.removeView(it.container) }
        }
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
        turns.forEachIndexed { index, turn ->
            var row = renderedTurns[turn.id]
            if (row?.task != turn) {
                row?.let { transcript.removeView(it.container) }
                val container = LinearLayout(context).apply { orientation = VERTICAL }
                bubble(container, turn.prompt, true)
                var replyView: TextView? = null
                if (turn.reply.isNotBlank()) {
                    replyView = bubble(container, turn.reply, false, readable = true, taskId = turn.id)
                    WatchReplyImages.views(context, turn.reply).forEach {
                        container.addView(it, LayoutParams(-1, dp(110)).apply { bottomMargin = dp(6) })
                    }
                } else if (turn.progress.isNotBlank()) bubble(container, turn.progress, false)
                else if (turn.state.terminal) bubble(container, context.getString(turn.state.label()), false)
                if (turn.state == TaskState.WAITING_APPROVAL) bubble(container, context.getString(R.string.approval_help), false)
                val status = if (!turn.state.terminal) bubble(container, statusText(turn), false).apply {
                    minHeight = dp(48); gravity = Gravity.CENTER_VERTICAL; textSize = 12f; setTextColor(secondary)
                    if (turn.state != TaskState.STOP_REQUESTED) setOnClickListener { onStop(turn) }
                } else null
                row = RenderedTurn(turn, container, status, replyView)
                renderedTurns[turn.id] = row
            }
            val rendered = requireNotNull(row)
            if (transcript.indexOfChild(rendered.container) != index) {
                transcript.removeView(rendered.container)
                transcript.addView(rendered.container, index, LayoutParams(-1, -2))
            }
            rendered.status?.let { waitingLabels.add(turn to it) }
        }
        transcriptScroll.post {
            if (revision != renderRevision) return@post
            if (turns.isEmpty()) { transcriptScroll.scrollTo(0, 0); newReply.visibility = GONE }
            else if ((resetScroll || changedTurn) && !manualScroll && speaking == null) {
                // One initial placement at the new turn; generation never chases the growing bottom.
                transcriptScroll.scrollTo(0, renderedTurns[turns.last().id]?.container?.top ?: 0)
                newReply.visibility = GONE
            } else if (speaking != null) applySpeaking(scroll = false)
            else if (!manualScroll) transcriptScroll.scrollTo(0, oldOffset)
        }
    }
    private fun pauseSpeechFollow() {
        scrollAnimation?.cancel()
        manualScroll = true
        followSpeech = false
        if (speaking != null) {
            newReply.setText(R.string.follow_speech)
            newReply.visibility = VISIBLE
        }
    }
    fun resumeSpeechFollow() {
        manualScroll = false
        followSpeech = true
        newReply.visibility = GONE
        applySpeaking(scroll = true, force = true)
    }
    fun showSpeaking(taskId: String, start: Int, end: Int) {
        if (renderedTurns[taskId]?.reply == null) return
        speaking = Speaking(taskId, start, end)
        if (!followSpeech) { newReply.setText(R.string.follow_speech); newReply.visibility = VISIBLE }
        applySpeaking(scroll = followSpeech)
    }
    fun stopSpeaking() {
        scrollAnimation?.cancel()
        speaking = null
        (highlighted?.text as? android.text.Spannable)?.removeSpan(speechColor)
        highlighted = null
        newReply.visibility = GONE
    }
    private fun scrollToReplyStart() {
        val row = lastTurns.lastOrNull()?.id?.let(renderedTurns::get) ?: return
        val reply = row.reply ?: return
        val rect = android.graphics.Rect(0, 0, reply.width, 1)
        transcript.offsetDescendantRectToMyCoords(reply, rect)
        animateScroll(rect.top)
    }
    private fun animateScroll(target: Int) {
        scrollAnimation?.cancel()
        val end = target.coerceIn(0, (transcript.height - transcriptScroll.height).coerceAtLeast(0))
        scrollAnimation = android.animation.ValueAnimator.ofInt(transcriptScroll.scrollY, end).apply {
            duration = 220
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener { transcriptScroll.scrollTo(0, it.animatedValue as Int) }
            start()
        }
    }
    private fun applySpeaking(scroll: Boolean, force: Boolean = false) {
        val range = speaking ?: return
        val message = renderedTurns[range.id]?.reply ?: return
        (highlighted?.text as? android.text.Spannable)?.removeSpan(speechColor)
        val value = message.text as? android.text.Spannable ?: return
        val start = range.start.coerceIn(0, value.length)
        val end = range.end.coerceIn(start, value.length)
        if (end <= start) return
        value.setSpan(speechColor, start, end, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        highlighted = message
        if (!scroll) return
        message.post {
            if (speaking != range || !followSpeech || !isAttachedToWindow) return@post
            val layout = message.layout ?: return@post
            val first = layout.getLineForOffset(start)
            val last = layout.getLineForOffset(end - 1)
            val rect = android.graphics.Rect(0, message.totalPaddingTop + layout.getLineTop(first),
                message.width, message.totalPaddingTop + layout.getLineBottom(last))
            transcript.offsetDescendantRectToMyCoords(message, rect)
            val top = transcriptScroll.scrollY
            val safeBottom = top + transcriptScroll.height - dp(12)
            if (force || rect.top < top || rect.bottom > safeBottom) {
                // Keep a little context above the sentence; no word-by-word movement or end snap.
                animateScroll((rect.top - dp(8)).coerceAtLeast(0))
            }
        }
    }
    private fun bubble(parent: LinearLayout, value: String, outgoing: Boolean, readable: Boolean = false, taskId: String = ""): TextView {
        val row = LinearLayout(context).apply { gravity = if (outgoing) Gravity.END else Gravity.START }
        val message = (if (readable) ParagraphSelectingTextView(context).apply {
            setOnParagraphDoubleTapListener { selection ->
                onReadFrom?.invoke(taskId, selection.sourceText, selection.startOffset)
                    ?: onRead(selection.sourceText.substring(selection.startOffset))
            }
        } else TextView(context)).apply {
            text = value; textSize = 14f; setTextColor(Color.WHITE); includeFontPadding = false
            setPadding(0, dp(4), 0, dp(4))
            if (outgoing) setTextColor(Color.rgb(151, 224, 207))
            maxWidth = (resources.configuration.screenWidthDp * resources.displayMetrics.density * 0.89f).toInt()
        }
        if (!outgoing) {
            message.text = WatchRichReply.render(value)
            if (readable) {
                message.setTextIsSelectable(true)
                var paragraphAnchor = 0
                var expandOnRelease = false
                message.setOnTouchListener { _, event ->
                    if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                        paragraphAnchor = message.getOffsetForPosition(event.x, event.y)
                    }
                    if (event.actionMasked == MotionEvent.ACTION_UP && expandOnRelease) {
                        expandOnRelease = false
                        val anchor = paragraphAnchor
                        message.post {
                            val selectable = message.text as? android.text.Spannable
                            if (selectable != null && message.hasSelection()) {
                                val range = com.galaxyssi.chat.ui.ParagraphSelectionPolicy.rangeAt(selectable, anchor)
                                android.text.Selection.setSelection(selectable, range.start, range.endExclusive)
                            }
                        }
                    }
                    false
                }
                message.customSelectionActionModeCallback = object : ActionMode.Callback {
                    override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                        expandOnRelease = true
                        pauseSpeechFollow(); onStopReading(); return true
                    }
                    override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
                    override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                        if (item.itemId == android.R.id.copy) {
                            val start = minOf(message.selectionStart, message.selectionEnd)
                            val end = maxOf(message.selectionStart, message.selectionEnd)
                            if (start >= 0 && end > start) WatchClipboardHistory.remember(message.text.subSequence(start, end).toString())
                        }
                        return false
                    }
                    override fun onDestroyActionMode(mode: ActionMode) { expandOnRelease = false }
                }
            } else message.movementMethod = android.text.method.LinkMovementMethod.getInstance()
        }
        row.addView(message, LayoutParams(-2, -2))
        parent.addView(row, LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
        return message
    }
}
