package com.galaxyssi.chat

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import org.json.JSONTokener

/** Chromium loads the document; the HTTP downloader must never refetch its HTML. */
@SuppressLint("SetJavaScriptEnabled")
internal class WechatArticleBrowser(
    context: Context,
    private val onArticle: (String, String) -> Unit,
    private val onVerification: () -> Unit,
    private val onFailure: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var closed = false
    private var paused = false
    private var delivered = false
    private var generation = 0
    private var deadline = 0L
    private var lastSignature = ""
    private var stable = 0
    val view = WebView(context).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.safeBrowsingEnabled = true
        settings.mediaPlaybackRequiresUserGesture = true
        settings.setSupportMultipleWindows(false)
        importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
        webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
        }
        webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !WechatArticleBrowserPolicy.allowedNavigation(request.url.toString(), request.isForMainFrame)

            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                generation++
                lastSignature = ""
                stable = 0
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                fail()
                return true
            }
        }
    }

    fun load(url: String) {
        require(WechatArticleDocuments.articleUrl(url) != null)
        view.loadUrl(url)
        observeLoadedPage()
    }

    internal fun observeLoadedPage() {
        deadline = SystemClock.elapsedRealtime() + 120_000
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(::poll, 750)
    }

    fun continueAfterVerification() {
        if (closed || delivered) return
        paused = false
        deadline = SystemClock.elapsedRealtime() + 120_000
        lastSignature = ""
        stable = 0
        handler.removeCallbacksAndMessages(null)
        poll()
    }

    private fun poll() {
        if (closed || paused || delivered) return
        if (SystemClock.elapsedRealtime() >= deadline) { fail(); return }
        val token = generation
        view.evaluateJavascript(READINESS) { encoded ->
            if (closed || paused || delivered) return@evaluateJavascript
            if (token != generation) { later(); return@evaluateJavascript }
            val state = runCatching { JSONObject(JSONTokener(encoded).nextValue() as String) }.getOrNull()
            when (state?.optString("phase")) {
                "verify" -> { paused = true; onVerification() }
                "oversize" -> fail()
                "ready" -> {
                    val signature = state.optString("signature")
                    stable = if (signature == lastSignature) stable + 1 else 0
                    lastSignature = signature
                    if (stable >= 2 && WechatArticleDocuments.articleUrl(view.url.orEmpty()) != null) {
                        capture(token)
                    } else later()
                }
                else -> { stable = 0; later() }
            }
        }
    }

    private fun capture(token: Int) {
        view.evaluateJavascript("document.documentElement.outerHTML.length <= 8388608 ? document.documentElement.outerHTML : null") { encoded ->
            if (closed || paused || delivered) return@evaluateJavascript
            if (token != generation) { later(); return@evaluateJavascript }
            val html = runCatching { JSONTokener(encoded).nextValue() as? String }.getOrNull()
            val url = view.url.orEmpty()
            if (html == null || WechatArticleDocuments.articleUrl(url) == null) { fail(); return@evaluateJavascript }
            delivered = true
            handler.removeCallbacksAndMessages(null)
            onArticle(url, html)
        }
    }

    private fun later() { handler.postDelayed(::poll, 750) }
    private fun fail() {
        if (closed || delivered) return
        delivered = true
        handler.removeCallbacksAndMessages(null)
        onFailure()
    }

    fun close() {
        if (closed) return
        closed = true
        handler.removeCallbacksAndMessages(null)
        view.stopLoading()
        view.destroy()
    }

    companion object {
        // Load lazy images without scrolling or modifying the user's visible WeChat page.
        internal val READINESS = """
            (() => {
              const body = document.querySelector('#js_content');
              if (!body && (document.querySelector('#js_verify') || location.href.includes('secitptpage/verify')))
                return JSON.stringify({phase:'verify'});
              const title = document.querySelector('#activity-name')?.textContent?.trim()
                || document.querySelector('meta[property="og:title"]')?.content?.trim();
              if (!body || !title || document.readyState !== 'complete') return JSON.stringify({phase:'loading'});
              const images = Array.from(body.querySelectorAll('img'));
              for (const img of images) {
                const source = img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-lazy-src');
                if (source && img.getAttribute('src') !== source) img.setAttribute('src', source);
                img.loading = 'eager';
              }
              if (images.some(img => !img.complete || img.naturalWidth === 0)) return JSON.stringify({phase:'loading'});
              const html = body.innerHTML;
              if (html.length > 8388608) return JSON.stringify({phase:'oversize'});
              if (!body.textContent.trim() && !images.length) return JSON.stringify({phase:'loading'});
              let hash = 0;
              for (let i = 0; i < html.length; i++) hash = ((hash << 5) - hash + html.charCodeAt(i)) | 0;
              return JSON.stringify({phase:'ready',signature:title + ':' + html.length + ':' + hash});
            })()
        """.trimIndent()
    }
}
