package com.galaxyssi.chat

import android.app.Activity
import android.app.Application
import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import java.util.concurrent.Executors
import java.util.concurrent.Future

internal class ChatImagePreviewDialog(
    private val activity: Activity,
    private val uri: Uri,
    private val title: String,
    private val mimeType: String = "",
    private val sizeBytes: Long = 0,
    private val onSave: (() -> Result<String>)? = null
) : Dialog(activity, android.R.style.Theme_Black_NoTitleBar) {
    private val appContext = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val state = ChatImageSaveState()
    private var source: ChatImagePreviewSource? = null
    private var bitmap: Bitmap? = null
    private var loading: Future<*>? = null
    private var released = false
    private val image = ImageView(activity).apply {
        tag = "chat-image-preview-image"
        contentDescription = title
        scaleType = ImageView.ScaleType.FIT_CENTER
    }
    private val details = TextView(activity).apply {
        tag = "chat-image-preview-details"
        textSize = 12f
        setTextColor(Color.parseColor("#A6A6AA"))
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }
    private val save = Button(activity).apply {
        tag = "chat-image-preview-save"
        textSize = 14f
        isAllCaps = false
        includeFontPadding = false
        minimumWidth = dp(88)
        minHeight = dp(48)
        gravity = Gravity.CENTER
        setPadding(dp(12), 0, dp(12), 0)
        background = ColorDrawable(Color.TRANSPARENT)
        compoundDrawablePadding = dp(8)
        setOnClickListener { saveImage() }
    }
    private val progress = ProgressBar(activity).apply {
        isIndeterminate = true
        indeterminateTintList = ColorStateList.valueOf(Color.WHITE)
        visibility = View.GONE
    }
    private val previewStatus = TextView(activity).apply {
        gravity = Gravity.CENTER
        textSize = 14f
        setTextColor(Color.LTGRAY)
        setText(R.string.image_preview_loading)
    }
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStopped(owner: Activity) { if (owner === activity) dismiss() }
        override fun onActivityDestroyed(owner: Activity) { if (owner === activity) dismiss() }
        override fun onActivityCreated(owner: Activity, state: Bundle?) = Unit
        override fun onActivityStarted(owner: Activity) = Unit
        override fun onActivityResumed(owner: Activity) = Unit
        override fun onActivityPaused(owner: Activity) = Unit
        override fun onActivitySaveInstanceState(owner: Activity, state: Bundle) = Unit
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setOwnerActivity(activity)
        val root = LinearLayout(activity).apply {
            tag = "chat-image-preview"
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#101113"))
        }
        val toolbar = FrameLayout(activity)
        toolbar.addView(TextView(activity).apply {
            setText(R.string.rich_output_type_image)
            gravity = Gravity.CENTER
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
        }, FrameLayout.LayoutParams(-1, -1).apply { marginStart = dp(56); marginEnd = dp(56) })
        toolbar.addView(ImageButton(activity).apply {
            tag = "chat-image-preview-back"
            setImageResource(R.drawable.ic_navigation_back)
            imageTintList = ColorStateList.valueOf(Color.WHITE)
            setPadding(dp(13), dp(13), dp(13), dp(13))
            background = ColorDrawable(Color.TRANSPARENT)
            contentDescription = activity.getString(R.string.agent_image_preview_close)
            setOnClickListener { dismiss() }
        }, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.START or Gravity.CENTER_VERTICAL).apply { marginStart = dp(4) })
        root.addView(toolbar, LinearLayout.LayoutParams(-1, dp(56)))
        val viewport = GalaxySSIPinchZoomViewport(activity).apply { attach(image) }
        val body = FrameLayout(activity).apply {
            addView(viewport, FrameLayout.LayoutParams(-1, -1))
            addView(previewStatus, FrameLayout.LayoutParams(-1, -1))
        }
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        val footer = LinearLayout(activity).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(4), dp(8))
            addView(details, LinearLayout.LayoutParams(0, -2, 1f))
            addView(progress, LinearLayout.LayoutParams(dp(18), dp(18)))
            addView(save, LinearLayout.LayoutParams(-2, dp(48)))
        }
        root.addView(footer, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.parseColor("#101113")))
            clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            statusBarColor = Color.parseColor("#101113")
            navigationBarColor = Color.parseColor("#101113")
            decorView.systemUiVisibility = 0
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }
        renderSave()
        activity.application.registerActivityLifecycleCallbacks(lifecycle)
        setOnDismissListener { release() }
        loadImage()
    }

    private fun loadImage() {
        val metrics = activity.resources.displayMetrics
        val width = (metrics.widthPixels * 2).coerceAtMost(2560)
        val height = (metrics.heightPixels * 2).coerceAtMost(2560)
        loading = PREVIEWS.submit {
            val resolved = runCatching { ChatImagePreviewSource.resolve(appContext, uri, title, mimeType, sizeBytes) }.getOrNull()
            val loaded = runCatching { AgentImagePipeline.loadPreview(appContext, uri, width, height) }.getOrNull()
            main.post {
                if (released || !isShowing) { loaded?.recycle(); return@post }
                source = resolved
                val type = ChatImagePreviewSource.formatLabel(resolved?.mimeType.orEmpty())
                details.text = listOf(type, resolved?.sizeBytes?.takeIf { it > 0 }?.let {
                    Formatter.formatShortFileSize(activity, it)
                }.orEmpty()).filter(String::isNotBlank).joinToString(" · ")
                bitmap = loaded
                image.setImageBitmap(loaded)
                previewStatus.visibility = if (loaded == null) View.VISIBLE else View.GONE
                if (loaded == null) previewStatus.setText(R.string.rich_output_load_failed)
                renderSave()
            }
        }
    }

    private fun saveImage() {
        val current = source ?: return
        if (!state.begin()) return
        renderSave()
        SAVES.execute {
            val result = runCatching { (onSave?.invoke() ?: current.save(appContext)).getOrThrow() }
            main.post {
                if (released || !isShowing) return@post
                state.finish(result.isSuccess)
                renderSave()
                Toast.makeText(activity, if (result.isSuccess) R.string.peer_attachment_saved
                    else R.string.rich_output_download_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun renderSave() {
        val saving = state.status == ChatImageSaveState.Status.SAVING
        val saved = state.status == ChatImageSaveState.Status.SAVED
        save.isEnabled = source != null && !saving && !saved
        save.setText(when { saved -> R.string.rich_output_saved; saving -> R.string.image_preview_saving; else -> R.string.peer_attachment_save })
        save.contentDescription = save.text
        save.setTextColor(if (saved) Color.parseColor("#71DE84") else Color.WHITE)
        val drawable = if (saving) null else activity.getDrawable(if (saved) R.drawable.ic_rich_saved else R.drawable.ic_rich_download)
            ?.mutate()?.apply { setTint(if (saved) Color.parseColor("#71DE84") else Color.WHITE); setBounds(0, 0, dp(22), dp(22)) }
        save.setCompoundDrawablesRelative(drawable, null, null, null)
        progress.visibility = if (saving) View.VISIBLE else View.GONE
        save.alpha = if (source == null) 0.45f else 1f
    }

    private fun release() {
        if (released) return
        released = true
        activity.application.unregisterActivityLifecycleCallbacks(lifecycle)
        loading?.cancel(true)
        image.setImageDrawable(null)
        bitmap?.recycle()
        bitmap = null
        source = null
    }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density + 0.5f).toInt()

    private companion object {
        val PREVIEWS = Executors.newFixedThreadPool(2) { Thread(it, "galaxyssi-image-preview").apply { isDaemon = true } }
        val SAVES = Executors.newSingleThreadExecutor { Thread(it, "galaxyssi-image-save").apply { isDaemon = true } }
    }
}

internal fun MainActivity.showAgentImagePreview(uri: Uri, title: String, mimeType: String = "", sizeBytes: Long = 0,
                                               onSave: (() -> Result<String>)? = null) {
    if (!isFinishing && !isDestroyed) ChatImagePreviewDialog(this, uri, title, mimeType, sizeBytes, onSave).show()
}
