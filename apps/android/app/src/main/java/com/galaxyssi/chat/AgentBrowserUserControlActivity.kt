package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Bundle
import android.text.InputType
import android.util.Base64
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.CheckBox
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import java.util.concurrent.Executors
import org.json.JSONObject

/** Displays the live guest browser, not a second WebView with unrelated cookies. */
class AgentBrowserUserControlActivity : Activity() {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var control: AgentBrowserUserControl
    private lateinit var title: TextView
    private lateinit var status: TextView
    private lateinit var image: ImageView
    private lateinit var spinner: ProgressBar
    private lateinit var actions: LinearLayout
    private var record: AgentBrowserUserRequest? = null
    private var bitmap: Bitmap? = null
    private var revision = ""
    private var resumed = false
    private var busy = false
    private var refreshQueued = false
    private var touchX = 0f
    private var touchY = 0f
    private var dialog: AlertDialog? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        control = AgentBrowserUserControl(applicationContext)
        setContentView(content())
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        refresh()
    }

    override fun onStop() {
        resumed = false
        clearPreview()
        dialog?.dismiss()
        dialog = null
        super.onStop()
    }

    override fun onDestroy() {
        worker.shutdown()
        clearPreview()
        super.onDestroy()
    }

    private fun content(): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        val color = TypedValue()
        theme.resolveAttribute(android.R.attr.colorBackground, color, true)
        setBackgroundColor(color.data)
        val bar = LinearLayout(this@AgentBrowserUserControlActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(icon(R.drawable.ic_navigation_back, R.string.browser_user_control_back) { finish() })
            title = TextView(this@AgentBrowserUserControlActivity).apply {
                text = getString(R.string.browser_user_control_title)
                textSize = 16f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_VERTICAL
            }
            addView(title, LinearLayout.LayoutParams(0, dp(48), 1f).apply { gravity = Gravity.CENTER_VERTICAL })
            actions = LinearLayout(this@AgentBrowserUserControlActivity).apply {
                addView(icon(R.drawable.ic_input_keyboard, R.string.browser_user_control_input) { enterText() })
                addView(icon(R.drawable.ic_composer_rotate, R.string.browser_user_control_refresh) { refresh() })
                addView(icon(R.drawable.ic_agent_progress_complete, R.string.browser_user_control_done) { complete() })
            }
            addView(actions)
        }
        addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)))
        val surface = FrameLayout(this@AgentBrowserUserControlActivity)
        image = ImageView(this@AgentBrowserUserControlActivity).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = getString(R.string.browser_user_control_title)
            setOnTouchListener { _, event -> touch(event) }
        }
        surface.addView(image, FrameLayout.LayoutParams(-1, -1))
        spinner = ProgressBar(this@AgentBrowserUserControlActivity)
        surface.addView(spinner, FrameLayout.LayoutParams(dp(36), dp(36), Gravity.CENTER))
        addView(surface, LinearLayout.LayoutParams(-1, 0, 1f))
        status = TextView(this@AgentBrowserUserControlActivity).apply {
            textSize = 13f
            setPadding(dp(16), dp(8), dp(16), dp(8))
            maxLines = 3
        }
        addView(status, LinearLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun icon(resource: Int, label: Int, click: () -> Unit) = ImageButton(this).apply {
        setImageResource(resource)
        contentDescription = getString(label)
        tooltipText = contentDescription
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        setPadding(dp(13), dp(13), dp(13), dp(13))
        layoutParams = LinearLayout.LayoutParams(dp(44), dp(48))
        setOnClickListener { click() }
    }

    private fun refresh() {
        if (busy) { refreshQueued = true; return }
        val width = (resources.displayMetrics.widthPixels / resources.displayMetrics.density).toInt().coerceIn(240, 1024)
        val height = ((image.height.takeIf { it > 0 } ?: resources.displayMetrics.heightPixels) /
            resources.displayMetrics.density).toInt().coerceIn(240, 2560)
        runTask {
            val current = loadRecord()
            if (current.state == "returned") {
                control.reconcileReturned(current)
                return@runTask UiResult(current, completed = true)
            }
            if (current.state == "interrupted") {
                control.reconcileReturned(current)
                throw AgentBrowserControlFailure(current.interruptionCode)
            }
            if (current.state != "active") throw AgentBrowserControlFailure("browser_user_request_stale")
            val observation = control.snapshot(current, width, height)
            val encoded = observation.optString("data_b64")
            val bytes = if (encoded.isNotBlank()) Base64.decode(encoded, Base64.NO_WRAP) else null
            val preview = try { bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } } finally { bytes?.fill(0) }
            UiResult(current, observation, preview)
        }
    }

    private fun loadRecord(): AgentBrowserUserRequest = control.current(
        intent.getStringExtra(AgentBrowserUserControl.EXTRA_KEY).orEmpty(),
        intent.getStringExtra(AgentBrowserUserControl.EXTRA_GENERATION).orEmpty())

    private fun touch(event: MotionEvent): Boolean {
        if (busy || revision.isEmpty()) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { touchX = event.x; touchY = event.y }
            MotionEvent.ACTION_UP -> {
                val inverse = Matrix()
                if (!image.imageMatrix.invert(inverse)) return true
                val point = floatArrayOf(event.x - image.paddingLeft, event.y - image.paddingTop)
                inverse.mapPoints(point)
                val preview = bitmap ?: return true
                if (point[0] !in 0f..preview.width.toFloat() || point[1] !in 0f..preview.height.toFloat()) return true
                val dy = event.y - touchY
                if (kotlin.math.abs(dy) > dp(24)) {
                    act(mapOf("operation" to "scroll", "delta_y" to (-dy / resources.displayMetrics.density).coerceIn(-2560f, 2560f)))
                } else if (kotlin.math.abs(event.x - touchX) < dp(24)) {
                    act(mapOf("operation" to "pointer", "x" to point[0], "y" to point[1]))
                    image.performClick()
                }
            }
        }
        return true
    }

    private fun act(action: AgentNativeJsonObject) {
        val current = record ?: return
        val observedRevision = revision
        runTask {
            control.operate(current, action + mapOf("page_id" to current.pageId, "revision" to observedRevision))
            UiResult(current, refreshAfter = true)
        }
    }

    private fun enterText() {
        if (busy || revision.isEmpty()) return
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            setSaveEnabled(false)
        }
        val show = CheckBox(this).apply {
            text = getString(R.string.browser_user_control_show_input)
            setOnCheckedChangeListener { _, checked ->
                input.transformationMethod = if (checked) null else android.text.method.PasswordTransformationMethod.getInstance()
            }
        }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(8))
            addView(input)
            addView(show)
        }
        dialog = AlertDialog.Builder(this).setTitle(R.string.browser_user_control_input).setView(layout)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                val value = input.text.toString()
                input.text.clear()
                act(mapOf("operation" to "insert_text", "value" to value))
            }.create().apply {
                setOnDismissListener { input.text.clear() }
                window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                show()
            }
    }

    private fun showPageDialog(observation: JSONObject) {
        val observedDialog = observation.optJSONObject("dialog") ?: return
        dialog?.dismiss()
        val input = EditText(this).apply {
            setSaveEnabled(false)
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        val builder = AlertDialog.Builder(this).setTitle(observedDialog.optString("type"))
            .setMessage(observedDialog.optString("message"))
            .setCancelable(false)
            .setNegativeButton(android.R.string.cancel) { _, _ -> act(mapOf("operation" to "dialog", "accept" to false)) }
            .setPositiveButton(android.R.string.ok) { _, _ ->
                val value = input.text.toString()
                input.text.clear()
                act(mapOf("operation" to "dialog", "accept" to true, "value" to value))
            }
        if (observedDialog.optString("type") == "prompt") builder.setView(input)
        dialog = builder.create().apply {
            setOnDismissListener { input.text.clear() }
            window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            show()
        }
    }

    private fun complete() {
        val current = record ?: return
        runTask { control.finish(current); UiResult(current, completed = true) }
    }

    private fun runTask(operation: () -> UiResult) {
        if (busy || !resumed) return
        busy = true
        spinner.visibility = View.VISIBLE
        for (index in 0 until actions.childCount) actions.getChildAt(index).isEnabled = false
        worker.execute {
            val result = runCatching(operation)
            runOnUiThread {
                busy = false
                if (result.getOrNull()?.completed == true) {
                    result.getOrNull()?.preview?.recycle()
                    if (!isDestroyed && !isFinishing) finish()
                    return@runOnUiThread
                }
                if (isDestroyed || isFinishing || !resumed) {
                    result.getOrNull()?.preview?.recycle()
                    return@runOnUiThread
                }
                spinner.visibility = View.GONE
                for (index in 0 until actions.childCount) actions.getChildAt(index).isEnabled = true
                result.onSuccess { value ->
                    if (value.completed) { finish(); return@onSuccess }
                    record = value.record
                    value.observation?.let { observed ->
                        clearPreview()
                        bitmap = value.preview
                        image.setImageBitmap(bitmap)
                        revision = observed.optString("revision")
                        title.text = observed.optString("url").ifBlank { getString(R.string.browser_user_control_title) }
                        status.text = ""
                        showPageDialog(observed)
                    }
                    refreshQueued = refreshQueued || value.refreshAfter
                }.onFailure { error ->
                    revision = ""
                    status.text = getString(R.string.browser_user_control_error,
                        (error as? AgentBrowserControlFailure)?.code ?: "browser_user_control_unavailable")
                }
                if (refreshQueued && !isFinishing) { refreshQueued = false; refresh() }
            }
        }
    }

    private fun clearPreview() {
        image.setImageDrawable(null)
        bitmap?.recycle()
        bitmap = null
        revision = ""
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private data class UiResult(val record: AgentBrowserUserRequest, val observation: JSONObject? = null,
        val preview: Bitmap? = null, val refreshAfter: Boolean = false, val completed: Boolean = false)
}
