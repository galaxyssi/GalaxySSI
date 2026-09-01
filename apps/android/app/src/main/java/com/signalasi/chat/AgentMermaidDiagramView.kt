package com.signalasi.chat

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.roundToInt

internal class AgentMermaidDiagramCard(
    private val activity: Activity,
    private val block: AgentRichBlock
) : LinearLayout(activity) {
    internal val previewFrame = AgentMermaidAspectFrame(activity)
    internal val previewImage = ImageView(activity)
    internal val saveButton = ImageButton(activity)

    private var previewBitmap: Bitmap? = null
    private var renderer: AgentMermaidWebView? = null

    init {
        orientation = VERTICAL
        clipChildren = false

        previewFrame.apply {
            background = roundedBackground("#FFFFFF", "#E2E7EB")
            clipToOutline = true
        }
        previewImage.apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.WHITE)
            contentDescription = activity.getString(R.string.rich_output_diagram_open)
            visibility = View.INVISIBLE
            isClickable = true
            isFocusable = true
            setOnClickListener { showFullscreen() }
        }
        previewFrame.addView(
            previewImage,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        val progress = ProgressBar(activity).apply {
            isIndeterminate = true
            contentDescription = activity.getString(R.string.rich_output_loading)
        }
        previewFrame.addView(progress, FrameLayout.LayoutParams(dp(32), dp(32), Gravity.CENTER))

        addView(
            previewFrame,
            LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )

        saveButton.apply {
            setImageResource(R.drawable.ic_rich_download)
            contentDescription = activity.getString(R.string.rich_output_diagram_save)
            background = ColorDrawable(Color.TRANSPARENT)
            setPadding(dp(8), dp(8), dp(8), dp(8))
            isEnabled = false
            alpha = 0.35f
            setOnClickListener { savePreview() }
        }
        addView(LinearLayout(activity).apply {
            orientation = HORIZONTAL
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            addView(saveButton, LayoutParams(dp(40), dp(40)))
        }, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)))

        previewFrame.post {
            if (previewFrame.width > 0 && previewFrame.height > 0) {
                renderPreview(progress)
            }
        }
    }

    private fun renderPreview(progress: ProgressBar) {
        if (renderer != null || previewBitmap != null) return
        val webView = AgentMermaidWebView(activity)
        webView.onRenderFailed = {
            progress.visibility = View.GONE
            releaseRenderer(webView)
            showPreviewError()
        }
        renderer = webView
        previewFrame.addView(
            webView,
            0,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        webView.render(block.text) {
            webView.postDelayed({ materializePreview(webView, progress) }, RENDER_SETTLE_MS)
        }
    }

    private fun materializePreview(webView: AgentMermaidWebView, progress: ProgressBar) {
        if (webView.width <= 0 || webView.height <= 0 || activity.isDestroyed) return
        val bitmap = runCatching { webView.captureBitmap() }.getOrNull()
        if (bitmap == null) {
            progress.visibility = View.GONE
            releaseRenderer(webView)
            showPreviewError()
            return
        }
        previewBitmap = bitmap
        previewImage.setImageBitmap(bitmap)
        previewImage.visibility = View.VISIBLE
        progress.visibility = View.GONE
        saveButton.isEnabled = true
        saveButton.alpha = 1f
        releaseRenderer(webView)
    }

    private fun releaseRenderer(webView: AgentMermaidWebView) {
        previewFrame.removeView(webView)
        webView.destroySafely()
        if (renderer === webView) renderer = null
    }

    private fun showPreviewError() {
        if (previewFrame.findViewWithTag<View>(ERROR_TAG) != null) return
        previewFrame.addView(TextView(activity).apply {
            tag = ERROR_TAG
            text = activity.getString(R.string.rich_output_diagram_failed)
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.parseColor("#66717D"))
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))
    }

    private fun showFullscreen() {
        val dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        val webView = AgentMermaidWebView(activity).apply {
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            render(block.text)
        }
        val viewport = SignalASIPinchZoomViewport(activity).apply {
            setBackgroundColor(Color.WHITE)
            attach(webView)
        }
        val back = ImageButton(activity).apply {
            setImageResource(R.drawable.ic_navigation_back)
            contentDescription = activity.getString(android.R.string.cancel)
            background = ColorDrawable(Color.TRANSPARENT)
            setPadding(dp(11), dp(11), dp(11), dp(11))
            setOnClickListener { dialog.dismiss() }
        }
        dialog.setContentView(LinearLayout(activity).apply {
            orientation = VERTICAL
            setBackgroundColor(Color.WHITE)
            addView(LinearLayout(activity).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), 0, dp(8), 0)
                addView(back, LayoutParams(dp(48), dp(48)))
                addView(TextView(activity).apply {
                    text = block.title.ifBlank { activity.getString(R.string.rich_output_diagram) }
                    textSize = 16f
                    setTextColor(Color.parseColor("#14202B"))
                    maxLines = 1
                }, LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)))
            addView(viewport, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        })
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.WHITE))
        dialog.setOnDismissListener { webView.destroySafely() }
        dialog.show()
    }

    private fun savePreview() {
        val bitmap = previewBitmap ?: return
        saveButton.isEnabled = false
        saveButton.alpha = 0.35f
        SAVE_EXECUTOR.execute {
            val saved = runCatching { savePng(activity, bitmap) }
            activity.runOnUiThread {
                if (activity.isDestroyed) return@runOnUiThread
                saved.onSuccess { location ->
                    saveButton.setImageResource(R.drawable.ic_rich_saved)
                    saveButton.contentDescription = activity.getString(R.string.rich_output_saved)
                    saveButton.alpha = 1f
                    Toast.makeText(
                        activity,
                        activity.getString(R.string.rich_output_diagram_saved, location),
                        Toast.LENGTH_SHORT
                    ).show()
                }.onFailure {
                    saveButton.isEnabled = true
                    saveButton.alpha = 1f
                    Toast.makeText(activity, R.string.rich_output_download_failed, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    override fun onDetachedFromWindow() {
        renderer?.destroySafely()
        renderer = null
        super.onDetachedFromWindow()
    }

    private fun roundedBackground(fill: String, stroke: String) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(8).toFloat()
        setColor(Color.parseColor(fill))
        setStroke(dp(1), Color.parseColor(stroke))
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

    private companion object {
        const val ERROR_TAG = "signalasi-mermaid-error"
        const val RENDER_SETTLE_MS = 80L
        val SAVE_EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "signalasi-mermaid-save").apply { isDaemon = true }
        }

        fun savePng(context: Context, bitmap: Bitmap): String {
            val name = "signalasi-diagram-${System.currentTimeMillis()}.png"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "image/png")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SignalASI")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val destination = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: error("MediaStore did not create the diagram")
                try {
                    resolver.openOutputStream(destination, "w")?.use { output ->
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                    } ?: error("MediaStore did not open the diagram")
                    resolver.update(destination, ContentValues().apply {
                        put(MediaStore.Downloads.IS_PENDING, 0)
                    }, null, null)
                } catch (error: Throwable) {
                    resolver.delete(destination, null, null)
                    throw error
                }
                return "Download/SignalASI/$name"
            }

            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "SignalASI"
            ).apply { mkdirs() }
            FileOutputStream(File(directory, name)).use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
            }
            return "Download/SignalASI/$name"
        }
    }
}

internal class AgentMermaidAspectFrame(context: Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = (width * HEIGHT_TO_WIDTH_RATIO).roundToInt()
        super.onMeasure(
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        )
    }

    private companion object {
        const val HEIGHT_TO_WIDTH_RATIO = 1.2f
    }
}

@SuppressLint("SetJavaScriptEnabled", "AddJavascriptInterface")
internal class AgentMermaidWebView(context: Context) : WebView(context) {
    var onRenderFailed: () -> Unit = {}
    private var onRendered: () -> Unit = {}

    init {
        setBackgroundColor(Color.WHITE)
        isVerticalScrollBarEnabled = false
        isHorizontalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = false
        settings.databaseEnabled = false
        settings.allowContentAccess = false
        settings.allowFileAccess = true
        settings.allowFileAccessFromFileURLs = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.blockNetworkLoads = true
        settings.loadsImagesAutomatically = false
        settings.javaScriptCanOpenWindowsAutomatically = false
        settings.setSupportMultipleWindows(false)
        settings.builtInZoomControls = false
        settings.displayZoomControls = false
        addJavascriptInterface(RenderBridge(), BRIDGE_NAME)
        webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = true

            @Deprecated("Deprecated in Android")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean = true

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                val uri = request?.url ?: return blockedResponse()
                val allowed = uri.scheme == "data" || (
                    uri.scheme == "file" &&
                        uri.path == "/android_asset/mermaid/mermaid.min.js"
                    )
                return if (allowed) super.shouldInterceptRequest(view, request) else blockedResponse()
            }
        }
    }

    fun render(source: String, onRendered: () -> Unit = {}) {
        this.onRendered = onRendered
        val encoded = Base64.encodeToString(source.take(MAX_SOURCE_CHARS).toByteArray(), Base64.NO_WRAP)
        loadDataWithBaseURL(
            ASSET_BASE_URL,
            document(encoded),
            "text/html",
            "utf-8",
            null
        )
    }

    fun captureBitmap(): Bitmap {
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        Canvas(output).apply {
            drawColor(Color.WHITE)
            this@AgentMermaidWebView.draw(this)
        }
        return output
    }

    fun destroySafely() {
        stopLoading()
        loadUrl("about:blank")
        removeJavascriptInterface(BRIDGE_NAME)
        clearHistory()
        removeAllViews()
        destroy()
    }

    private fun document(sourceBase64: String): String = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; font-src 'none'; form-action 'none'; base-uri 'none'">
          <script src="mermaid.min.js"></script>
          <style>
            html,body,#diagram{width:100%;height:100%;margin:0;overflow:hidden;background:#fff}
            body{font-family:system-ui,-apple-system,sans-serif;color:#14202b}
            #diagram{display:flex;align-items:center;justify-content:center;padding:12px;box-sizing:border-box}
            #diagram svg{display:block;width:100%!important;height:100%!important;max-width:none!important}
          </style>
        </head>
        <body><div id="diagram"></div>
        <script>
          (() => {
            const bridge = window.$BRIDGE_NAME;
            const bytes = Uint8Array.from(atob('$sourceBase64'), value => value.charCodeAt(0));
            const source = new TextDecoder('utf-8').decode(bytes);
            mermaid.initialize({
              startOnLoad: false,
              securityLevel: 'strict',
              suppressErrorRendering: true,
              theme: 'neutral',
              fontFamily: 'system-ui, -apple-system, sans-serif',
              flowchart: { useMaxWidth: true, htmlLabels: false },
              sequence: { useMaxWidth: true },
              maxTextSize: $MAX_SOURCE_CHARS
            });
            mermaid.render('signalasi-mermaid', source).then(result => {
              const root = document.getElementById('diagram');
              root.innerHTML = result.svg;
              const svg = root.querySelector('svg');
              if (svg) {
                svg.removeAttribute('width');
                svg.removeAttribute('height');
                svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
              }
              requestAnimationFrame(() => requestAnimationFrame(() => bridge.rendered()));
            }).catch(() => bridge.failed());
          })();
        </script></body></html>
    """.trimIndent()

    private fun blockedResponse(): WebResourceResponse = WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        emptyMap(),
        null
    )

    private inner class RenderBridge {
        @JavascriptInterface
        fun rendered() {
            post { onRendered() }
        }

        @JavascriptInterface
        fun failed() {
            post { onRenderFailed() }
        }
    }

    private companion object {
        const val BRIDGE_NAME = "SignalASIMermaidBridge"
        const val ASSET_BASE_URL = "file:///android_asset/mermaid/"
        const val MAX_SOURCE_CHARS = 32_000
    }
}
