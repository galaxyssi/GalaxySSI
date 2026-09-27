package com.galaxyssi.chat

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Toast
import java.util.concurrent.Executors

/** Only escaped, locally generated HTML is loaded; scripts and external navigation are disabled. */
class ScreenAssistantPageViewerActivity : Activity() {
    private lateinit var web: WebView
    private val worker = Executors.newSingleThreadExecutor()
    private var closed = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getStringExtra("capture_id").orEmpty()
        val store = ScreenAssistantPageStore(this)
        val html = runCatching { java.io.File(store.directory(id), "page.html").takeIf { it.isFile } }.getOrNull()
        if (html == null) { finish(); return }
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val bar = LinearLayout(this)
        bar.addView(Button(this).apply { text = getString(R.string.screen_assistant_page_back); setOnClickListener { finish() } })
        listOf(false, true).forEach { pdf ->
            bar.addView(Button(this).apply {
                text = getString(if (pdf) R.string.screen_assistant_page_export_pdf else R.string.screen_assistant_page_export_html)
                setOnClickListener {
                    isEnabled = false
                    worker.execute {
                        val result = runCatching {
                            val file = if (pdf) store.exportPdf(id) else html
                            val mime = if (pdf) "application/pdf" else "text/html"
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, getString(R.string.screen_assistant_page_attachment) + "-${id.take(8)}." + file.extension)
                                put(MediaStore.Downloads.MIME_TYPE, mime)
                                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/GalaxySSI")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = requireNotNull(contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values))
                            try {
                                requireNotNull(contentResolver.openOutputStream(uri)).use { output -> file.inputStream().use { it.copyTo(output) } }
                                contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                            } catch (error: Exception) {
                                contentResolver.delete(uri, null, null); throw error
                            }
                        }
                        runOnUiThread {
                            if (!closed) {
                                isEnabled = true
                                Toast.makeText(this@ScreenAssistantPageViewerActivity, getString(if (result.isSuccess)
                                    R.string.screen_assistant_page_saved else R.string.screen_assistant_page_export_failed), Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
        layout.addView(bar)
        web = WebView(this).apply {
            settings.javaScriptEnabled = false
            settings.allowFileAccess = false
            settings.allowContentAccess = true
            settings.blockNetworkLoads = true
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?) = true
            }
            loadUrl(LocalAttachmentUris.forFile(this@ScreenAssistantPageViewerActivity, html,
                getString(R.string.screen_assistant_page_attachment) + ".html", "text/html").toString())
        }
        layout.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(layout)
    }
    override fun onDestroy() {
        closed = true
        if (::web.isInitialized) web.destroy()
        worker.shutdown()
        super.onDestroy()
    }
    companion object {
        internal fun open(context: Context, id: String) = context.startActivity(
            Intent(context, ScreenAssistantPageViewerActivity::class.java).putExtra("capture_id", id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
