package com.signalasi.chat

import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.SystemClock
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient.FileChooserParams
import org.json.JSONObject
import org.json.JSONTokener
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Private renderer process used only after the bounded static fetcher detects a JS-only page. */
class AgentIsolatedWebRenderService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, RenderJob>()
    private val incoming = Messenger(Handler(Looper.getMainLooper(), ::handleMessage))

    override fun onCreate() {
        super.onCreate()
        WebView.setWebContentsDebuggingEnabled(false)
        renderCacheDirectory().apply {
            mkdirs()
            listFiles()?.forEach(File::delete)
        }
    }

    override fun onBind(intent: Intent?): IBinder = incoming.binder

    override fun onDestroy() {
        jobs.values.toList().forEach { it.cancel("renderer_process_stopped") }
        jobs.clear()
        clearRendererStorage()
        renderCacheDirectory().listFiles()?.forEach(File::delete)
        super.onDestroy()
    }

    private fun handleMessage(message: Message): Boolean {
        when (message.what) {
            AgentWebRenderContract.MSG_RENDER -> startRender(message)
            AgentWebRenderContract.MSG_CANCEL -> {
                val requestId = message.data.getString(AgentWebRenderContract.KEY_REQUEST_ID).orEmpty()
                jobs.remove(requestId)?.cancel("renderer_cancelled")
            }
            else -> return false
        }
        return true
    }

    private fun startRender(message: Message) {
        val requestId = message.data.getString(AgentWebRenderContract.KEY_REQUEST_ID).orEmpty()
        val url = message.data.getString(AgentWebRenderContract.KEY_URL).orEmpty()
        val reply = message.replyTo
        val timeoutMillis = message.data.getLong(AgentWebRenderContract.KEY_TIMEOUT_MILLIS)
            .coerceIn(MIN_TIMEOUT_MILLIS, MAX_TIMEOUT_MILLIS)
        val maxBytes = message.data.getLong(AgentWebRenderContract.KEY_MAX_BYTES)
            .coerceIn(1L, MAX_RENDER_BYTES)
        if (requestId.isBlank() || reply == null || !AgentWebRenderUrlPolicy.allows(url)) {
            reply?.sendFailure(requestId, "renderer_invalid_request")
            return
        }
        if (jobs.isNotEmpty()) {
            reply.sendFailure(requestId, "renderer_busy")
            return
        }
        val job = RenderJob(requestId, url, timeoutMillis, maxBytes, reply)
        jobs[requestId] = job
        job.start()
    }

    private fun renderCacheDirectory(): File = File(
        cacheDir,
        AgentWebRenderContract.CACHE_DIRECTORY
    )

    private fun clearRendererStorage() {
        runCatching {
            CookieManager.getInstance().apply {
                setAcceptCookie(false)
                removeAllCookies(null)
                flush()
            }
        }
        runCatching { WebStorage.getInstance().deleteAllData() }
    }

    private inner class RenderJob(
        private val requestId: String,
        private val initialUrl: String,
        private val timeoutMillis: Long,
        private val maxBytes: Long,
        private val reply: Messenger
    ) {
        private val finished = AtomicBoolean(false)
        private val startedAt = SystemClock.elapsedRealtime()
        private var pageFinishedAt = 0L
        private var currentUrl = initialUrl
        private var probeScheduled = false
        private var extractionFile: File? = null
        private var extractionOutput: BufferedOutputStream? = null
        private var webView: WebView? = null
        private val publicHosts = ConcurrentHashMap<String, Boolean>()
        private val timeoutAction = Runnable { fail("renderer_timeout") }

        fun start() {
            if (!AgentWebRenderUrlPolicy.resolvesToPublicAddress(initialUrl)) {
                fail("renderer_non_public_destination")
                return
            }
            clearRendererStorage()
            val view = runCatching { WebView(this@AgentIsolatedWebRenderService) }
                .getOrElse {
                    fail("renderer_webview_unavailable:${it.javaClass.simpleName}")
                    return
                }
            webView = view
            configure(view)
            mainHandler.postDelayed(timeoutAction, timeoutMillis)
            view.loadUrl(initialUrl, ARTICLE_HEADERS)
        }

        fun cancel(reason: String) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                fail(reason)
            } else {
                mainHandler.post { fail(reason) }
            }
        }

        @Suppress("SetJavaScriptEnabled")
        private fun configure(view: WebView) {
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = false
                databaseEnabled = false
                allowContentAccess = false
                allowFileAccess = false
                allowFileAccessFromFileURLs = false
                allowUniversalAccessFromFileURLs = false
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                cacheMode = WebSettings.LOAD_NO_CACHE
                loadsImagesAutomatically = false
                blockNetworkImage = true
                mediaPlaybackRequiresUserGesture = true
                safeBrowsingEnabled = true
                userAgentString = MOBILE_USER_AGENT
            }
            CookieManager.getInstance().apply {
                setAcceptCookie(false)
                setAcceptThirdPartyCookies(view, false)
            }
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest?) {
                    request?.deny()
                }

                override fun onGeolocationPermissionsShowPrompt(
                    origin: String?,
                    callback: GeolocationPermissions.Callback?
                ) {
                    callback?.invoke(origin, false, false)
                }

                override fun onShowFileChooser(
                    webView: WebView?,
                    filePathCallback: ValueCallback<Array<Uri>>?,
                    fileChooserParams: FileChooserParams?
                ): Boolean {
                    filePathCallback?.onReceiveValue(null)
                    return true
                }

                override fun onCreateWindow(
                    view: WebView?,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: Message?
                ): Boolean = false

                override fun onJsAlert(
                    view: WebView?,
                    url: String?,
                    message: String?,
                    result: JsResult?
                ): Boolean {
                    result?.confirm()
                    return true
                }

                override fun onJsConfirm(
                    view: WebView?,
                    url: String?,
                    message: String?,
                    result: JsResult?
                ): Boolean {
                    result?.cancel()
                    return true
                }

                override fun onJsPrompt(
                    view: WebView?,
                    url: String?,
                    message: String?,
                    defaultValue: String?,
                    result: JsPromptResult?
                ): Boolean {
                    result?.cancel()
                    return true
                }
            }
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?
                ): Boolean {
                    val target = request?.url?.toString().orEmpty()
                    if (request?.isForMainFrame != true) return false
                    if (!AgentWebRenderUrlPolicy.sameOrigin(initialUrl, target)) {
                        fail("renderer_cross_origin_navigation")
                        return true
                    }
                    currentUrl = target
                    return false
                }

                override fun shouldInterceptRequest(
                    view: WebView?,
                    request: WebResourceRequest?
                ): WebResourceResponse? {
                    val target = request?.url?.toString().orEmpty()
                    if (request?.isForMainFrame == true &&
                        !AgentWebRenderUrlPolicy.sameOrigin(initialUrl, target)
                    ) {
                        mainHandler.post { fail("renderer_cross_origin_navigation") }
                        return blockedResponse()
                    }
                    return if (allowsSubresource(target)) {
                        null
                    } else {
                        blockedResponse()
                    }
                }

                override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                    currentUrl = url.orEmpty().ifBlank { currentUrl }
                    pageFinishedAt = 0L
                    probeScheduled = false
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    currentUrl = url.orEmpty().ifBlank { currentUrl }
                    if (!AgentWebRenderUrlPolicy.sameOrigin(initialUrl, currentUrl)) {
                        fail("renderer_cross_origin_navigation")
                        return
                    }
                    pageFinishedAt = SystemClock.elapsedRealtime()
                    scheduleProbe(PROBE_INTERVAL_MILLIS)
                }

                override fun onReceivedSslError(
                    view: WebView?,
                    handler: SslErrorHandler?,
                    error: SslError?
                ) {
                    handler?.cancel()
                    fail("renderer_tls_error")
                }

                override fun onReceivedError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    error: WebResourceError?
                ) {
                    if (request?.isForMainFrame == true) {
                        fail("renderer_network_error:${error?.errorCode ?: 0}")
                    }
                }

                override fun onReceivedHttpError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    errorResponse: WebResourceResponse?
                ) {
                    if (request?.isForMainFrame == true && (errorResponse?.statusCode ?: 0) >= 400) {
                        fail("renderer_http_error:${errorResponse?.statusCode ?: 0}")
                    }
                }

                override fun onRenderProcessGone(
                    view: WebView?,
                    detail: RenderProcessGoneDetail?
                ): Boolean {
                    fail("renderer_process_gone")
                    return true
                }
            }
        }

        private fun scheduleProbe(delayMillis: Long) {
            if (finished.get() || probeScheduled) return
            probeScheduled = true
            mainHandler.postDelayed({
                probeScheduled = false
                probeDom()
            }, delayMillis)
        }

        private fun allowsSubresource(target: String): Boolean {
            if (!AgentWebRenderUrlPolicy.allowsSubresource(target)) return false
            val uri = runCatching { URI(target) }.getOrNull() ?: return false
            if (!uri.scheme.equals("https", true)) return true
            val host = uri.host?.lowercase().orEmpty()
            if (host.isBlank()) return false
            return publicHosts.computeIfAbsent(host) {
                AgentWebRenderUrlPolicy.resolvesToPublicAddress(target)
            }
        }

        private fun probeDom() {
            if (finished.get()) return
            val view = webView ?: return fail("renderer_webview_missing")
            view.evaluateJavascript(PROBE_SCRIPT) { raw ->
                if (finished.get()) return@evaluateJavascript
                val probe = decodeJavascriptObject(raw)
                if (probe == null) {
                    scheduleProbe(PROBE_INTERVAL_MILLIS)
                    return@evaluateJavascript
                }
                val finalUrl = probe.optString("url", currentUrl)
                if (!AgentWebRenderUrlPolicy.sameOrigin(initialUrl, finalUrl)) {
                    fail("renderer_cross_origin_navigation")
                    return@evaluateJavascript
                }
                currentUrl = finalUrl
                val now = probe.optLong("now", 0L)
                val mutationAt = probe.optLong("mutation_at", now)
                val pageAge = SystemClock.elapsedRealtime() - pageFinishedAt
                val mutationAge = (now - mutationAt).coerceAtLeast(0L)
                val ready = probe.optString("ready_state") == "complete"
                val settled = ready && pageAge >= MIN_PAGE_SETTLE_MILLIS &&
                    mutationAge >= MIN_MUTATION_SETTLE_MILLIS
                val forced = pageAge >= MAX_PAGE_SETTLE_MILLIS
                if (settled || forced) {
                    freezeSnapshot()
                } else {
                    scheduleProbe(PROBE_INTERVAL_MILLIS)
                }
            }
        }

        private fun freezeSnapshot() {
            val view = webView ?: return fail("renderer_webview_missing")
            view.evaluateJavascript(FREEZE_SCRIPT) { raw ->
                if (finished.get()) return@evaluateJavascript
                val metadata = decodeJavascriptObject(raw)
                    ?: return@evaluateJavascript fail("renderer_snapshot_failed")
                val finalUrl = metadata.optString("url", currentUrl)
                if (!AgentWebRenderUrlPolicy.sameOrigin(initialUrl, finalUrl)) {
                    fail("renderer_cross_origin_navigation")
                    return@evaluateJavascript
                }
                currentUrl = finalUrl
                val characters = metadata.optLong("length", 0L)
                if (characters <= 0L || characters > maxBytes) {
                    fail(if (characters <= 0L) "renderer_empty_dom" else "renderer_result_too_large")
                    return@evaluateJavascript
                }
                val directory = renderCacheDirectory().apply { mkdirs() }
                val pending = File(directory, "$requestId.html.pending")
                extractionFile = pending
                runCatching {
                    BufferedOutputStream(FileOutputStream(pending)).also { output ->
                        extractionOutput = output
                        readSnapshotChunk(view, output, 0L, characters, 0L)
                    }
                }.onFailure { fail("renderer_file_open_failed:${it.javaClass.simpleName}") }
            }
        }

        private fun readSnapshotChunk(
            view: WebView,
            output: BufferedOutputStream,
            offset: Long,
            totalCharacters: Long,
            bytesWritten: Long
        ) {
            if (finished.get()) {
                runCatching { output.close() }
                return
            }
            if (offset >= totalCharacters) {
                runCatching {
                    output.flush()
                    output.close()
                    extractionOutput = null
                }
                    .onFailure { return fail("renderer_file_write_failed:${it.javaClass.simpleName}") }
                val pending = extractionFile ?: return fail("renderer_result_missing")
                val completed = File(pending.parentFile, "$requestId.html")
                if (!pending.renameTo(completed)) {
                    fail("renderer_result_commit_failed")
                    return
                }
                extractionFile = completed
                complete(completed, bytesWritten)
                return
            }
            val script = """
                (() => {
                  const value = window.__signalasiFrozenDom || '';
                  const start = ${offset};
                  let end = Math.min(value.length, start + $SNAPSHOT_CHUNK_CHARS);
                  if (end < value.length) {
                    const code = value.charCodeAt(end - 1);
                    if (code >= 0xD800 && code <= 0xDBFF) end -= 1;
                  }
                  return JSON.stringify({ chunk: value.slice(start, end), end });
                })()
            """.trimIndent()
            view.evaluateJavascript(script) { raw ->
                if (finished.get()) {
                    runCatching { output.close() }
                    return@evaluateJavascript
                }
                val part = decodeJavascriptObject(raw)
                    ?: return@evaluateJavascript fail("renderer_chunk_decode_failed")
                val chunk = part.optString("chunk")
                val nextOffset = part.optLong("end", offset)
                if (nextOffset <= offset || nextOffset > totalCharacters) {
                    fail("renderer_chunk_bounds_invalid")
                    return@evaluateJavascript
                }
                val bytes = chunk.toByteArray(Charsets.UTF_8)
                val nextBytes = bytesWritten + bytes.size
                if (nextBytes > maxBytes) {
                    bytes.fill(0)
                    fail("renderer_result_too_large")
                    return@evaluateJavascript
                }
                runCatching { output.write(bytes) }
                    .onFailure {
                        bytes.fill(0)
                        fail("renderer_file_write_failed:${it.javaClass.simpleName}")
                        return@evaluateJavascript
                    }
                bytes.fill(0)
                readSnapshotChunk(view, output, nextOffset, totalCharacters, nextBytes)
            }
        }

        private fun complete(file: File, bytesWritten: Long) {
            if (bytesWritten <= 0L || !finished.compareAndSet(false, true)) {
                if (bytesWritten <= 0L) fail("renderer_empty_dom")
                return
            }
            mainHandler.removeCallbacks(timeoutAction)
            jobs.remove(requestId, this)
            releaseWebView()
            reply.sendResult(
                requestId = requestId,
                status = AgentWebRenderContract.STATUS_COMPLETED,
                values = Bundle().apply {
                    putString(AgentWebRenderContract.KEY_FINAL_URL, currentUrl)
                    putString(AgentWebRenderContract.KEY_CONTENT_TYPE, "text/html; charset=utf-8")
                    putString(AgentWebRenderContract.KEY_FILE_PATH, file.absolutePath)
                    putLong(
                        AgentWebRenderContract.KEY_DURATION_MILLIS,
                        SystemClock.elapsedRealtime() - startedAt
                    )
                }
            )
        }

        private fun fail(reason: String) {
            if (!finished.compareAndSet(false, true)) return
            mainHandler.removeCallbacks(timeoutAction)
            jobs.remove(requestId, this)
            runCatching { extractionOutput?.close() }
            extractionOutput = null
            extractionFile?.delete()
            releaseWebView()
            reply.sendFailure(requestId, reason.take(MAX_ERROR_CHARS))
        }

        private fun releaseWebView() {
            webView?.apply {
                stopLoading()
                webChromeClient = WebChromeClient()
                webViewClient = WebViewClient()
                clearHistory()
                clearCache(true)
                removeAllViews()
                destroy()
            }
            webView = null
            clearRendererStorage()
        }
    }

    private fun Messenger.sendFailure(requestId: String, reason: String) {
        sendResult(
            requestId,
            AgentWebRenderContract.STATUS_FAILED,
            Bundle().apply { putString(AgentWebRenderContract.KEY_ERROR, reason) }
        )
    }

    private fun Messenger.sendResult(requestId: String, status: String, values: Bundle) {
        runCatching {
            send(Message.obtain(null, AgentWebRenderContract.MSG_RENDER).apply {
                data = Bundle(values).apply {
                    putString(AgentWebRenderContract.KEY_REQUEST_ID, requestId)
                    putString(AgentWebRenderContract.KEY_STATUS, status)
                }
            })
        }.onFailure {
            File(values.getString(AgentWebRenderContract.KEY_FILE_PATH).orEmpty()).delete()
        }
    }

    private fun decodeJavascriptObject(raw: String?): JSONObject? = runCatching {
        val decoded = JSONTokener(raw ?: "null").nextValue() as? String ?: return null
        JSONObject(decoded)
    }.getOrNull()

    private companion object {
        const val MIN_TIMEOUT_MILLIS = 1_000L
        const val MAX_TIMEOUT_MILLIS = 60_000L
        const val MAX_RENDER_BYTES = 10L * 1024L * 1024L
        const val PROBE_INTERVAL_MILLIS = 300L
        const val MIN_PAGE_SETTLE_MILLIS = 750L
        const val MIN_MUTATION_SETTLE_MILLIS = 600L
        const val MAX_PAGE_SETTLE_MILLIS = 4_000L
        const val SNAPSHOT_CHUNK_CHARS = 48 * 1024
        const val MAX_ERROR_CHARS = 500

        val ARTICLE_HEADERS = mapOf(
            "Accept-Language" to "zh-CN,zh;q=0.9,en;q=0.7",
            "DNT" to "1"
        )
        const val MOBILE_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/140.0 Mobile Safari/537.36"
        fun blockedResponse() = WebResourceResponse(
            "text/plain",
            "utf-8",
            403,
            "Blocked",
            emptyMap(),
            ByteArray(0).inputStream()
        )
        val PROBE_SCRIPT = """
            (() => {
              if (!window.__signalasiDomObserver) {
                window.__signalasiMutationAt = Date.now();
                window.__signalasiDomObserver = new MutationObserver(() => {
                  window.__signalasiMutationAt = Date.now();
                });
                window.__signalasiDomObserver.observe(document.documentElement, {
                  subtree: true, childList: true, characterData: true, attributes: true
                });
              }
              return JSON.stringify({
                url: location.href,
                ready_state: document.readyState,
                now: Date.now(),
                mutation_at: window.__signalasiMutationAt || Date.now()
              });
            })()
        """.trimIndent()
        val FREEZE_SCRIPT = """
            (() => {
              window.__signalasiFrozenDom = document.documentElement
                ? document.documentElement.outerHTML
                : '';
              return JSON.stringify({
                url: location.href,
                title: document.title || '',
                length: window.__signalasiFrozenDom.length
              });
            })()
        """.trimIndent()
    }
}
