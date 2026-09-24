package com.galaxyssi.chat

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max

internal object ScreenAssistantSettings {
    private const val PREFS = "screen_assistant_v1"
    private const val ENABLED = "enabled"
    private const val CONVERSATION = "conversation"
    private const val LAST_TURN = "last_turn"
    private const val PENDING_FILE = "pending_file"
    private const val PENDING_QUESTION = "pending_question"
    private const val TARGET_ID = "target_id"
    private const val TARGET_NAME = "target_name"
    private const val MODEL_ID = "model_id"
    private const val LAST_CAPTURE = "last_capture"
    private const val BUBBLE_X = "bubble_x"
    private const val BUBBLE_Y = "bubble_y"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun enabled(context: Context): Boolean = prefs(context).getBoolean(ENABLED, false)
    fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(ENABLED, value).apply()
        GalaxySSIAccessibilityService.refreshScreenAssistant()
    }
    fun conversation(context: Context): String = prefs(context).getString(CONVERSATION, "").orEmpty()
    fun saveConversation(context: Context, id: String) = prefs(context).edit().putString(CONVERSATION, id).apply()
    fun lastTurn(context: Context): String = prefs(context).getString(LAST_TURN, "").orEmpty()
    fun saveLastTurn(context: Context, id: String) = prefs(context).edit().putString(LAST_TURN, id).apply()
    data class Target(val id: String, val name: String, val modelId: String)
    fun target(context: Context): Target = Target(
        prefs(context).getString(TARGET_ID, "").orEmpty(),
        prefs(context).getString(TARGET_NAME, "").orEmpty(),
        prefs(context).getString(MODEL_ID, "").orEmpty()
    )
    fun setTarget(context: Context, target: Target) = prefs(context).edit()
        .putString(TARGET_ID, target.id).putString(TARGET_NAME, target.name)
        .putString(MODEL_ID, target.modelId).apply()
    fun saveLastCapture(context: Context, file: File) = prefs(context).edit()
        .putString(LAST_CAPTURE, file.canonicalPath).apply()
    fun lastCapture(context: Context): File? = validatedCaptureFile(
        context, prefs(context).getString(LAST_CAPTURE, "").orEmpty()
    )
    private fun validatedCaptureFile(context: Context, path: String): File? {
        if (path.isBlank()) return null
        val root = File(context.filesDir, "agent-rich-output-v2/screen-assistant").canonicalFile
        val file = runCatching { File(path).canonicalFile }.getOrNull() ?: return null
        return file.takeIf { it.isFile && it.toPath().startsWith(root.toPath()) }
    }
    fun pending(context: Context): Pair<File, String>? {
        val path = prefs(context).getString(PENDING_FILE, "").orEmpty()
        return validatedCaptureFile(context, path)
            ?.let { it to prefs(context).getString(PENDING_QUESTION, "").orEmpty() }
    }
    fun savePending(context: Context, file: File, question: String) = prefs(context).edit()
        .putString(PENDING_FILE, file.canonicalPath).putString(PENDING_QUESTION, question).apply()
    fun clearPending(context: Context) = prefs(context).edit()
        .remove(PENDING_FILE).remove(PENDING_QUESTION).apply()
    fun bubblePosition(context: Context): Pair<Int, Int> =
        prefs(context).getInt(BUBBLE_X, -1) to prefs(context).getInt(BUBBLE_Y, -1)
    fun saveBubblePosition(context: Context, x: Int, y: Int) =
        prefs(context).edit().putInt(BUBBLE_X, x).putInt(BUBBLE_Y, y).apply()
}

internal object ScreenAssistantVisibilityPolicy {
    fun shouldShow(
        enabled: Boolean,
        sdk: Int,
        appForeground: Boolean,
        locked: Boolean,
        capturing: Boolean,
        foregroundPackage: String,
        ownPackage: String
    ): Boolean = enabled && sdk >= Build.VERSION_CODES.R && !appForeground && !locked &&
        !capturing && foregroundPackage != ownPackage
}

/** The accessibility overlay is small; the other app stays touchable outside its bounds. */
internal class ScreenAssistantOverlay(private val service: GalaxySSIAccessibilityService) {
    private val windowManager = service.getSystemService(WindowManager::class.java)
    private val keyguard = service.getSystemService(KeyguardManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "screen-assistant-io") }
    private val transcriptStore by lazy { AgentTranscriptStore(service.applicationContext, "main") }
    private val density = service.resources.displayMetrics.density
    private var foregroundPackage = ""
    private var bubble: View? = null
    private var bubbleBadge: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var menu: View? = null
    private var panel: View? = null
    private var crop: View? = null
    private var panelText: TextView? = null
    private var panelTitle: TextView? = null
    private var expanded = false
    private var capturePending = false
    private var activeTurn = ScreenAssistantSettings.lastTurn(service)
    private var currentText = ""
    private var currentStatus = service.getString(R.string.screen_assistant_ready)
    private var pollGeneration = 0
    private var closed = false

    private fun dp(value: Int) = (value * density + 0.5f).toInt()
    private fun screenWidth() = service.resources.displayMetrics.widthPixels
    private fun screenHeight() = service.resources.displayMetrics.heightPixels
    private fun rounded(color: Int, radius: Int = 18, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
        stroke?.let { setStroke(dp(1), it) }
    }
    private fun params(width: Int, height: Int, gravity: Int, focusable: Boolean = false) =
        WindowManager.LayoutParams(
            width, height, WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                (if (focusable) 0 else WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE),
            PixelFormat.TRANSLUCENT
        ).apply { this.gravity = gravity }

    fun onForegroundPackage(value: String) {
        if (value.isNotBlank() && (value != service.packageName || AppForegroundTracker.isForeground())) {
            foregroundPackage = value
        }
        refresh()
    }

    fun refresh() {
        if (closed) return
        val visible = ScreenAssistantVisibilityPolicy.shouldShow(
            enabled = ScreenAssistantSettings.enabled(service),
            sdk = Build.VERSION.SDK_INT,
            appForeground = AppForegroundTracker.isForeground(),
            locked = keyguard.isKeyguardLocked,
            capturing = capturePending,
            foregroundPackage = foregroundPackage,
            ownPackage = service.packageName
        )
        if (visible) ensureBubble() else hideAll()
    }

    fun close() {
        closed = true
        pollGeneration++
        hideAll()
        worker.shutdown()
    }

    fun retryPending() {
        val (file, question) = ScreenAssistantSettings.pending(service) ?: return
        if (AgentConversationWindows.screenAssistantRunner() != null) submit(file, question)
    }

    private fun add(view: View, params: WindowManager.LayoutParams): Boolean =
        runCatching { windowManager.addView(view, params) }.isSuccess

    private fun remove(view: View?) {
        if (view != null) runCatching { windowManager.removeViewImmediate(view) }
    }

    private fun hideAll() {
        remove(menu); menu = null
        remove(panel); panel = null
        remove(crop); crop = null
        remove(bubble); bubble = null
        bubbleBadge = null
        bubbleParams = null
        panelText = null
        panelTitle = null
    }

    private fun ensureBubble() {
        if (bubble != null) return
        val size = dp(58)
        val logo = ImageView(service).apply {
            setImageResource(R.drawable.galaxyssi_mark_large)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = service.getString(R.string.screen_assistant_capture)
        }
        val root = FrameLayout(service).apply {
            background = rounded(Color.WHITE, 29, 0xFFD9E5E1.toInt())
            elevation = dp(8).toFloat()
            addView(logo, FrameLayout.LayoutParams(dp(43), dp(43), Gravity.CENTER))
            val badge = View(service)
            addView(badge, FrameLayout.LayoutParams(dp(12), dp(12), Gravity.TOP or Gravity.END).apply {
                topMargin = dp(2)
                rightMargin = dp(2)
            })
            bubbleBadge = badge
            setOnTouchListener(BubbleTouchListener())
        }
        val (savedX, savedY) = ScreenAssistantSettings.bubblePosition(service)
        val layout = params(size, size, Gravity.TOP or Gravity.START).apply {
            x = savedX.takeIf { it >= 0 } ?: (screenWidth() - size - dp(12))
            y = savedY.takeIf { it >= 0 } ?: screenHeight() / 2
        }
        if (add(root, layout)) {
            bubble = root
            bubbleParams = layout
            updateBubbleBadge()
        }
    }

    private fun updateBubbleBadge() {
        val color = when (currentStatus) {
            service.getString(R.string.screen_assistant_ready) -> null
            service.getString(R.string.screen_assistant_analyzing) -> 0xFFE2A430.toInt()
            service.getString(R.string.screen_assistant_completed) -> 0xFF169F75.toInt()
            else -> 0xFFD95353.toInt()
        }
        bubbleBadge?.apply {
            visibility = if (color == null) View.GONE else View.VISIBLE
            if (color != null) background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
                setStroke(dp(2), Color.WHITE)
            }
        }
        bubble?.contentDescription = "${service.getString(R.string.screen_assistant_title)}: $currentStatus"
    }

    private inner class BubbleTouchListener : View.OnTouchListener {
        private val slop = ViewConfiguration.get(service).scaledTouchSlop
        private var startX = 0f
        private var startY = 0f
        private var windowX = 0
        private var windowY = 0
        private var moved = false
        private var longPressed = false
        private val openMenu = Runnable { longPressed = true; showMenu() }

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val layout = bubbleParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX; startY = event.rawY
                    windowX = layout.x; windowY = layout.y
                    moved = false; longPressed = false
                    handler.postDelayed(openMenu, ViewConfiguration.getLongPressTimeout().toLong())
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - startX
                    val dy = event.rawY - startY
                    if (abs(dx) > slop || abs(dy) > slop) {
                        moved = true
                        handler.removeCallbacks(openMenu)
                        dismissMenu()
                    }
                    if (moved) {
                        layout.x = (windowX + dx.toInt()).coerceIn(0, max(0, screenWidth() - dp(58)))
                        layout.y = (windowY + dy.toInt()).coerceIn(dp(24), max(dp(24), screenHeight() - dp(100)))
                        runCatching { windowManager.updateViewLayout(view, layout) }
                    }
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(openMenu)
                    if (moved) ScreenAssistantSettings.saveBubblePosition(service, layout.x, layout.y)
                    else if (!longPressed) {
                        if (panel != null) dismissPanel() else captureScreen()
                    }
                }
                MotionEvent.ACTION_CANCEL -> handler.removeCallbacks(openMenu)
            }
            return true
        }
    }

    private fun action(label: Int, click: () -> Unit): TextView = TextView(service).apply {
        text = service.getString(label)
        textSize = 14f
        setTextColor(0xFF20342D.toInt())
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), 0, dp(16), 0)
        minHeight = dp(48)
        setOnClickListener { dismissMenu(); click() }
    }

    private fun showMenu() {
        dismissMenu()
        val list = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(Color.WHITE, 16, 0xFFE0E8E5.toInt())
            elevation = dp(10).toFloat()
            addView(action(R.string.screen_assistant_capture) { captureScreen() })
            addView(action(R.string.screen_assistant_ask) { showQuestionInput() })
            addView(action(R.string.screen_assistant_crop) { showCrop() })
            addView(action(R.string.screen_assistant_last_result) { showPanel() })
            addView(action(R.string.screen_assistant_pause) {
                ScreenAssistantSettings.setEnabled(service, false)
            })
        }
        val layout = params(dp(215), dp(240), Gravity.TOP or Gravity.START).apply {
            x = (bubbleParams?.x ?: 0).coerceAtMost(max(0, screenWidth() - dp(225)))
            y = ((bubbleParams?.y ?: 0) - dp(250)).coerceAtLeast(dp(30))
        }
        if (add(list, layout)) menu = list
    }

    private fun dismissMenu() { remove(menu); menu = null }

    private fun showQuestionInput() = showPrompt(R.string.screen_assistant_send) { question ->
        handler.postDelayed({ captureScreen(question = question) }, 180L)
    }

    private fun showFollowUpInput() = showPrompt(R.string.screen_assistant_follow_up_send) { question ->
        submitFollowUp(question)
    }

    private fun showPrompt(sendLabel: Int, onSubmit: (String) -> Unit) {
        dismissPanel()
        val input = EditText(service).apply {
            hint = service.getString(R.string.screen_assistant_question_hint)
            textSize = 15f
            minLines = 2
            maxLines = 4
        }
        val content = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = rounded(Color.WHITE, 18)
            addView(input)
            addView(action(sendLabel) {
                val question = input.text.toString().trim()
                if (question.isBlank() && sendLabel == R.string.screen_assistant_follow_up_send) {
                    input.error = service.getString(R.string.screen_assistant_question_hint)
                    return@action
                }
                service.getSystemService(InputMethodManager::class.java)
                    .hideSoftInputFromWindow(input.windowToken, 0)
                dismissPanel()
                onSubmit(question)
            })
        }
        val layout = params(screenWidth() - dp(32), dp(180), Gravity.TOP or Gravity.CENTER_HORIZONTAL, true).apply {
            y = dp(100)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        if (add(content, layout)) {
            panel = content
            input.requestFocus()
            handler.postDelayed({
                service.getSystemService(InputMethodManager::class.java)
                    .showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
            }, 100)
        }
    }

    private fun showCrop() {
        dismissPanel()
        val view = CropSelectionView(service) { region ->
            remove(crop); crop = null
            if (region != null) captureScreen(region = region)
        }
        val layout = params(-1, -1, Gravity.TOP or Gravity.START)
        if (add(view, layout)) crop = view
    }

    private fun captureScreen(question: String = "", region: Rect? = null) {
        if (capturePending) { showPanel(); return }
        if (ScreenAssistantSettings.pending(service) != null) {
            update(service.getString(R.string.screen_assistant_open_app), "", true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || keyguard.isKeyguardLocked ||
            foregroundPackage == service.packageName) {
            update(service.getString(R.string.screen_assistant_unavailable), "", true)
            return
        }
        capturePending = true
        dismissMenu(); dismissPanel()
        remove(bubble); bubble = null; bubbleParams = null
        bubbleBadge = null
        handler.postDelayed({
            if (closed || !ScreenAssistantSettings.enabled(service)) {
                capturePending = false
                return@postDelayed
            }
            runCatching { service.takeScreenshot(Display.DEFAULT_DISPLAY, { task -> handler.post(task) },
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                        capturePending = false
                        refresh()
                        val buffer = result.hardwareBuffer
                        val bitmap = runCatching { try {
                            Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false)
                        } finally { buffer.close() } }.getOrNull()
                        if (bitmap == null) {
                            update(service.getString(R.string.screen_assistant_capture_failed), "", true)
                            return
                        }
                        update(service.getString(R.string.screen_assistant_analyzing), "", true)
                        persistAndSubmit(bitmap, region, question)
                    }
                    override fun onFailure(errorCode: Int) {
                        Log.w("ScreenAssistant", "Screenshot unavailable code=$errorCode")
                        capturePending = false
                        refresh()
                        update(service.getString(R.string.screen_assistant_capture_failed), "", true)
                    }
                }) }.onFailure {
                capturePending = false
                refresh()
                update(service.getString(R.string.screen_assistant_capture_failed), "", true)
            }
        }, 220)
    }

    private fun persistAndSubmit(bitmap: Bitmap, region: Rect?, question: String) {
        if (closed) { bitmap.recycle(); return }
        worker.execute {
            val file = runCatching {
                val clipped = if (region != null) {
                    val scaleX = bitmap.width.toFloat() / screenWidth()
                    val scaleY = bitmap.height.toFloat() / screenHeight()
                    val left = (region.left * scaleX).toInt().coerceIn(0, bitmap.width - 1)
                    val top = (region.top * scaleY).toInt().coerceIn(0, bitmap.height - 1)
                    val right = (region.right * scaleX).toInt().coerceIn(left + 1, bitmap.width)
                    val bottom = (region.bottom * scaleY).toInt().coerceIn(top + 1, bitmap.height)
                    Bitmap.createBitmap(bitmap, left, top, right - left, bottom - top)
                } else bitmap
                val target = File(service.filesDir, "agent-rich-output-v2/screen-assistant/${UUID.randomUUID()}.jpg")
                check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
                FileOutputStream(target).use { output -> check(clipped.compress(Bitmap.CompressFormat.JPEG, 88, output)) }
                if (clipped !== bitmap) clipped.recycle()
                target
            }.getOrNull()
            bitmap.recycle()
            handler.post {
                if (file == null || closed) {
                    file?.delete()
                    update(service.getString(R.string.screen_assistant_capture_failed), "", true)
                } else {
                    ScreenAssistantSettings.saveLastCapture(service, file)
                    submit(file, question)
                }
            }
        }
    }

    private fun submitFollowUp(question: String) {
        val runner = AgentConversationWindows.screenAssistantRunner()
        val conversationId = ScreenAssistantSettings.conversation(service)
        if (runner == null || conversationId.isBlank() || runner.agentTranscriptStore.conversation(conversationId) == null) {
            update(service.getString(R.string.screen_assistant_open_app), "", true)
            return
        }
        runCatching {
            runner.submitAgentGoal(
                pendingVoiceConversationId = conversationId,
                goalOverride = question,
                onTurnCreated = { turn ->
                    activeTurn = turn
                    ScreenAssistantSettings.saveLastTurn(service, turn)
                    currentText = ""
                    update(service.getString(R.string.screen_assistant_analyzing), "", true)
                    beginPolling(turn)
                }
            )
        }.onFailure { update(service.getString(R.string.screen_assistant_open_app), "", true) }
    }

    private fun submit(file: File, question: String) {
        val runner = AgentConversationWindows.screenAssistantRunner()
        if (runner == null) {
            ScreenAssistantSettings.savePending(service, file, question)
            update(service.getString(R.string.screen_assistant_open_app), "", true)
            return
        }
        val target = ScreenAssistantSettings.target(service)
        if (target.id.isNotBlank() && runner.mobileNativeAgent.snapshot().callableTargets.none {
            it.id == target.id && AgentConnectorRouteSelector.isDeliverable(it)
        }) {
            ScreenAssistantSettings.savePending(service, file, question)
            update(service.getString(R.string.screen_assistant_target_unavailable), "", true)
            return
        }
        runCatching {
            val store = runner.agentTranscriptStore
            val conversationId = ScreenAssistantSettings.conversation(service)
                .takeIf { it.isNotBlank() && store.conversation(it) != null }
                ?: store.createAgentConversation(service.getString(R.string.screen_assistant_conversation)).id.also {
                    ScreenAssistantSettings.saveConversation(service, it)
                }
            if (target.id.isBlank()) {
                AgentModelSelectionSettings.selectAutoForConversation(service, conversationId)
                store.setSelectedModelOrAgent(conversationId,
                    service.getString(R.string.agent_model_selection_automatic))
            } else {
                AgentModelSelectionSettings.selectManual(
                    service, conversationId, target.id, target.modelId, target.name,
                    rememberAsDefault = false
                )
                store.setSelectedModelOrAgent(conversationId, target.name)
            }
            val name = service.getString(R.string.screen_assistant_attachment)
            val attachment = AgentInputAttachment(
                id = UUID.randomUUID().toString(),
                uri = LocalAttachmentUris.forFile(service, file, name, "image/jpeg"),
                displayName = name,
                mimeType = "image/jpeg",
                sizeBytes = file.length()
            )
            val goal = question.ifBlank { service.getString(R.string.screen_assistant_default_goal) }
            runner.submitAgentGoal(
                pendingVoiceConversationId = conversationId,
                goalOverride = goal,
                attachmentsOverride = listOf(attachment),
                onTurnCreated = { turn ->
                    ScreenAssistantSettings.clearPending(service)
                    activeTurn = turn
                    ScreenAssistantSettings.saveLastTurn(service, turn)
                    currentText = ""
                    update(service.getString(R.string.screen_assistant_analyzing), "", false)
                    beginPolling(turn)
                }
            )
        }.onFailure {
            ScreenAssistantSettings.savePending(service, file, question)
            update(service.getString(R.string.screen_assistant_open_app), "", true)
        }
    }

    private fun beginPolling(turn: String) {
        val generation = ++pollGeneration
        val started = SystemClock.elapsedRealtime()
        var lastReply = ""
        var lastReplyChangeAt = 0L
        fun poll() {
            if (closed || generation != pollGeneration) return
            worker.execute {
                val entries = runCatching { transcriptStore.entriesForTurn(turn) }
                    .getOrDefault(emptyList())
                handler.post {
                    if (closed || generation != pollGeneration) return@post
                    val reply = entries.lastOrNull { it.role == AgentTranscriptRole.ASSISTANT && it.text.isNotBlank() }
                    val progress = entries.lastOrNull { it.role == AgentTranscriptRole.PROCESS && it.text.isNotBlank() }
                    if (reply != null && reply.text != lastReply) {
                        lastReply = reply.text
                        lastReplyChangeAt = SystemClock.elapsedRealtime()
                    }
                    when {
                        reply != null -> update(
                            service.getString(if (SystemClock.elapsedRealtime() - lastReplyChangeAt >= 6_000L)
                                R.string.screen_assistant_completed else R.string.screen_assistant_analyzing),
                            reply.text, false
                        )
                        progress != null -> update(service.getString(R.string.screen_assistant_analyzing), progress.text, false)
                    }
                    val replySettled = reply != null && SystemClock.elapsedRealtime() - lastReplyChangeAt >= 6_000L
                    if (!replySettled && SystemClock.elapsedRealtime() - started < 30 * 60_000L) {
                        handler.postDelayed(::poll, 1500L)
                    }
                }
            }
        }
        handler.postDelayed(::poll, 600L)
    }

    private fun update(status: String, text: String, reveal: Boolean) {
        currentStatus = status
        if (text.isNotBlank() || reveal) currentText = text
        panelTitle?.text = status
        panelText?.text = currentText
        updateBubbleBadge()
        if (reveal) showPanel()
    }

    private fun showPanel() {
        dismissPanel()
        if (currentText.isBlank() && activeTurn.isNotBlank() && currentStatus == service.getString(R.string.screen_assistant_ready)) {
            beginPolling(activeTurn)
        }
        val title = TextView(service).apply {
            text = currentStatus
            textSize = 17f
            setTextColor(0xFF1D2923.toInt())
            setPadding(dp(4), dp(8), dp(4), dp(8))
        }
        val body = TextView(service).apply {
            text = currentText.ifBlank { service.getString(R.string.screen_assistant_waiting) }
            textSize = 15f
            setTextColor(0xFF35473E.toInt())
            setLineSpacing(dp(4).toFloat(), 1f)
            setTextIsSelectable(true)
        }
        panelTitle = title
        panelText = body
        val controls = LinearLayout(service).apply {
            gravity = Gravity.END
            addView(action(R.string.screen_assistant_collapse) { dismissPanel() })
            addView(action(R.string.screen_assistant_follow_up) { showFollowUpInput() })
            addView(action(if (expanded) R.string.screen_assistant_shrink else R.string.screen_assistant_expand) {
                expanded = !expanded
                showPanel()
            })
        }
        val content = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = rounded(Color.WHITE, 18, 0xFFE1E8E4.toInt())
            elevation = dp(12).toFloat()
            addView(title)
            if (expanded) {
                val preview = ImageView(service).apply {
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    background = rounded(0xFFE9F1EE.toInt(), 6)
                    contentDescription = service.getString(R.string.screen_assistant_attachment)
                }
                addView(preview, LinearLayout.LayoutParams(-1, dp(150)).apply { bottomMargin = dp(10) })
                ScreenAssistantSettings.lastCapture(service)?.let { file ->
                    worker.execute {
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeFile(file.path, bounds)
                        var sample = 1
                        while (bounds.outWidth / sample > 720 || bounds.outHeight / sample > 400) sample *= 2
                        val image = BitmapFactory.decodeFile(file.path,
                            BitmapFactory.Options().apply { inSampleSize = sample })
                        handler.post { if (panel === this) preview.setImageBitmap(image) else image?.recycle() }
                    }
                }
            }
            addView(ScrollView(service).apply { addView(body) }, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(controls)
        }
        val height = if (expanded) screenHeight() - dp(36) else minOf(dp(340), screenHeight() / 2)
        if (add(content, params(-1, height, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))) panel = content
    }

    private fun dismissPanel() {
        remove(panel)
        panel = null
        panelText = null
        panelTitle = null
    }

    private inner class CropSelectionView(
        context: Context,
        private val finished: (Rect?) -> Unit
    ) : View(context) {
        private val border = Paint().apply { color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = dp(2).toFloat() }
        private var startX = 0f
        private var startY = 0f
        private var endX = 0f
        private var endY = 0f
        override fun onDraw(canvas: Canvas) {
            canvas.drawColor(0x33000000)
            val rect = Rect(minOf(startX, endX).toInt(), minOf(startY, endY).toInt(),
                maxOf(startX, endX).toInt(), maxOf(startY, endY).toInt())
            if (rect.width() > 0 && rect.height() > 0) canvas.drawRect(rect, border)
            canvas.drawText(service.getString(R.string.screen_assistant_crop_hint), dp(20).toFloat(), dp(70).toFloat(),
                Paint().apply { color = Color.WHITE; textSize = dp(16).toFloat() })
        }
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> { startX = event.x; startY = event.y; endX = startX; endY = startY }
                MotionEvent.ACTION_MOVE -> { endX = event.x; endY = event.y; invalidate() }
                MotionEvent.ACTION_UP -> {
                    endX = event.x; endY = event.y
                    val rect = Rect(minOf(startX, endX).toInt(), minOf(startY, endY).toInt(),
                        maxOf(startX, endX).toInt(), maxOf(startY, endY).toInt())
                    finished(rect.takeIf { it.width() >= dp(60) && it.height() >= dp(60) })
                }
                MotionEvent.ACTION_CANCEL -> finished(null)
            }
            return true
        }
    }
}
