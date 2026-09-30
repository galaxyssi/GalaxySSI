package com.galaxyssi.chat

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
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
import android.provider.Settings
import android.util.Log
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.Choreographer
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.io.FileOutputStream
import java.lang.ref.WeakReference
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
    private const val LAST_CAPTURE = "last_capture"
    private const val LAST_PAGE_CAPTURE = "last_page_capture"
    private const val BUBBLE_X = "bubble_x"
    private const val BUBBLE_Y = "bubble_y"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun enabled(context: Context): Boolean = prefs(context).getBoolean(ENABLED, false)
    fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(ENABLED, value).apply()
        GalaxySSIAccessibilityService.refreshScreenAssistant()
    }
    fun systemAccessEnabled(context: Context): Boolean {
        if (GalaxySSIAccessibilityService.isActive()) return true
        val component = ComponentName(context, GalaxySSIAccessibilityService::class.java)
        val services = Settings.Secure.getString(context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        return services.split(':').any { ComponentName.unflattenFromString(it) == component }
    }
    fun reconcileSystemAccess(context: Context) {
        if (enabled(context) && !systemAccessEnabled(context)) setEnabled(context, false)
    }
    fun conversation(context: Context): String = prefs(context).getString(CONVERSATION, "").orEmpty()
    fun saveConversation(context: Context, id: String) = prefs(context).edit().putString(CONVERSATION, id).apply()
    fun lastTurn(context: Context): String = prefs(context).getString(LAST_TURN, "").orEmpty()
    fun saveLastTurn(context: Context, id: String) = prefs(context).edit().putString(LAST_TURN, id).apply()
    fun lastPageCapture(context: Context): String = prefs(context).getString(LAST_PAGE_CAPTURE, "").orEmpty()
    fun saveLastPageCapture(context: Context, id: String) = prefs(context).edit().putString(LAST_PAGE_CAPTURE, id).apply()
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
        locked: Boolean,
        capturing: Boolean
    ): Boolean = enabled && sdk >= Build.VERSION_CODES.R && !locked && !capturing
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
    private var panelTitle: TextView? = null
    private var capturePending = false
    private var request: ScreenAssistantAnalysisRequest? = null
    private var activeRunner: WeakReference<MainActivity>? = null
    private var stopAction: View? = null
    private var stopping = false
    private var activeTurn = ScreenAssistantSettings.lastTurn(service)
    private var currentText = ""
    private var currentStatus = service.getString(R.string.screen_assistant_ready)
    private var pollGeneration = 0
    private var closed = false
    private var captureHiddenViews = emptyList<Pair<View, Int>>()
    private var observationHidden = false
    private var pauseAction: TextView? = null
    private var approvalAction: TextView? = null
    private var displayedApproval = 0L
    private var pageCollection: ScreenAssistantPageCollection? = null
    private var pageCaptureId = ScreenAssistantSettings.lastPageCapture(service)
    private val pageWorker = Executors.newSingleThreadExecutor { task -> Thread(task, "screen-assistant-page") }

    internal fun hideForCapture(capture: () -> Unit) {
        observationHidden = true
        ScreenAssistantChatActivity.hideForCapture()
        captureHiddenViews = listOfNotNull(bubble, menu, panel, crop).map { it to it.visibility }
        captureHiddenViews.forEach { it.first.visibility = View.INVISIBLE }
        Choreographer.getInstance().postFrameCallback {
            Choreographer.getInstance().postFrameCallback { if (!closed) capture() }
        }
    }

    internal fun restoreAfterCapture() {
        ScreenAssistantChatActivity.restoreAfterCapture()
        captureHiddenViews.forEach { (view, visibility) -> if (view.isAttachedToWindow) view.visibility = visibility }
        captureHiddenViews = emptyList()
        observationHidden = false
        refresh()
    }

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

    fun onTargetInteraction(packageName: String, eventType: Int) {
        ScreenAssistantContentCapture.onInteraction(packageName, eventType)
        if (packageName == foregroundPackage && packageName != service.packageName &&
            eventType in setOf(android.view.accessibility.AccessibilityEvent.TYPE_VIEW_CLICKED,
                android.view.accessibility.AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED)) pageCollection?.interrupted = true
        if (packageName == foregroundPackage && pageCollection != null &&
            eventType == android.view.accessibility.AccessibilityEvent.TYPE_VIEW_SCROLLED &&
            SystemClock.elapsedRealtime() > (pageCollection?.ownScrollUntil ?: 0)) pageCollection?.interrupted = true
    }

    fun refresh() {
        if (closed) return
        if (observationHidden) return
        val visible = ScreenAssistantVisibilityPolicy.shouldShow(
            enabled = ScreenAssistantSettings.enabled(service),
            sdk = Build.VERSION.SDK_INT,
            locked = keyguard.isKeyguardLocked,
            capturing = capturePending
        )
        if (visible) ensureBubble() else hideAll()
    }

    fun close() {
        pageCollection?.request?.cancel()
        if (request?.automation == true) stopAnalysis()
        closed = true
        ScreenAssistantChatActivity.collapseIfOpen()
        pollGeneration++
        hideAll()
        worker.shutdown()
        pageWorker.shutdown()
    }

    fun retryPending() {
        if (closed || !ScreenAssistantSettings.enabled(service)) return
        if (capturePending || stopping || request?.turnId?.isNotBlank() == true) return
        val (file, question) = ScreenAssistantSettings.pending(service) ?: return
        if (AgentConversationWindows.screenAssistantRunner(allowInitializing = true) != null) {
            val attempt = request?.takeUnless { it.isCancelled } ?: newRequest()
            submit(file, question, attempt)
        }
    }

    private fun add(view: View, params: WindowManager.LayoutParams): Boolean =
        runCatching { windowManager.addView(view, params) }.isSuccess

    private fun bringBubbleToFront() {
        val view = bubble ?: return
        val layout = bubbleParams ?: return
        if (observationHidden || capturePending || !view.isAttachedToWindow) return
        runCatching {
            windowManager.removeViewImmediate(view)
            windowManager.addView(view, layout)
        }.onFailure { error ->
            Log.w("ScreenAssistant", "Could not raise floating icon", error)
            if (!view.isAttachedToWindow) {
                bubble = null
                bubbleBadge = null
                bubbleParams = null
                ensureBubble()
            }
        }
    }

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
        panelTitle = null
        stopAction = null
    }

    private fun ensureBubble() {
        if (bubble != null) return
        val size = dp(48)
        val iconSize = service.resources.getDimensionPixelSize(R.dimen.screen_assistant_bubble_icon_size)
        val logo = ImageView(service).apply {
            setImageResource(R.drawable.screen_assistant_bubble_02)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = service.getString(R.string.screen_assistant_capture)
        }
        val root = FrameLayout(service).apply {
            alpha = 0.5f
            // Keep a 48dp touch target around the smaller visual icon.
            addView(logo, FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER))
            val badge = View(service)
            val badgeSize = service.resources.getDimensionPixelSize(R.dimen.screen_assistant_bubble_badge_size)
            addView(badge, FrameLayout.LayoutParams(badgeSize, badgeSize, Gravity.TOP or Gravity.END).apply {
                topMargin = dp(2)
                rightMargin = dp(2)
            })
            bubbleBadge = badge
            setOnTouchListener(BubbleTouchListener())
        }
        val (savedX, savedY) = ScreenAssistantSettings.bubblePosition(service)
        val layout = params(size, size, Gravity.TOP or Gravity.START).apply {
            x = (savedX.takeIf { it >= 0 } ?: (screenWidth() - size - dp(12)))
                .coerceIn(0, max(0, screenWidth() - size))
            y = (savedY.takeIf { it >= 0 } ?: screenHeight() / 2)
                .coerceIn(dp(24), max(dp(24), screenHeight() - dp(100)))
        }
        if (add(root, layout)) {
            bubble = root
            bubbleParams = layout
            updateBubbleBadge()
        }
    }

    private fun updateBubbleBadge() {
        val color = if (pageCollection != null) 0xFFE2A430.toInt() else when (currentStatus) {
            service.getString(R.string.screen_assistant_ready) -> null
            service.getString(R.string.screen_assistant_preparing),
            service.getString(R.string.screen_assistant_analyzing),
            service.getString(R.string.screen_assistant_executing),
            service.getString(R.string.screen_assistant_delayed) -> 0xFFE2A430.toInt()
            service.getString(R.string.screen_assistant_completed) -> 0xFF169F75.toInt()
            else -> 0xFFD95353.toInt()
        }
        bubbleBadge?.apply {
            visibility = if (color == null) View.GONE else View.VISIBLE
            if (color != null) background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
                setStroke(dp(1), Color.WHITE)
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
        private var dismissedMenuOnDown = false
        private val openMenu = Runnable { longPressed = true; showMenu() }

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val layout = bubbleParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX; startY = event.rawY
                    windowX = layout.x; windowY = layout.y
                    moved = false; longPressed = false
                    dismissedMenuOnDown = menu != null
                    if (dismissedMenuOnDown) dismissMenu()
                    else handler.postDelayed(openMenu, ViewConfiguration.getLongPressTimeout().toLong())
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
                        layout.x = (windowX + dx.toInt()).coerceIn(0, max(0, screenWidth() - layout.width))
                        layout.y = (windowY + dy.toInt()).coerceIn(dp(24), max(dp(24), screenHeight() - dp(100)))
                        runCatching { windowManager.updateViewLayout(view, layout) }
                    }
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(openMenu)
                    if (moved) ScreenAssistantSettings.saveBubblePosition(service, layout.x, layout.y)
                    else if (!longPressed && !dismissedMenuOnDown) {
                        if (panel != null) dismissPanel()
                        openChat(capture = !canStopAnalysis() && !stopping)
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
            addView(action(R.string.screen_assistant_capture) { analyzeCurrentScreen() })
            addView(action(R.string.screen_assistant_full_page) { analyzeFullPage() })
            addView(action(R.string.screen_assistant_ask) { showQuestionInput() })
            addView(action(R.string.screen_assistant_execute) { showPhoneTaskInput() })
            addView(action(R.string.screen_assistant_open_target) { showPhoneTaskInput(R.string.screen_assistant_open_target_goal) })
            addView(action(R.string.screen_assistant_chrome) { showPhoneTaskInput(R.string.screen_assistant_chrome_goal) })
            addView(action(R.string.screen_assistant_device_tools) { showDeviceTools() })
            addView(action(R.string.screen_assistant_crop) { showCrop() })
            addView(action(R.string.screen_assistant_last_result) { showPanel() })
            if (canStopAnalysis()) addView(action(R.string.screen_assistant_stop) { stopAnalysis() })
            addView(action(R.string.screen_assistant_pause) {
                ScreenAssistantSettings.setEnabled(service, false)
            })
        }
        val height = minOf(dp(list.childCount * 48), screenHeight() - dp(100))
        val scroll = ScrollView(service).apply { addView(list) }
        val layout = params(dp(235), height, Gravity.TOP or Gravity.START).apply {
            x = menuX(width)
            y = ((bubbleParams?.y ?: 0) - height - dp(10)).coerceAtLeast(dp(30))
        }
        if (add(scroll, layout)) {
            menu = scroll
            bringBubbleToFront()
        }
    }

    private fun dismissMenu() { remove(menu); menu = null }

    private fun menuX(width: Int): Int {
        val iconX = bubbleParams?.x ?: 0
        val iconWidth = bubbleParams?.width ?: dp(48)
        val gap = dp(8)
        val left = iconX - width - gap
        val right = iconX + iconWidth + gap
        return when {
            left >= 0 -> left
            right + width <= screenWidth() -> right
            else -> iconX.coerceIn(0, max(0, screenWidth() - width))
        }
    }

    private fun showQuestionInput() = openChat(capture = true)

    private fun showPhoneTaskInput(template: Int = R.string.screen_assistant_phone_goal) =
        openChat(draft = when (template) {
            R.string.screen_assistant_open_target_goal -> service.getString(R.string.screen_assistant_open_target)
            R.string.screen_assistant_chrome_goal -> service.getString(R.string.screen_assistant_chrome)
            else -> ""
        }, automation = true)

    private fun showDeviceTools() {
        dismissMenu()
        val list = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(Color.WHITE, 16, 0xFFE0E8E5.toInt())
            listOf(R.string.screen_assistant_device_status, R.string.screen_assistant_notifications,
                R.string.screen_assistant_location, R.string.screen_assistant_photo,
                R.string.screen_assistant_audio).forEach { label ->
                addView(action(label) { startPhoneTask(service.getString(R.string.screen_assistant_phone_goal, service.getString(label))) })
            }
            addView(action(R.string.screen_assistant_screenshot) { captureScreen() })
            addView(action(R.string.screen_assistant_recording) { startPhoneTask(service.getString(R.string.screen_assistant_recording_goal)) })
        }
        val height = minOf(dp(list.childCount * 48), screenHeight() - dp(100))
        val scroll = ScrollView(service).apply { addView(list) }
        val layout = params(dp(235), height, Gravity.TOP or Gravity.START).apply {
            x = menuX(width)
            y = ((bubbleParams?.y ?: 0) - height - dp(10)).coerceAtLeast(dp(30))
        }
        if (add(scroll, layout)) {
            menu = scroll
            bringBubbleToFront()
        }
    }

    private fun startPhoneTask(goal: String) {
        if (canStopAnalysis() || stopping) { showPanel(); return }
        val attempt = newRequest().apply { automation = true }
        dismissMenu(); dismissPanel()
        update(service.getString(R.string.screen_assistant_executing), "", false)
        submit(null, goal, attempt)
    }

    private fun analyzeCurrentScreen(question: String = "") {
        if (canStopAnalysis() || stopping) { showPanel(); return }
        val attempt = startAnalysisPreparation()
        worker.execute {
            val snapshot = runCatching { GalaxySSIAccessibilityService.readTargetUi() }.getOrNull()
            handler.post {
                if (!accepts(attempt)) return@post
                if (ScreenAssistantEvidencePolicy.shouldCaptureImage(snapshot)) {
                    request = null
                    captureScreen(question, snapshot = snapshot)
                } else {
                    val protectedSnapshot = requireNotNull(snapshot)
                    attempt.displayQuestion = ScreenAssistantEvidencePolicy.displayedQuestion(question,
                        service.getString(R.string.screen_assistant_default_goal))
                    val goal = service.getString(R.string.screen_assistant_structured_goal,
                        attempt.displayQuestion,
                        AgentUntrustedEvidenceBoundary.wrapText("phone_ui", protectedSnapshot.packageName,
                            ScreenAssistantEvidencePolicy.supplementaryText(protectedSnapshot)))
                    submit(null, goal, attempt)
                }
            }
        }
    }

    private fun startAnalysisPreparation(): ScreenAssistantAnalysisRequest {
        val attempt = newRequest()
        dismissMenu(); dismissPanel()
        update(service.getString(R.string.screen_assistant_preparing), "", true)
        return attempt
    }

    private fun analyzeFullPage() {
        if (canStopAnalysis() || stopping) { showPanel(); return }
        if (AgentConversationWindows.screenAssistantRunner(allowInitializing = true) == null) {
            update(service.getString(R.string.screen_assistant_open_app), "", true); return
        }
        val attempt = startAnalysisPreparation()
        attempt.displayQuestion = service.getString(R.string.screen_assistant_page_question)
        val session = ScreenAssistantPageCollection(attempt)
        pageCollection = session
        update(service.getString(R.string.screen_assistant_page_collecting, 0), "", true)
        pageWorker.execute {
            val outcome = runCatching { ScreenAssistantPageCollector(service).collect(session) { count, top ->
                handler.post {
                    if (accepts(attempt) && pageCollection === session) update(service.getString(
                        if (top) R.string.screen_assistant_page_top else R.string.screen_assistant_page_collecting, count), "", false)
                }
            } }
            handler.post {
                if (pageCollection === session) pageCollection = null
                if (!accepts(attempt)) return@post
                outcome.onSuccess { id ->
                    pageCaptureId = id
                    attempt.pageCaptureId = id
                    ScreenAssistantSettings.saveLastPageCapture(service, id)
                    val store = ScreenAssistantPageStore(service)
                    val meta = store.manifest(id)
                    if (meta.optInt("pages") == 0 || session.interrupted) {
                        request = null
                        update(store.status(meta), "", true)
                    } else {
                        update(service.getString(R.string.screen_assistant_analyzing), store.status(meta), true)
                        submit(null, service.getString(R.string.screen_assistant_page_goal, store.status(meta),
                            meta.optInt("pages")), attempt)
                    }
                }.onFailure {
                    request = null
                    Log.e("ScreenAssistant", "Whole-page collection failed", it)
                    update(service.getString(R.string.screen_assistant_page_failed), "", true)
                }
            }
        }
    }

    private fun openChat(capture: Boolean = false, draft: String = "", automation: Boolean = false,
        reveal: Boolean = false) {
        dismissMenu()
        dismissPanel()
        worker.execute {
            val prepared = runCatching {
                val id = ScreenAssistantSettings.conversation(service)
                    .takeIf { transcriptStore.conversation(it) != null }
                    ?: transcriptStore.createAgentConversation(service.getString(R.string.screen_assistant_conversation)).id
                ScreenAssistantSettings.saveConversation(service, id)
                val home = AgentConversationWindows.screenAssistantRunner(allowInitializing = true)
                val sourceId = home?.agentTranscriptStore?.activeConversation()?.id
                    ?: transcriptStore.activeConversation().id
                val route = ScreenAssistantHomeRouting.capture(service, sourceId,
                    AppStoreAgentConnectorRegistry(service).availableTargets())
                ScreenAssistantHomeRouting.apply(service, id, route)
                AgentWindowStateStore(service).select(ScreenAssistantChatActivity.WINDOW_KEY, id)
                id
            }
            handler.post {
                if (closed || !ScreenAssistantSettings.enabled(service)) return@post
                prepared.onSuccess { id ->
                    runCatching { ScreenAssistantChatActivity.open(service, id, reveal, capture, draft, automation) }
                        .onFailure { Log.e("ScreenAssistant", "Could not open Agent window", it) }
                }.onFailure { Log.e("ScreenAssistant", "Could not prepare Agent window", it) }
            }
        }
    }

    internal fun trackChatTurn(runner: MainActivity, conversationId: String, turnId: String,
        attempt: ScreenAssistantAnalysisRequest) {
        activeRunner = WeakReference(runner)
        ScreenAssistantSettings.saveConversation(service, conversationId)
        ScreenAssistantSettings.saveLastTurn(service, turnId)
        request = attempt
        displayedApproval = 0L
        activeTurn = turnId
        currentText = ""
        currentStatus = service.getString(R.string.screen_assistant_analyzing)
        beginPolling(turnId)
    }

    private fun showCrop() {
        dismissPanel()
        val view = CropSelectionView(service) { region ->
            remove(crop); crop = null
            if (region != null) captureScreen(region = region)
        }
        val layout = params(-1, -1, Gravity.TOP or Gravity.START)
        if (add(view, layout)) {
            crop = view
            bringBubbleToFront()
        }
    }

    private fun captureScreen(question: String = "", region: Rect? = null, snapshot: PhoneUiSnapshot? = null) {
        if (canStopAnalysis() || stopping) { showPanel(); return }
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
        val attempt = newRequest()
        attempt.displayQuestion = ScreenAssistantEvidencePolicy.displayedQuestion(question,
            service.getString(R.string.screen_assistant_default_goal))
        dismissMenu(); dismissPanel()
        remove(bubble); bubble = null; bubbleParams = null
        bubbleBadge = null
        handler.postDelayed({
            if (!accepts(attempt)) return@postDelayed
            if (!ScreenAssistantSettings.enabled(service)) {
                capturePending = false
                request = null
                return@postDelayed
            }
            val callback =
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                        if (!accepts(attempt)) { result.hardwareBuffer.close(); return }
                        capturePending = false
                        refresh()
                        val buffer = result.hardwareBuffer
                        val bitmap = runCatching { try {
                            Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false)
                        } finally { buffer.close() } }.getOrNull()
                        if (bitmap == null) {
                            request = null
                            update(service.getString(R.string.screen_assistant_capture_failed), "", true)
                            return
                        }
                        update(service.getString(R.string.screen_assistant_analyzing), "", true)
                        val goal = if (snapshot == null) attempt.displayQuestion else service.getString(
                            R.string.screen_assistant_structured_goal, attempt.displayQuestion,
                            AgentUntrustedEvidenceBoundary.wrapText("phone_ui", snapshot.packageName,
                                ScreenAssistantEvidencePolicy.supplementaryText(snapshot)))
                        persistAndSubmit(bitmap, region, goal, attempt)
                    }
                    override fun onFailure(errorCode: Int) {
                        if (!accepts(attempt)) return
                        Log.w("ScreenAssistant", "Screenshot unavailable code=$errorCode")
                        capturePending = false
                        request = null
                        refresh()
                        update(service.getString(R.string.screen_assistant_capture_failed), "", true)
                    }
                }
            runCatching {
                val targetWindow = GalaxySSIAccessibilityService.targetWindowId()
                check(snapshot == null || targetWindow == snapshot.windowId) { "Target window changed before capture" }
                if (Build.VERSION.SDK_INT >= 34 && targetWindow != null)
                    service.takeScreenshotOfWindow(targetWindow, { task -> handler.post(task) }, callback)
                else service.takeScreenshot(Display.DEFAULT_DISPLAY, { task -> handler.post(task) }, callback)
            }.onFailure {
                if (!accepts(attempt)) return@onFailure
                capturePending = false
                request = null
                refresh()
                update(service.getString(R.string.screen_assistant_capture_failed), "", true)
            }
        }, 220)
    }

    private fun persistAndSubmit(bitmap: Bitmap, region: Rect?, question: String, attempt: ScreenAssistantAnalysisRequest) {
        if (!accepts(attempt)) { bitmap.recycle(); return }
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
                if (!accepts(attempt)) { file?.delete(); return@post }
                if (file == null) {
                    request = null
                    update(service.getString(R.string.screen_assistant_capture_failed), "", true)
                } else {
                    ScreenAssistantSettings.saveLastCapture(service, file)
                    submit(file, question, attempt)
                }
            }
        }
    }

    private fun submit(file: File?, question: String, attempt: ScreenAssistantAnalysisRequest,
        readyDeadline: Long = SystemClock.elapsedRealtime() + 15_000L) {
        if (!accepts(attempt) || attempt.preparingSubmission) return
        val runner = AgentConversationWindows.screenAssistantRunner()
        if (runner == null) {
            if (AgentConversationWindows.screenAssistantRunner(allowInitializing = true) != null &&
                SystemClock.elapsedRealtime() < readyDeadline) {
                update(service.getString(R.string.screen_assistant_preparing), "", panel == null)
                handler.postDelayed({ submit(file, question, attempt, readyDeadline) }, 100L)
                return
            }
            if (attempt.turnId.isBlank() && file != null) ScreenAssistantSettings.savePending(service, file,
                attempt.displayQuestion.ifBlank { question })
            request = null
            update(service.getString(R.string.screen_assistant_open_app), "", true)
            return
        }
        attempt.preparingSubmission = true
        worker.execute {
            val outcome = runCatching {
                val sourceId = runner.agentTranscriptStore.activeConversation().id
                val targets = AppStoreAgentConnectorRegistry(service).availableTargets()
                ScreenAssistantHomeRouting.capture(service, sourceId, targets) to targets
            }
            handler.post {
                attempt.preparingSubmission = false
                if (!accepts(attempt)) return@post
                if (runner.isDestroyed || runner.isFinishing) {
                    submit(file, question, attempt, readyDeadline)
                    return@post
                }
                outcome.onSuccess { (route, targets) ->
                    if (route.manualTargetId.isNotBlank() && targets.none {
                            it.id == route.manualTargetId && AgentConnectorRouteSelector.isDeliverable(it)
                        }) {
                        if (file != null) ScreenAssistantSettings.savePending(service, file,
                            attempt.displayQuestion.ifBlank { question })
                        if (attempt.turnId.isBlank()) request = null
                        update(service.getString(R.string.screen_assistant_target_unavailable), "", true)
                    } else submitPrepared(runner, file, question, attempt, route)
                }.onFailure {
                    Log.e("ScreenAssistant", "Home route preparation failed", it)
                    if (attempt.turnId.isBlank()) request = null
                    update(service.getString(R.string.screen_assistant_submit_failed), "", true)
                }
            }
        }
    }

    private fun submitPrepared(runner: MainActivity, file: File?, question: String,
        attempt: ScreenAssistantAnalysisRequest, route: ScreenAssistantHomeRoute) {
        activeRunner = WeakReference(runner)
        val store = runner.agentTranscriptStore
        runCatching {
            val conversationId = ScreenAssistantSettings.conversation(service)
                .takeIf { it.isNotBlank() && store.conversation(it) != null }
                ?: store.createAgentConversation(service.getString(R.string.screen_assistant_conversation)).id.also {
                    ScreenAssistantSettings.saveConversation(service, it)
                }
            ScreenAssistantHomeRouting.apply(service, conversationId, route)
            store.setSelectedModelOrAgent(conversationId, if (route.manualTargetId.isBlank())
                service.getString(R.string.agent_model_selection_automatic)
            else route.selection.displayName.ifBlank { route.manualTargetId })
            Log.i("ScreenAssistant", "Home route inherited mode=${route.selection.mode} " +
                "target=${route.manualTargetId.ifBlank { route.autoTargetId }}")
            val name = service.getString(R.string.screen_assistant_attachment)
            val attachment = file?.let { image -> AgentInputAttachment(
                id = UUID.randomUUID().toString(),
                uri = LocalAttachmentUris.forFile(service, image, name, "image/jpeg"),
                displayName = name,
                mimeType = "image/jpeg",
                sizeBytes = image.length()
            ) }
            val goal = question.ifBlank { service.getString(R.string.screen_assistant_default_goal) }
            if (attempt.displayQuestion.isBlank()) attempt.displayQuestion = goal
            runner.submitAgentGoal(
                pendingVoiceConversationId = conversationId,
                goalOverride = goal,
                displayGoalOverride = attempt.displayQuestion.ifBlank { goal },
                attachmentsOverride = listOfNotNull(attachment) + pageAttachments(attempt.pageCaptureId),
                onTurnCreated = { turn ->
                    attempt.turnId = turn
                    PhoneAssistantTaskControl.bind(turn, attempt)
                    ScreenAssistantSettings.clearPending(service)
                    activeTurn = turn
                    ScreenAssistantSettings.saveLastTurn(service, turn)
                    currentText = ""
                    update(service.getString(if (attempt.automation) R.string.screen_assistant_executing else R.string.screen_assistant_analyzing), "", true)
                    beginPolling(turn)
                },
                isSubmissionCancelled = { attempt.isCancelled }
            )
        }.onFailure {
            Log.e("ScreenAssistant", "Task submission failed", it)
            if (attempt.turnId.isBlank() && file != null) ScreenAssistantSettings.savePending(service, file,
                attempt.displayQuestion.ifBlank { question })
            if (attempt.turnId.isBlank()) request = null
            update(service.getString(R.string.screen_assistant_submit_failed), "", true)
        }
    }

    private fun beginPolling(turn: String) {
        val generation = ++pollGeneration
        val started = SystemClock.elapsedRealtime()
        var lastReply = ""
        var lastReplyChangeAt = 0L
        var recoveryRequested = false
        fun poll() {
            if (closed || generation != pollGeneration) return
            worker.execute {
                val entries = runCatching { transcriptStore.entriesForTurn(turn) }
                    .getOrDefault(emptyList())
                val workspace = AgentTaskRuntime.supervisor(service).findWorkspace(turn)
                handler.post {
                    if (closed || generation != pollGeneration) return@post
                    val reply = entries.lastOrNull { it.role == AgentTranscriptRole.ASSISTANT && it.text.isNotBlank() }
                    val progress = entries.lastOrNull { it.role == AgentTranscriptRole.PROCESS && it.text.isNotBlank() }
                    if (reply != null && reply.text != lastReply) {
                        lastReply = reply.text
                        lastReplyChangeAt = SystemClock.elapsedRealtime()
                    }
                    val terminal = workspace?.status?.isTerminal == true
                    if (terminal) {
                        PhoneAssistantTaskControl.finish(turn)
                        request?.setPaused(false)
                        request = null
                    }
                    val approval = request?.approvalDescription.orEmpty()
                    val approvalRevision = request?.approvalRevision ?: 0L
                    if (approval.isNotBlank() && approvalRevision != displayedApproval) {
                        if (ScreenAssistantChatActivity.showPhoneApproval(request)) displayedApproval = approvalRevision
                    }
                    when {
                        workspace?.status == AgentWorkspaceStatus.CANCELLED ->
                            update(service.getString(R.string.screen_assistant_cancelled), reply?.text.orEmpty(), false)
                        workspace?.status == AgentWorkspaceStatus.FAILED ->
                            update(service.getString(R.string.agent_task_status_failed), reply?.text ?: progress?.text.orEmpty(), false)
                        reply != null -> update(
                            service.getString(if (terminal || workspace == null && SystemClock.elapsedRealtime() - lastReplyChangeAt >= 6_000L)
                                R.string.screen_assistant_completed else R.string.screen_assistant_analyzing),
                            reply.text, false
                        )
                        SystemClock.elapsedRealtime() - started >= 90_000L -> {
                            if (!recoveryRequested) {
                                recoveryRequested = true
                                AndroidAgentRecoveryWake.request(service)
                            }
                            update(
                                service.getString(R.string.screen_assistant_delayed),
                                service.getString(R.string.screen_assistant_delayed_detail), false
                            )
                        }
                        progress != null -> update(service.getString(R.string.screen_assistant_analyzing), progress.text, false)
                    }
                    val replySettled = workspace == null && reply != null && SystemClock.elapsedRealtime() - lastReplyChangeAt >= 6_000L
                    if (terminal || replySettled) {
                        request = null
                        stopAction?.visibility = View.GONE
                    } else {
                        handler.postDelayed(::poll,
                            if (SystemClock.elapsedRealtime() - started < 30 * 60_000L) 1500L else 10_000L)
                    }
                }
            }
        }
        handler.postDelayed(::poll, 600L)
    }

    private fun update(status: String, text: String, reveal: Boolean) {
        currentStatus = status
        if (text.isNotBlank() || reveal) currentText = text
        panelTitle?.text = when {
            request?.approvalDescription?.isNotBlank() == true -> service.getString(R.string.screen_assistant_approval, request?.approvalDescription)
            request?.isPaused == true -> service.getString(R.string.screen_assistant_task_paused)
            else -> status
        }
        pauseAction?.text = service.getString(if (request?.isPaused == true) R.string.screen_assistant_resume_task else R.string.screen_assistant_pause_task)
        pauseAction?.visibility = if ((request?.automation == true || pageCollection != null) && canStopAnalysis()) View.VISIBLE else View.GONE
        approvalAction?.visibility = if (request?.approvalDescription?.isNotBlank() == true) View.VISIBLE else View.GONE
        stopAction?.visibility = if (canStopAnalysis()) View.VISIBLE else View.GONE
        updateBubbleBadge()
        if (reveal) showPanel()
    }

    private fun showPanel() {
        dismissPanel()
        if (pageCollection == null) {
            if (request != null && activeTurn.isBlank()) {
                android.widget.Toast.makeText(service, currentStatus, android.widget.Toast.LENGTH_SHORT).show()
                return
            }
            openChat(reveal = true)
            return
        }
        if (currentText.isBlank() && activeTurn.isNotBlank() &&
            ScreenAssistantSettings.pending(service) == null &&
            currentStatus == service.getString(R.string.screen_assistant_ready)) {
            request = ScreenAssistantAnalysisRequest().apply { turnId = activeTurn }
            beginPolling(activeTurn)
        }
        val title = TextView(service).apply {
            text = if (request?.isPaused == true) service.getString(R.string.screen_assistant_task_paused) else currentStatus
            textSize = 17f
            setTextColor(0xFF1D2923.toInt())
            setPadding(dp(4), dp(8), dp(4), dp(8))
        }
        panelTitle = title
        val controls = LinearLayout(service).apply {
            gravity = Gravity.END
            addView(action(R.string.screen_assistant_approve) {
                request?.approve()
                displayedApproval = 0L
                update(currentStatus, currentText, false)
            }.apply {
                visibility = if (request?.approvalDescription?.isNotBlank() == true) View.VISIBLE else View.GONE
                approvalAction = this
            })
            if ((request?.automation == true || pageCollection != null) && canStopAnalysis()) addView(action(R.string.screen_assistant_pause_task) {
                request?.let { it.setPaused(!it.isPaused) }
                update(currentStatus, currentText, false)
            }.also { pauseAction = it })
            if (pageCollection != null) addView(action(R.string.screen_assistant_page_finish) {
                pageCollection?.finish()
            })
            addView(action(if (pageCollection != null) R.string.screen_assistant_page_cancel else R.string.screen_assistant_stop) { stopAnalysis() }.apply {
                setTextColor(0xFFB33636.toInt())
                visibility = if (canStopAnalysis()) View.VISIBLE else View.GONE
                stopAction = this
            })
            addView(action(R.string.screen_assistant_collapse) { dismissPanel() })
            for (index in 0 until childCount) getChildAt(index).apply {
                layoutParams = LinearLayout.LayoutParams(0, -2, 1f)
                setPadding(dp(4), 0, dp(4), 0)
                (this as TextView).gravity = Gravity.CENTER
            }
        }
        val content = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = rounded(Color.WHITE, 18, 0xFFE1E8E4.toInt())
            elevation = dp(12).toFloat()
            addView(title)
            addView(controls)
        }
        val height = dp(145)
        if (add(content, params(-1, height, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))) {
            panel = content
            bringBubbleToFront()
        }
    }

    private fun dismissPanel() {
        remove(panel)
        panel = null
        panelTitle = null
        stopAction = null
        pauseAction = null
        approvalAction = null
    }

    private fun newRequest(): ScreenAssistantAnalysisRequest = ScreenAssistantAnalysisRequest().also {
        pageCaptureId = ""
        request = it
        displayedApproval = 0L
        activeTurn = ""
        pollGeneration++
        currentText = ""
        currentStatus = service.getString(R.string.screen_assistant_analyzing)
    }

    private fun accepts(attempt: ScreenAssistantAnalysisRequest): Boolean =
        !closed && request === attempt && !attempt.isCancelled

    private fun canStopAnalysis(): Boolean = !stopping &&
        (request?.isCancelled == false || ScreenAssistantSettings.pending(service) != null)

    private fun stopAnalysis() {
        if (!canStopAnalysis()) return
        val attempt = request
        attempt?.cancel()
        pageCollection = null
        pollGeneration++
        capturePending = false
        ScreenAssistantSettings.clearPending(service)
        val turns = attempt?.turnIds.orEmpty()
        val conversation = ScreenAssistantSettings.conversation(service)
        val runner = activeRunner?.get() ?: AgentConversationWindows.screenAssistantRunner()
        stopping = turns.isNotEmpty()
        update(service.getString(if (stopping) R.string.agent_task_status_cancelling
            else R.string.screen_assistant_cancelled), currentText, true)
        refresh()
        if (!stopping) { request = null; return }
        Thread({
            val stopped = runCatching {
                var remoteDelivered = true
                for (turn in turns) {
                    val sent = ScreenAssistantTaskCancellation.cancel(service.applicationContext, conversation, turn, runner)
                    remoteDelivered = remoteDelivered && sent
                    transcriptStore.append(AgentTranscriptRole.PROCESS,
                        service.getString(R.string.screen_assistant_cancelled),
                        dedupeKey = "screen-analysis-cancel:$turn", conversationId = conversation,
                        turnId = turn, taskId = turn)
                }
                remoteDelivered
            }
            handler.post {
                if (closed || request !== attempt) return@post
                stopping = false
                request = if (stopped.isFailure) attempt else null
                update(service.getString(R.string.screen_assistant_cancelled), currentText, false)
                if (stopped.isFailure) update(service.getString(R.string.screen_assistant_cancel_failed), currentText, false)
                else if (stopped.getOrNull() == false) {
                    update(service.getString(R.string.agent_loop_timeline_remote_cancel_failed), currentText, false)
                }
            }
        }, "screen-assistant-cancel").start()
    }

    private fun pageAttachments(id: String): List<AgentInputAttachment> {
        if (id.isBlank()) return emptyList()
        val directory = ScreenAssistantPageStore(service).directory(id)
        return listOf("page.html" to "text/html", "page.txt" to "text/plain").mapNotNull { (name, mime) ->
            val file = File(directory, name).takeIf(File::isFile) ?: return@mapNotNull null
            val label = service.getString(R.string.screen_assistant_page_attachment) + "." + file.extension
            AgentInputAttachment(UUID.randomUUID().toString(), LocalAttachmentUris.forFile(service, file, label, mime),
                label, mime, file.length())
        }
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
