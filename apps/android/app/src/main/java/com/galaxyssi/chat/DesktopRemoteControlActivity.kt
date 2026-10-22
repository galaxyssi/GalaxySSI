package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import org.json.JSONObject
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/** A remote display session with its own orientation and input lifecycle. */
class DesktopRemoteControlActivity : Activity(), GalaxySSIMqttClient.Listener {
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val inputQueue = DesktopInputQueue()
    private val streamRecovery = DesktopRemoteStreamRecovery()
    private lateinit var root: LinearLayout
    private lateinit var header: LinearLayout
    private lateinit var deviceBar: LinearLayout
    private lateinit var toolbar: LinearLayout
    private lateinit var canvas: FrameLayout
    private lateinit var screen: DesktopRemoteScreenView
    private lateinit var composer: DesktopRemoteComposer
    private lateinit var placeholder: TextView
    private lateinit var status: TextView
    private lateinit var overlayName: TextView
    private lateinit var overlayMore: ImageButton
    private lateinit var handle: ImageButton
    private lateinit var floatingTools: LinearLayout
    private lateinit var spinner: ProgressBar
    private var desktopId = ""
    private var desktopName = ""
    private var fullscreen = false
    @Volatile private var resumed = false
    @Volatile private var generation = 0
    private var imeVisible = false
    private var resumeKeyboard = false
    private var manualInput = false
    private var autoInputAction = ""
    private var focus: DesktopInputFocus? = null
    private var snapshot: DesktopRemoteControlSnapshot? = null
    private var bitmap: Bitmap? = null
    private var capturedAt = 0L
    private var reading = false
    private var readAgain = false
    private var streamStarted = false
    private var streamFps = 1
    private var waitingSince = 0L
    private val connectionWatchdog = object : Runnable {
        override fun run() {
            if (!resumed) return
            readState()
            handler.postDelayed(this, 5_000)
        }
    }
    private val inputTimeout = Runnable {
        if (inputQueue.active != null) failInput(getString(R.string.desktop_remote_input_timeout))
    }
    private val refreshTimeout = Runnable {
        spinner.visibility = View.GONE
        if (bitmap == null) placeholder.setText(R.string.desktop_remote_frame_timeout)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        desktopId = intent.getStringExtra(EXTRA_DESKTOP_ID).orEmpty()
        desktopName = intent.getStringExtra(EXTRA_DESKTOP_NAME).orEmpty()
        if (desktopId.isBlank()) { finish(); return }
        fullscreen = savedInstanceState?.getBoolean("fullscreen") == true
        streamFps = savedInstanceState?.getInt("stream_fps", 1) ?: 1
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        createContent()
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val keyboard = insets.getInsets(WindowInsetsCompat.Type.ime())
            val visible = insets.isVisible(WindowInsetsCompat.Type.ime())
            if (imeVisible != visible) composer.onKeyboardVisibilityChanged(visible)
            imeVisible = visible
            toolbar.visibility = if (fullscreen || visible) View.GONE else View.VISIBLE
            root.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, keyboard.bottom))
            handle.visibility = if (fullscreen && !visible && floatingTools.visibility != View.VISIBLE) View.VISIBLE else View.GONE
            if (visible) screen.post { revealFocus() }
            insets
        }
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val chrome = (if (header.isShown) header.height else 0) + (if (deviceBar.isShown) deviceBar.height else 0) +
                (if (toolbar.isShown) toolbar.height else 0)
            composer.constrainHeight(root.height - root.paddingTop - root.paddingBottom - chrome)
        }
        applyFullscreen()
    }

    override fun onResume() {
        super.onResume()
        if (desktopId.isBlank()) return
        resumed = true
        if (resumeKeyboard && composer.view.isShown) composer.showKeyboard()
        resumeKeyboard = false
        waitingSince = System.currentTimeMillis()
        streamRecovery.reset()
        handler.postDelayed(connectionWatchdog, 5_000)
        val epoch = ++generation
        AppForegroundTracker.onActivityForeground(this)
        GalaxySSIMqttClient.addListener(this)
        worker.execute {
            if (!resumed || generation != epoch) return@execute
            GalaxySSIMqttClient.bindApplicationContext(applicationContext)
            GalaxySSIMqttClient.connect(applicationContext)
            DesktopRemoteControl.requestAuthorizations(desktopId)
            handler.post { readState() }
        }
    }

    override fun onPause() {
        resumeKeyboard = imeVisible && composer.view.isShown
        resumed = false
        generation++
        AppForegroundTracker.onActivityBackground(this)
        GalaxySSIMqttClient.removeListener(this)
        DesktopRemoteControl.stopScreenshotStream(desktopId)
        streamStarted = false
        handler.removeCallbacks(inputTimeout)
        handler.removeCallbacks(refreshTimeout)
        handler.removeCallbacks(connectionWatchdog)
        inputQueue.clear()
        worker.execute { DesktopRemoteControl.clearInputResults(desktopId) }
        hideKeyboard()
        composer.pause()
        super.onPause()
    }

    override fun onStop() {
        resumeKeyboard = false
        focus = null; manualInput = false
        composer.background()
        screen.clearScreenshot()
        bitmap?.recycle(); bitmap = null; capturedAt = 0
        super.onStop()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (::composer.isInitialized) composer.close()
        worker.shutdown()
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("fullscreen", fullscreen)
        outState.putInt("stream_fps", streamFps)
        super.onSaveInstanceState(outState)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyFullscreen()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        when {
            imeVisible -> hideKeyboard()
            composer.view.isShown -> { composer.hide(); toolbar.visibility = if (fullscreen) View.GONE else View.VISIBLE }
            fullscreen -> { fullscreen = false; applyFullscreen() }
            else -> super.onBackPressed()
        }
    }

    override fun onDesktopControlChanged(desktopId: String, streamFrame: Boolean) {
        if (desktopId == this.desktopId) handler.post { if (resumed) readState() }
    }

    override fun onConnectionChanged(isConnected: Boolean) {
        handler.post {
            if (!resumed) return@post
            if (!isConnected) {
                if (inputQueue.active != null) failInput(getString(R.string.desktop_remote_input_timeout))
                streamStarted = false
            }
            readState()
        }
    }

    private fun createContent() {
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE) }
        header = row().apply {
            addView(icon(R.drawable.ic_navigation_back, R.string.desktop_remote_back) { onBackPressed() })
            addView(label(getString(R.string.desktop_control_title), 18f).apply {
                gravity = Gravity.CENTER
            }, LinearLayout.LayoutParams(0, dp(52), 1f))
            addView(icon(R.drawable.ic_more_horizontal, R.string.common_more) { more(it) })
        }
        root.addView(header, LinearLayout.LayoutParams(-1, dp(52)))
        status = label("", 12f).apply { setTextColor(Color.rgb(73, 112, 99)) }
        deviceBar = row().apply {
            setPadding(dp(16), 0, dp(16), 0)
            addView(android.widget.ImageView(this@DesktopRemoteControlActivity).apply {
                setImageResource(R.drawable.ic_device_node)
                imageTintList = ColorStateList.valueOf(Color.rgb(37, 44, 51))
                setPadding(dp(6), dp(6), dp(6), dp(6))
                background = GradientDrawable().apply {
                    setColor(Color.rgb(243, 244, 246)); cornerRadius = dp(6).toFloat()
                }
            }, LinearLayout.LayoutParams(dp(36), dp(36)))
            addView(LinearLayout(this@DesktopRemoteControlActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(12), 0, 0, 0)
                addView(label(desktopName, 16f)); addView(status)
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }
        root.addView(deviceBar, LinearLayout.LayoutParams(-1, dp(58)))
        canvas = FrameLayout(this).apply { setBackgroundColor(Color.rgb(239, 241, 243)) }
        screen = DesktopRemoteScreenView(this).apply {
            setScreenContentDescription(getString(R.string.desktop_control_screen_content_description))
            onImageTap = { x, y -> click(x, y, "left", 1) }
            onImageDoubleTap = { x, y -> click(x, y, "left", 2) }
            onImageLongPress = { x, y -> click(x, y, "right", 1) }
            onRemoteScroll = { delta -> enqueue(DesktopRemoteControl.SCROLL, JSONObject().put("delta", delta)) }
        }
        canvas.addView(screen, FrameLayout.LayoutParams(-1, -1))
        placeholder = label(getString(R.string.desktop_remote_connecting), 14f).apply { gravity = Gravity.CENTER }
        canvas.addView(placeholder, FrameLayout.LayoutParams(-1, -1))
        spinner = ProgressBar(this).apply { visibility = View.GONE }
        canvas.addView(spinner, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))
        overlayName = label(desktopName, 12f).apply {
            setTextColor(Color.rgb(25, 95, 76)); setPadding(dp(12), dp(8), dp(12), dp(8))
            setBackgroundColor(0xDDFFFFFF.toInt())
        }
        canvas.addView(overlayName, FrameLayout.LayoutParams(-2, dp(40), Gravity.TOP or Gravity.START))
        overlayMore = icon(R.drawable.ic_more_horizontal, R.string.common_more) { more(it) }
        canvas.addView(overlayMore, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.END))
        floatingTools = row().apply {
            setBackgroundColor(0xEEFFFFFF.toInt()); elevation = dp(2).toFloat()
            addView(icon(R.drawable.ic_composer_rotate, R.string.desktop_control_surface_refresh_action) { refresh() })
            addView(icon(R.drawable.ic_screen_assistant_expand, R.string.desktop_remote_fit) { screen.resetTransform() })
            addView(icon(R.drawable.ic_navigation_back, R.string.desktop_remote_exit_fullscreen) { fullscreen = false; applyFullscreen() })
            addView(icon(R.drawable.ic_chevron_down, R.string.desktop_remote_hide_tools) { collapseTools() })
        }
        canvas.addView(floatingTools, FrameLayout.LayoutParams(-2, dp(48), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(12) })
        handle = icon(R.drawable.ic_chevron_down, R.string.desktop_remote_show_tools) {
            handle.visibility = View.GONE; floatingTools.visibility = View.VISIBLE
        }.apply { rotation = 180f; setBackgroundColor(0xDDFFFFFF.toInt()) }
        canvas.addView(handle, FrameLayout.LayoutParams(dp(48), dp(36), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
        root.addView(canvas, LinearLayout.LayoutParams(-1, 0, 1f))
        toolbar = row().apply {
            addView(command(R.drawable.ic_composer_rotate, R.string.desktop_control_surface_refresh_action) { refresh() }, LinearLayout.LayoutParams(0, dp(60), 1f))
            addView(command(R.drawable.ic_screen_assistant_expand, R.string.desktop_remote_fullscreen) { fullscreen = true; applyFullscreen() }, LinearLayout.LayoutParams(0, dp(60), 1f))
        }
        composer = DesktopRemoteComposer(this, ::sendDraft)
        root.addView(composer.view, LinearLayout.LayoutParams(-1, -2))
        root.addView(toolbar, LinearLayout.LayoutParams(-1, dp(60)))
    }

    private fun applyFullscreen() {
        requestedOrientation = if (fullscreen) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        header.visibility = if (fullscreen) View.GONE else View.VISIBLE
        deviceBar.visibility = header.visibility
        toolbar.visibility = if (fullscreen || imeVisible) View.GONE else View.VISIBLE
        overlayName.visibility = if (fullscreen) View.VISIBLE else View.GONE
        overlayMore.visibility = overlayName.visibility
        collapseTools()
        WindowInsetsControllerCompat(window, root).apply {
            isAppearanceLightStatusBars = !fullscreen
            isAppearanceLightNavigationBars = !fullscreen
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (fullscreen) hide(WindowInsetsCompat.Type.systemBars()) else show(WindowInsetsCompat.Type.systemBars())
        }
        ViewCompat.requestApplyInsets(root)
    }

    private fun collapseTools() {
        floatingTools.visibility = View.GONE
        handle.visibility = if (fullscreen && !imeVisible) View.VISIBLE else View.GONE
    }

    private fun readState() {
        if (!resumed) return
        if (reading) { readAgain = true; return }
        reading = true
        val previousCapture = capturedAt
        val epoch = generation
        worker.execute {
            val state = runCatching { DesktopRemoteControl.snapshot(applicationContext, desktopId) }.getOrNull()
            val image = state?.screenshot?.takeIf { it.capturedAt != previousCapture }?.let {
                BitmapFactory.decodeByteArray(it.jpegBytes, 0, it.jpegBytes.size)
            }
            handler.post {
                reading = false
                if (!resumed || isDestroyed || generation != epoch) {
                    image?.recycle()
                    if (resumed && !isDestroyed) readState()
                    return@post
                }
                if (state == null) { failureToast(getString(R.string.desktop_control_request_failed)); return@post }
                snapshot = state
                status.text = getString(when {
                    !GalaxySSIMqttClient.isConnected() -> R.string.status_disconnected
                    state.authorized && (image != null || bitmap != null) -> R.string.desktop_remote_connected
                    state.authorized -> R.string.desktop_remote_waiting
                    else -> R.string.desktop_control_authorization_required
                })
                if (image != null) {
                    val old = bitmap
                    bitmap = image; capturedAt = state.screenshot!!.capturedAt
                    screen.setScreenshot(image, preserveTransform = true)
                    old?.recycle()
                    placeholder.visibility = View.GONE; spinner.visibility = View.GONE
                    handler.removeCallbacks(refreshTimeout)
                }
                if (bitmap == null && !state.authorized) placeholder.setText(R.string.desktop_control_authorization_required)
                else if (bitmap == null && state.lastActionErrorCode.isNotBlank()) {
                    placeholder.text = getString(R.string.desktop_remote_frame_failed, state.lastActionErrorCode)
                    spinner.visibility = View.GONE
                } else if (bitmap == null && System.currentTimeMillis() - waitingSince >= 15_000) {
                    placeholder.setText(R.string.desktop_remote_frame_timeout)
                    spinner.visibility = View.GONE
                }
                inputQueue.active?.id?.let(DesktopRemoteControl::consumeInputResult)?.let(::inputResult)
                val action = streamRecovery.next(System.currentTimeMillis(), GalaxySSIMqttClient.isConnected(),
                    state.authorized, state.currentAuthorization?.desktopSessionId.orEmpty(),
                    state.currentAuthorization?.desktopSessionExpiresAt ?: 0L,
                    if (streamFps > 0) state.streamActive else streamStarted,
                    state.lastActionErrorCode, state.lastActionDesktopSessionId, state.lastActionAt)
                if (action != DesktopRemoteStreamRecovery.Action.NONE) {
                    worker.execute {
                        if (!resumed || generation != epoch) return@execute
                        when (action) {
                            DesktopRemoteStreamRecovery.Action.RENEW -> DesktopRemoteControl.requestAuthorizations(desktopId)
                            DesktopRemoteStreamRecovery.Action.START -> {
                                val accepted = if (streamFps > 0) DesktopRemoteControl.startScreenshotStream(desktopId, streamFps)
                                    else DesktopRemoteControl.requestScreenshot(desktopId)
                                handler.post { if (resumed && generation == epoch) streamStarted = accepted }
                            }
                            else -> Unit
                        }
                    }
                }
                if (readAgain) { readAgain = false; readState() }
            }
        }
    }

    private fun refresh() {
        if (!resumed) return
        spinner.visibility = View.VISIBLE
        waitingSince = System.currentTimeMillis()
        val epoch = generation
        handler.removeCallbacks(refreshTimeout); handler.postDelayed(refreshTimeout, 30_000)
        worker.execute {
            if (!resumed || generation != epoch) return@execute
            val accepted = DesktopRemoteControl.requestScreenshot(desktopId)
            handler.post { if (!accepted && resumed) { spinner.visibility = View.GONE; failureToast(getString(R.string.desktop_control_request_failed)) } }
        }
    }

    private fun click(x: Float, y: Float, button: String, clicks: Int) {
        if (!resumed || snapshot?.authorized != true) return
        val image = snapshot?.screenshot ?: return
        hideKeyboard()
        composer.hide()
        toolbar.visibility = if (fullscreen) View.GONE else View.VISIBLE
        focus = null; manualInput = false
        val command = DesktopInputCommand(DesktopRemoteControl.CLICK_XY, JSONObject()
            .put("x", (x * (image.originalWidth - 1)).roundToInt())
            .put("y", (y * (image.originalHeight - 1)).roundToInt())
            .put("coordinate_width", image.originalWidth).put("coordinate_height", image.originalHeight)
            .put("button", button).put("clicks", clicks))
        autoInputAction = if (button == "left") command.id else ""
        if (!inputQueue.add(command)) failInput(getString(R.string.desktop_remote_input_busy)) else sendNext()
    }

    private fun enqueue(tool: String, input: JSONObject) {
        if (!resumed || snapshot?.authorized != true) return
        if (tool in setOf(DesktopRemoteControl.TYPE_TEXT, DesktopRemoteControl.HOTKEY)) {
            if (!manualInput && focus?.editable != true) return
            if (!manualInput) focus?.targetId?.takeIf { it.isNotBlank() }?.let { input.put("input_target_id", it) }
        }
        if (tool == DesktopRemoteControl.TYPE_TEXT && input.optString("text").length > 4096) {
            failureToast(getString(R.string.desktop_remote_text_too_long)); return
        }
        if (!inputQueue.add(DesktopInputCommand(tool, input))) failInput(getString(R.string.desktop_remote_input_busy)) else sendNext()
    }

    private fun sendDraft(text: String) {
        if (!resumed || snapshot?.authorized != true || !GalaxySSIMqttClient.isConnected()) {
            composer.failed(getString(R.string.desktop_control_request_failed)); return
        }
        if (!manualInput && focus?.editable != true) {
            composer.failed(getString(R.string.desktop_remote_draft_no_target)); return
        }
        if (text.length > 4096) { composer.failed(getString(R.string.desktop_remote_text_too_long)); return }
        val input = JSONObject().put("text", text)
        if (!manualInput) focus?.targetId?.takeIf(String::isNotBlank)?.let { input.put("input_target_id", it) }
        val command = DesktopInputCommand(DesktopRemoteControl.TYPE_TEXT, input)
        if (!inputQueue.add(command)) { composer.failed(getString(R.string.desktop_remote_input_busy)); return }
        composer.beginSend(command.id)
        sendNext()
    }

    private fun sendNext() {
        val next = inputQueue.next() ?: return
        val epoch = generation
        handler.removeCallbacks(inputTimeout); handler.postDelayed(inputTimeout, 30_000)
        worker.execute {
            if (!resumed || generation != epoch) return@execute
            val accepted = runCatching {
                DesktopRemoteControl.sendInteractiveInput(desktopId, next.id, next.tool, next.input)
            }.getOrDefault(false)
            handler.post { if (!accepted && inputQueue.active?.id == next.id) failInput(getString(R.string.desktop_control_request_failed)) }
        }
    }

    private fun inputResult(result: DesktopInputResult) {
        if (!inputQueue.complete(result)) return
        handler.removeCallbacks(inputTimeout)
        if (!result.succeeded) { failInput(result.error.ifBlank { getString(R.string.desktop_control_request_failed) }); return }
        composer.received(result.actionId, true)
        val value = result.focus
        if (value != null && result.actionId == autoInputAction) {
            focus = value
            if (value.editable) showKeyboard(false)
        }
        if (result.actionId == autoInputAction) autoInputAction = ""
        sendNext()
        if (streamFps == 0) refresh()
    }

    private fun showKeyboard(manual: Boolean) {
        manualInput = manualInput || manual
        if (!manualInput && focus?.editable != true) return
        toolbar.visibility = View.GONE
        composer.open(password = focus?.password == true)
        collapseTools()
    }

    private fun hideKeyboard() {
        if (!::composer.isInitialized) return
        autoInputAction = ""
        composer.hideKeyboard()
    }

    private fun revealFocus() {
        val value = focus ?: return
        val image = snapshot?.screenshot ?: return
        if (image.originalWidth > 0 && image.originalHeight > 0) screen.revealImagePoint(
            ((value.left + value.width / 2f) / image.originalWidth).coerceIn(0f, 1f),
            ((value.top + minOf(value.height, 40) / 2f) / image.originalHeight).coerceIn(0f, 1f))
    }

    private fun failInput(message: String) {
        inputQueue.clear(); handler.removeCallbacks(inputTimeout); hideKeyboard()
        composer.failed(message)
        worker.execute { DesktopRemoteControl.clearInputResults(desktopId) }
        failureToast(message)
    }

    private fun more(anchor: View) {
        PopupMenu(this, anchor).apply {
            menu.add(0, 1, 0, R.string.desktop_remote_keyboard)
            menu.add(0, 2, 1, R.string.desktop_remote_fit)
            menu.add(0, 3, 2, R.string.desktop_control_stream_title)
            menu.add(0, 4, 3, R.string.desktop_remote_advanced)
            setOnMenuItemClickListener {
                when (it.itemId) {
                    1 -> showKeyboard(true)
                    2 -> screen.resetTransform()
                    3 -> AlertDialog.Builder(this@DesktopRemoteControlActivity)
                        .setTitle(R.string.desktop_control_stream_dialog_title)
                        .setSingleChoiceItems(arrayOf(getString(R.string.common_off), "1 FPS", "2 FPS", "3 FPS"), streamFps) { dialog, rate ->
                            streamFps = rate; streamStarted = false; streamRecovery.reset()
                            DesktopRemoteControl.stopScreenshotStream(desktopId)
                            dialog.dismiss(); readState()
                        }.setNegativeButton(R.string.common_cancel, null).show()
                    4 -> { setResult(RESULT_OK, Intent().putExtra(EXTRA_DESKTOP_ID, desktopId)); finish() }
                }
                true
            }
            show()
        }
    }

    private fun row() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun label(value: String, size: Float) = TextView(this).apply {
        text = value; textSize = size; setTextColor(Color.rgb(25, 29, 35)); gravity = Gravity.CENTER_VERTICAL
        maxLines = 2
    }
    private fun icon(drawable: Int, description: Int, action: (View) -> Unit) = ImageButton(this).apply {
        setImageResource(drawable); setColorFilter(Color.rgb(37, 44, 51))
        contentDescription = getString(description); tooltipText = contentDescription
        setPadding(dp(13), dp(13), dp(13), dp(13)); setBackgroundColor(Color.TRANSPARENT)
        layoutParams = LinearLayout.LayoutParams(dp(48), dp(48)); setOnClickListener(action)
    }
    private fun command(drawable: Int, description: Int, action: () -> Unit) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
        contentDescription = getString(description); isClickable = true; isFocusable = true
        addView(android.widget.ImageView(this@DesktopRemoteControlActivity).apply { setImageResource(drawable) }, LinearLayout.LayoutParams(dp(23), dp(23)))
        addView(label(getString(description), 11f).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            maxLines = 1
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(3) })
        setOnClickListener { action() }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()
    private fun failureToast(value: String) { if (resumed) Toast.makeText(this, value, Toast.LENGTH_LONG).show() }

    companion object {
        const val EXTRA_DESKTOP_ID = "desktop_id"
        const val EXTRA_DESKTOP_NAME = "desktop_name"
        const val REQUEST_CONTROL = 6380
    }
}
