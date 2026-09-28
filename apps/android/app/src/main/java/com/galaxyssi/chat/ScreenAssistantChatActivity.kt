package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.Toast
import java.lang.ref.WeakReference
import java.util.UUID

/** The actual Agent page in a non-modal window, not a second chat implementation. */
class ScreenAssistantChatActivity : MainActivity() {
    private var expanded = false
    private var outputVisible = false
    private var attached = false
    private var lastConversation = ""
    private var latestTurn = ""
    private var latestTurnConversation = ""
    private var captureInFlight = false
    private var automation = false
    private val screenAttachments = hashSetOf<String>()
    private lateinit var resizeButton: ImageButton
    private lateinit var stopButton: ImageButton
    private val layoutListener = android.view.ViewTreeObserver.OnGlobalLayoutListener {
        if (attached) updateContainer()
    }
    private val transcriptObserver = object : androidx.recyclerview.widget.RecyclerView.AdapterDataObserver() {
        override fun onChanged() = revealTranscript()
        override fun onItemRangeInserted(positionStart: Int, itemCount: Int) = revealTranscript()
        override fun onItemRangeChanged(positionStart: Int, itemCount: Int) = revealTranscript()
        override fun onItemRangeRemoved(positionStart: Int, itemCount: Int) = revealTranscript()
        private fun revealTranscript() {
            // A GONE RecyclerView need not trigger a global layout after a data update.
            agentPage.post { if (attached) updateContainer() }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        intent.putExtra(AgentConversationWindows.WINDOW_KEY, WINDOW_KEY)
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        expanded = savedInstanceState?.getBoolean(EXPANDED) ?: false
        outputVisible = savedInstanceState?.getBoolean(OUTPUT) ?: intent.getBooleanExtra(REVEAL, false)
        screenAttachments.addAll(savedInstanceState?.getStringArrayList("screen_attachment_ids").orEmpty())
        screenAttachments.addAll(getSharedPreferences("screen_assistant_composer_v1", MODE_PRIVATE)
            .getStringSet("screen_ids", emptySet()).orEmpty())
        latestTurn = savedInstanceState?.getString("screen_latest_turn").orEmpty()
        latestTurnConversation = savedInstanceState?.getString("screen_latest_conversation").orEmpty()
        automation = savedInstanceState?.getBoolean(AUTOMATION) ?: false
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
        window.decorView.systemUiVisibility = window.decorView.systemUiVisibility and
            (View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY).inv()
        val header = LinearLayout(this).apply {
            id = R.id.screenAssistantChatHeader
            gravity = Gravity.CENTER_VERTICAL
        }
        val summary = findViewById<View>(R.id.agentSessionSummary)
        (summary.parent as ViewGroup).removeView(summary)
        header.addView(summary, LinearLayout.LayoutParams(0, dp(48), 1f))
        listOf(R.id.agentSessionTitleTap, R.id.agentModelSelectionTap).forEach { id ->
            findViewById<View>(id).let { target ->
                target.layoutParams = target.layoutParams.apply { height = dp(24) }
            }
        }
        stopButton = button(R.id.screenAssistantChatStop, R.drawable.ic_screen_prompt_voice_stop,
            R.string.screen_assistant_stop) { stopCurrentTask() }
        resizeButton = button(R.id.screenAssistantChatResize, R.drawable.ic_screen_assistant_expand,
            R.string.screen_assistant_expand) { toggleExpanded() }
        header.addView(stopButton)
        header.addView(button(R.id.screenAssistantChatCapture, R.drawable.ic_agent_screen,
            R.string.screen_assistant_screenshot) { captureTarget() })
        header.addView(resizeButton)
        header.addView(button(R.id.screenAssistantChatCollapse, R.drawable.ic_chevron_down,
            R.string.screen_assistant_collapse) { collapse() })
        agentPage.addView(header, 0, LinearLayout.LayoutParams(-1, dp(48)))
        findViewById<View>(R.id.agentFixedHeader).visibility = View.GONE
        findViewById<View>(R.id.startupConnectingView).apply {
            animate().cancel()
            visibility = View.GONE
        }
        agentGoalInput.clearFocus()
        attached = true
        agentTranscriptAdapter.registerAdapterDataObserver(transcriptObserver)
        window.decorView.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
        consumeOpenRequest()
        updateContainer()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent != null) consumeOpenRequest()
    }

    override fun onResume() {
        super.onResume()
        current = WeakReference(this)
        visible = true
        if (attached) updateContainer()
        GalaxySSIAccessibilityService.refreshScreenAssistant()
    }

    override fun onPause() {
        visible = false
        super.onPause()
        GalaxySSIAccessibilityService.refreshScreenAssistant()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(EXPANDED, expanded)
        outState.putBoolean(OUTPUT, outputVisible)
        outState.putStringArrayList("screen_attachment_ids", ArrayList(screenAttachments))
        outState.putString("screen_latest_turn", latestTurn)
        outState.putString("screen_latest_conversation", latestTurnConversation)
        outState.putBoolean(AUTOMATION, automation)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        attached = false
        if (isAgentTranscriptAdapterInitialized()) agentTranscriptAdapter.unregisterAdapterDataObserver(transcriptObserver)
        window.decorView.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        if (current?.get() === this) { current = null; visible = false }
        super.onDestroy()
    }

    override fun onBackPressed() {
        if (agentActionTrayExpanded || agentComposerTextMode || chatComposerTextMode ||
            featurePage.visibility == View.VISIBLE || chatPage.visibility == View.VISIBLE ||
            activeMainTab != PAGE_AGENT) super.onBackPressed()
        else collapse()
    }

    internal override fun onAgentTurnSubmitted(conversationId: String, turnId: String,
        goal: String, attachments: List<AgentInputAttachment>) {
        latestTurn = turnId
        latestTurnConversation = conversationId
        outputVisible = true
        val screenAnalysis = attachments.any { it.id in screenAttachments }
        screenAttachments.removeAll(attachments.map(AgentInputAttachment::id).toSet())
        saveScreenAttachmentIds()
        val attempt = ScreenAssistantAnalysisRequest().apply {
            this.automation = this@ScreenAssistantChatActivity.automation
            displayQuestion = goal.ifBlank { getString(R.string.screen_assistant_default_goal) }
            this.turnId = turnId
        }
        if (screenAnalysis || automation) PhoneAssistantTaskControl.bind(turnId, attempt)
        GalaxySSIAccessibilityService.trackScreenAssistantTurn(this, conversationId, turnId, attempt)
        updateContainer()
    }

    private fun consumeOpenRequest() {
        outputVisible = outputVisible || intent.getBooleanExtra(REVEAL, false)
        automation = intent.getBooleanExtra(AUTOMATION, automation)
        val draft = intent.getStringExtra(DRAFT).orEmpty()
        val capture = intent.getBooleanExtra(CAPTURE, false)
        intent.removeExtra(DRAFT)
        intent.removeExtra(CAPTURE)
        intent.removeExtra(REVEAL)
        fun ready() {
            if (isFinishing || isDestroyed) return
            if (initialAgentHydrationPending) { handler.postDelayed(::ready, 50L); return }
            if (draft.isNotBlank() && agentGoalInput.text.isNullOrBlank()) {
                agentGoalInput.setText(draft)
                agentGoalInput.setSelection(agentGoalInput.length())
            }
            if (capture && agentInputAttachments.isEmpty() && pendingAgentReplyIndicators.isEmpty()) captureTarget()
            updateContainer()
        }
        ready()
    }

    internal fun toggleExpanded() {
        expanded = !expanded
        outputVisible = true
        updateContainer()
    }

    internal fun collapse() {
        exitAgentComposerTextMode(hideKeyboard = true)
        conversationWindow.save()
        moveTaskToBack(true)
    }

    private fun updateContainer() {
        if (!attached) return
        val conversationId = conversationWindow.conversationId.ifBlank { agentRenderedConversationId }
        if (conversationId.isNotBlank() && conversationId != lastConversation) {
            lastConversation = conversationId
            ScreenAssistantSettings.saveConversation(this, conversationId)
        }
        val otherPage = featurePage.visibility == View.VISIBLE || chatPage.visibility == View.VISIBLE ||
            activeMainTab != PAGE_AGENT
        val showOutput = outputVisible || agentTranscriptAdapter.itemCount > 0 ||
            pendingAgentReplyIndicators.values.any { it.conversationId == conversationId }
        findViewById<View>(R.id.agentOutputViewport).visibility = if (showOutput) View.VISIBLE else View.GONE
        val fill = showOutput || otherPage || expanded
        (mainPage.getChildAt(1).layoutParams as LinearLayout.LayoutParams).let { params ->
            val height = if (fill) 0 else ViewGroup.LayoutParams.WRAP_CONTENT
            val weight = if (fill) 1f else 0f
            if (params.height != height || params.weight != weight) {
                params.height = height; params.weight = weight
                mainPage.getChildAt(1).layoutParams = params
            }
        }
        val pageHeight = if (fill) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT
        if (agentPage.layoutParams.height != pageHeight) agentPage.layoutParams = agentPage.layoutParams.apply { height = pageHeight }
        val metrics = resources.displayMetrics
        val height = ScreenAssistantChatWindowPolicy.height(metrics.heightPixels, dp(1), expanded, fill)
        val attrs = window.attributes
        if (attrs.height != height || attrs.width != metrics.widthPixels - dp(16)) {
            attrs.height = height
            attrs.width = metrics.widthPixels - dp(16)
            attrs.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            attrs.y = dp(8)
            attrs.setFitInsetsTypes(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
            attrs.setFitInsetsIgnoringVisibility(false)
            window.attributes = attrs
        }
        if (resizeButton.tag != expanded) {
            resizeButton.tag = expanded
            resizeButton.setImageResource(if (expanded) R.drawable.ic_screen_assistant_shrink else R.drawable.ic_screen_assistant_expand)
            resizeButton.contentDescription = getString(if (expanded) R.string.screen_assistant_shrink else R.string.screen_assistant_expand)
        }
        stopButton.visibility = if (pendingAgentReplyIndicators.values.any { it.conversationId == conversationId } ||
            PhoneAssistantTaskControl.isBound(latestTurn)) View.VISIBLE else View.GONE
    }

    private fun captureTarget() {
        if (captureInFlight) return
        captureInFlight = true
        val conversation = agentTranscriptStore.activeConversation().id
        navigationContentExecutor.execute {
            val result = runCatching {
                val snapshot = requireNotNull(GalaxySSIAccessibilityService.readTargetUi()) { "No target screen" }
                check(ScreenAssistantEvidencePolicy.shouldCaptureImage(snapshot)) { "Protected screen" }
                PhoneUiScreenshot.capture(this, snapshot.windowId)
            }
            runOnUiThread {
                captureInFlight = false
                if (isDestroyed || isFinishing || conversation != agentTranscriptStore.activeConversation().id) return@runOnUiThread
                result.onSuccess { file ->
                    ScreenAssistantSettings.saveLastCapture(this, file)
                    val name = getString(R.string.screen_assistant_attachment)
                    val attachment = AgentInputAttachment(UUID.randomUUID().toString(),
                        LocalAttachmentUris.forFile(this, file, name, "image/jpeg"), name, "image/jpeg", file.length())
                    agentInputAttachments.add(attachment)
                    screenAttachments.add(attachment.id)
                    saveScreenAttachmentIds()
                    renderAgentInputAttachments()
                }.onFailure { Toast.makeText(this, R.string.screen_assistant_capture_failed, Toast.LENGTH_SHORT).show() }
            }
        }
    }

    private fun stopCurrentTask() {
        val conversation = agentTranscriptStore.activeConversation().id
        val turn = pendingAgentReplyIndicators.values.lastOrNull { it.conversationId == conversation }?.turnId
            ?: latestTurn.takeIf { latestTurnConversation == conversation }.orEmpty()
        if (turn.isBlank()) return
        navigationContentExecutor.execute {
            runCatching { ScreenAssistantTaskCancellation.cancel(applicationContext, conversation, turn, this) }
                .onFailure { runOnUiThread { Toast.makeText(this, R.string.screen_assistant_cancel_failed, Toast.LENGTH_SHORT).show() } }
        }
    }

    private fun saveScreenAttachmentIds() {
        getSharedPreferences("screen_assistant_composer_v1", MODE_PRIVATE).edit()
            .putStringSet("screen_ids", screenAttachments.toList().takeLast(64).toSet()).apply()
    }

    private fun button(id: Int, icon: Int, label: Int, click: () -> Unit) = ImageButton(this).apply {
        this.id = id
        setImageResource(icon)
        imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.text_primary))
        background = ColorDrawable(Color.TRANSPARENT)
        contentDescription = getString(label)
        tooltipText = getString(label)
        setPadding(dp(10), dp(10), dp(10), dp(10))
        layoutParams = LinearLayout.LayoutParams(dp(40), dp(44))
        setOnClickListener { click() }
    }

    companion object {
        internal const val WINDOW_KEY = "screen-assistant-chat"
        private const val REVEAL = "screen_assistant_reveal"
        private const val CAPTURE = "screen_assistant_capture"
        private const val DRAFT = "screen_assistant_draft"
        private const val AUTOMATION = "screen_assistant_automation"
        private const val EXPANDED = "screen_assistant_expanded"
        private const val OUTPUT = "screen_assistant_output"
        private var current: WeakReference<ScreenAssistantChatActivity>? = null
        private var visible = false
        private var captureHidden = false
        internal fun isOpen() = visible && current?.get()?.isDestroyed == false
        internal fun collapseIfOpen() { current?.get()?.takeIf { isOpen() }?.collapse() }
        internal fun hideForCapture() {
            current?.get()?.takeIf { isOpen() }?.let {
                it.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                    .hideSoftInputFromWindow(it.agentGoalInput.windowToken, 0)
                it.window.decorView.visibility = View.INVISIBLE
                captureHidden = true
            }
        }
        internal fun restoreAfterCapture() {
            if (captureHidden) current?.get()?.window?.decorView?.visibility = View.VISIBLE
            captureHidden = false
        }
        internal fun showPhoneApproval(request: ScreenAssistantAnalysisRequest?): Boolean {
            val activity = current?.get()?.takeIf { isOpen() && !it.isFinishing } ?: return false
            val description = request?.approvalDescription?.takeIf { it.isNotBlank() } ?: return false
            android.app.AlertDialog.Builder(activity)
                .setMessage(activity.getString(R.string.screen_assistant_approval, description))
                .setPositiveButton(R.string.screen_assistant_approve) { _, _ -> request.approve() }
                .setNegativeButton(android.R.string.cancel) { _, _ -> request.cancel() }
                .setOnCancelListener { request.cancel() }
                .show()
            return true
        }
        internal fun open(context: Context, conversationId: String, reveal: Boolean = false,
            capture: Boolean = false, draft: String = "", automation: Boolean = false) {
            context.startActivity(Intent(context, ScreenAssistantChatActivity::class.java)
                .putExtra(AgentConversationWindows.WINDOW_KEY, WINDOW_KEY)
                .putExtra(AgentConversationWindows.CONVERSATION, conversationId)
                .putExtra("galaxyssi_open_agent", true)
                .putExtra("galaxyssi_agent_conversation_id", conversationId)
                .putExtra(REVEAL, reveal).putExtra(CAPTURE, capture).putExtra(DRAFT, draft)
                .putExtra(AUTOMATION, automation)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        }
    }
}

internal object ScreenAssistantChatWindowPolicy {
    fun height(screenHeight: Int, density: Int, expanded: Boolean, content: Boolean): Int = when {
        expanded -> (screenHeight - 64 * density).coerceAtLeast(240 * density)
        content -> minOf(440 * density, (screenHeight * 0.62f).toInt())
        else -> WindowManager.LayoutParams.WRAP_CONTENT
    }
}
