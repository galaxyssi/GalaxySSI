package com.galaxyssi.chat

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebChromeClient
import android.webkit.PermissionRequest
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import org.jsoup.Jsoup
import org.json.JSONTokener
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Foreground, explicit clipboard handoff. Android does not permit background clipboard reads. */
class WechatArticleSaveActivity : Activity() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false
    private var started = false
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private lateinit var close: Button
    private lateinit var open: Button
    private lateinit var layout: LinearLayout
    private var verification: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val gap = (20 * resources.displayMetrics.density).toInt()
        layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(gap, gap, gap, gap)
        }
        layout.addView(TextView(this).apply { text = getString(R.string.wechat_article_save); textSize = 20f })
        status = TextView(this).apply { text = getString(R.string.wechat_article_read_clipboard); textSize = 16f; setPadding(0, gap, 0, gap) }
        layout.addView(status)
        progress = ProgressBar(this).also(layout::addView)
        open = Button(this).apply { text = getString(R.string.wechat_article_open); visibility = View.GONE }
        layout.addView(open)
        close = Button(this).apply { text = getString(R.string.wechat_article_cancel); setOnClickListener { finish() } }
        layout.addView(close)
        setContentView(layout)
        // Do not silently reread an old clipboard or restart an interrupted export after recreation.
        if (savedInstanceState != null) { started = true; fail(R.string.wechat_article_failed) }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || started || cancelled) return
        started = true
        val clip = runCatching { getSystemService(ClipboardManager::class.java).primaryClip }.getOrNull()
        val since = intent.getLongExtra("copied_after", Long.MAX_VALUE)
        val url = clip?.takeIf { it.itemCount == 1 && it.description.timestamp >= since }
            ?.getItemAt(0)?.text?.toString()?.let(WechatArticleDocuments::articleUrl)
        if (url == null) { fail(R.string.wechat_article_clipboard_failed); return }
        export(url)
    }

    private fun export(url: String, verifiedHtml: String? = null) {
        status.setText(R.string.wechat_article_fetch)
        progress.visibility = View.VISIBLE
        open.visibility = View.GONE
        close.setText(R.string.wechat_article_cancel)
        worker.execute {
            val id = UUID.randomUUID().toString()
            val pdf = File(cacheDir, "wechat-$id.pdf")
            val result = runCatching {
                val deadline = SystemClock.elapsedRealtime() + 180_000
                fun checkpoint() {
                    check(!cancelled && !Thread.currentThread().isInterrupted) { "article_cancelled" }
                    check(SystemClock.elapsedRealtime() < deadline) { "article_export_timeout" }
                }
                val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport(), policy = AgentWebPolicy(
                    maxFetchBytes = 8L * 1024 * 1024, maxDownloadBytes = 8L * 1024 * 1024, maxTimeoutMillis = 20_000))
                val source = if (verifiedHtml == null) web.fetch(url, checkpoint = ::checkpoint) else null
                val sourceUrl = source?.finalUrl ?: url
                val sourceBody = source?.body ?: checkNotNull(verifiedHtml).toByteArray()
                if (WechatArticleDocuments.requiresVerification(sourceBody)) throw ArticleVerificationRequired()
                val article = WechatArticleDocuments.extract(sourceUrl, sourceBody)
                var remaining = 48L * 1024 * 1024
                val archived = AgentWebOriginalDocument.build(sourceUrl, article.html.toByteArray()) { address ->
                    checkpoint()
                    check(remaining > 0) { "article_asset_limit" }
                    val image = web.download(address, maxBytes = minOf(8L * 1024 * 1024, remaining), checkpoint = ::checkpoint)
                    remaining -= image.body.size
                    OriginalPageAsset(image.contentType.substringBefore(';').trim(), image.body)
                }
                checkpoint()
                check(archived.missing == 0) { "article_assets_incomplete" }
                val document = Jsoup.parse(archived.html)
                document.body().appendElement("p").text(getString(R.string.wechat_article_static))
                runOnUiThread { if (!cancelled) status.setText(R.string.wechat_article_render) }
                val pages = WechatArticlePdf.render(document.outerHtml(), pdf, ::checkpoint)
                WechatArticlePdf.save(this, pdf, WechatArticleDocuments.fileName(article.title, id.take(8)), pages, ::checkpoint)
            }
            pdf.delete()
            runOnUiThread {
                if (!cancelled) result.fold({ saved ->
                    progress.visibility = View.GONE
                    status.text = getString(R.string.wechat_article_saved, saved.pages, saved.name)
                    close.setText(R.string.wechat_article_close)
                    open.visibility = View.VISIBLE
                    open.setText(R.string.wechat_article_open)
                    open.setOnClickListener {
                        runCatching { startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(saved.uri, "application/pdf")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }.onFailure {
                            Toast.makeText(this, R.string.wechat_article_no_viewer, Toast.LENGTH_SHORT).show()
                        }
                    }
                    Log.i("WechatArticleSave", "Article PDF saved pages=${saved.pages}")
                }, { error ->
                    // Do not log the user's clipboard, article text, URL, or network exception messages.
                    Log.w("WechatArticleSave", "Article PDF failed type=${error.javaClass.simpleName}")
                    if (error is ArticleVerificationRequired) offerVerification(url)
                    else fail(R.string.wechat_article_failed)
                })
            }
        }
    }

    private fun offerVerification(url: String) {
        fail(R.string.wechat_article_verification)
        open.visibility = View.VISIBLE
        open.setText(R.string.wechat_article_verify)
        open.setOnClickListener { showVerification(url) }
    }

    @Suppress("SetJavaScriptEnabled")
    private fun showVerification(url: String) {
        if (verification != null) return
        val browser = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.safeBrowsingEnabled = true
            settings.mediaPlaybackRequiresUserGesture = true
            android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            }
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url
                    if (uri.scheme != "https") return true
                    return if (request.isForMainFrame) uri.host != "mp.weixin.qq.com"
                    else uri.host?.let { it != "qq.com" && !it.endsWith(".qq.com") } != false
                }
            }
        }
        verification = browser
        status.setText(R.string.wechat_article_verify_continue_hint)
        layout.addView(browser, 2, LinearLayout.LayoutParams(-1, 0, 1f))
        open.setText(R.string.wechat_article_continue)
        open.setOnClickListener {
            if (browser.url?.let(WechatArticleDocuments::articleUrl) == null) {
                status.setText(R.string.wechat_article_verify_continue_hint)
                return@setOnClickListener
            }
            // The user completes verification themselves. Only then read this visible article DOM.
            browser.evaluateJavascript("document.documentElement.outerHTML.length <= 8388608 ? document.documentElement.outerHTML : null") { value ->
                val html = runCatching { JSONTokener(value).nextValue() as? String }.getOrNull()
                val currentUrl = browser.url.orEmpty()
                if (html == null || runCatching { WechatArticleDocuments.extract(currentUrl, html.toByteArray()) }.isFailure) {
                    status.setText(R.string.wechat_article_verify_continue_hint)
                } else {
                    layout.removeView(browser)
                    browser.destroy()
                    verification = null
                    export(currentUrl, html)
                }
            }
        }
        browser.loadUrl(url)
    }

    private fun fail(message: Int) {
        progress.visibility = View.GONE
        status.setText(message)
        close.setText(R.string.wechat_article_close)
    }

    override fun onDestroy() {
        cancelled = true
        verification?.destroy()
        verification = null
        worker.shutdownNow()
        super.onDestroy()
    }

    companion object {
        internal fun open(context: Context, copiedAfter: Long) = context.startActivity(
            Intent(context, WechatArticleSaveActivity::class.java).putExtra("copied_after", copiedAfter)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private class ArticleVerificationRequired : IllegalStateException()
}
