package com.galaxyssi.chat

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceError
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import org.json.JSONTokener

internal enum class WechatArticleBrowserFailure { BODY_NOT_READY, BODY_UNSTABLE, LOAD, TOO_LARGE, SNAPSHOT, RENDERER }

/** Chromium loads the document; the HTTP downloader must never refetch its HTML. */
@SuppressLint("SetJavaScriptEnabled")
internal class WechatArticleBrowser(
    context: Context,
    private val onArticle: (String, String) -> Unit,
    private val onVerification: () -> Unit,
    private val onFailure: (WechatArticleBrowserFailure) -> Unit,
    private val readinessTimeoutMillis: Long = 120_000,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var closed = false
    private var paused = false
    private var delivered = false
    private var generation = 0
    private var deadline = 0L
    private var lastSignature = ""
    private var stable = 0
    private var httpError = false
    private val timeout = Runnable {
        fail(when {
            httpError -> WechatArticleBrowserFailure.LOAD
            lastSignature.isEmpty() -> WechatArticleBrowserFailure.BODY_NOT_READY
            else -> WechatArticleBrowserFailure.BODY_UNSTABLE
        })
    }
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
                httpError = false
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (!request.isForMainFrame) return
                Log.w("WechatArticleSave", "stage=browser_network code=${error.errorCode}")
                if (!paused) fail(WechatArticleBrowserFailure.LOAD)
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (!request.isForMainFrame) return
                httpError = true
                // An HTTP error response can contain a verification page. Let the DOM probe recognize it.
                Log.w("WechatArticleSave", "stage=browser_http code=${response.statusCode}")
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                fail(WechatArticleBrowserFailure.RENDERER)
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
        deadline = SystemClock.elapsedRealtime() + readinessTimeoutMillis
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(timeout, readinessTimeoutMillis)
        handler.postDelayed(::poll, 750)
    }

    fun continueAfterVerification() {
        if (closed || delivered) return
        paused = false
        deadline = SystemClock.elapsedRealtime() + readinessTimeoutMillis
        lastSignature = ""
        stable = 0
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(timeout, readinessTimeoutMillis)
        poll()
    }

    private fun poll() {
        if (closed || paused || delivered) return
        if (SystemClock.elapsedRealtime() >= deadline) { timeout.run(); return }
        val token = generation
        view.evaluateJavascript(READINESS) { encoded ->
            if (closed || paused || delivered) return@evaluateJavascript
            if (token != generation) { later(); return@evaluateJavascript }
            val state = runCatching { JSONObject(JSONTokener(encoded).nextValue() as String) }.getOrNull()
            when (state?.optString("phase")) {
                "verify" -> {
                    paused = true
                    handler.removeCallbacksAndMessages(null)
                    onVerification()
                }
                "oversize" -> fail(WechatArticleBrowserFailure.TOO_LARGE)
                "ready" -> {
                    val signature = state.optString("signature")
                    stable = if (signature == lastSignature) stable + 1 else 0
                    lastSignature = signature
                    if (!httpError && stable >= 2 && WechatArticleDocuments.articleUrl(view.url.orEmpty()) != null) {
                        capture(token, signature)
                    } else later()
                }
                else -> { lastSignature = ""; stable = 0; later() }
            }
        }
    }

    private fun capture(token: Int, signature: String) {
        val expected = JSONObject.quote(signature)
        view.evaluateJavascript("($DOCUMENT_PROBE)($expected)") { encoded ->
            if (closed || paused || delivered) return@evaluateJavascript
            if (token != generation) { later(); return@evaluateJavascript }
            val snapshot = runCatching { JSONTokener(encoded).nextValue() }.getOrNull()
            val url = view.url.orEmpty()
            if (snapshot == false) {
                fail(WechatArticleBrowserFailure.TOO_LARGE)
                return@evaluateJavascript
            }
            val html = snapshot as? String
            if (html == null) {
                lastSignature = ""
                stable = 0
                later()
                return@evaluateJavascript
            }
            if (httpError || WechatArticleDocuments.articleUrl(url) == null) {
                fail(WechatArticleBrowserFailure.SNAPSHOT)
                return@evaluateJavascript
            }
            delivered = true
            handler.removeCallbacksAndMessages(null)
            onArticle(url, html)
        }
    }

    private fun later() { handler.postDelayed(::poll, 750) }
    private fun fail(reason: WechatArticleBrowserFailure) {
        if (closed || delivered) return
        delivered = true
        handler.removeCallbacksAndMessages(null)
        onFailure(reason)
    }

    fun close() {
        if (closed) return
        closed = true
        handler.removeCallbacksAndMessages(null)
        view.stopLoading()
        view.destroy()
    }

    companion object {
        // Image URLs are resolved separately during export; image requests must not gate the DOM.
        private val DOCUMENT_PROBE = """
            (expected => {
              const body = document.querySelector('#js_content');
              const response = (phase, signature) => expected == null ? JSON.stringify({phase,signature}) : null;
              if (location.pathname.includes('/secitptpage/verify') || (!body && document.querySelector('#js_verify')))
                return response('verify');
              const title = document.querySelector('#activity-name')?.textContent?.trim()
                || document.querySelector('meta[property="og:title"]')?.content?.trim();
              if (!body || !title || document.readyState === 'loading') return response('loading');
              const html = body.innerHTML;
              if (html.length > 8388608) return response('oversize');
              if (!body.textContent.trim() && !body.querySelector('img')) return response('loading');
              let hash = 0;
              for (let i = 0; i < html.length; i++) hash = ((hash << 5) - hash + html.charCodeAt(i)) | 0;
              const signature = title + ':' + html.length + ':' + hash;
              if (expected == null) return response('ready', signature);
              if (expected !== signature) return null;
              const snapshot = document.documentElement.outerHTML;
              return snapshot.length <= 8388608 ? snapshot : false;
            })
        """.trimIndent()
        internal val READINESS = "$DOCUMENT_PROBE(null)"
    }
}
