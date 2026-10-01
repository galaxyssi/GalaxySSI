package com.galaxyssi.chat

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/** Transparent clipboard handoff; only explicit verification opens a visible page. */
class WechatArticleSaveActivity : Activity() {
    private var started = false
    private var verificationService: WechatArticleSaveService? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action == WechatArticleSaveService.VERIFY) {
            started = true
            showVerification()
        } else {
            setContentView(View(this))
            if (savedInstanceState != null) finish()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || started || isFinishing) return
        started = true
        val clip = runCatching { getSystemService(ClipboardManager::class.java).primaryClip }.getOrNull()
        val since = intent.getLongExtra("copied_after", Long.MAX_VALUE)
        val url = clip?.takeIf { it.itemCount == 1 && it.description.timestamp >= since }
            ?.getItemAt(0)?.text?.toString()?.let(WechatArticleDocuments::articleUrl)
        if (url == null) Toast.makeText(this, R.string.wechat_article_clipboard_failed, Toast.LENGTH_LONG).show()
        else runCatching {
            startForegroundService(Intent(this, WechatArticleSaveService::class.java).putExtra("url", url))
        }.onFailure { Toast.makeText(this, R.string.wechat_article_failed, Toast.LENGTH_LONG).show() }
        finish()
    }

    private fun showVerification() {
        val service = WechatArticleSaveService.active?.takeIf { it.needsVerification }
        if (service == null) { finish(); return }
        verificationService = service
        val gap = (16 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(gap, gap, gap, gap)
            setBackgroundColor(android.graphics.Color.WHITE)
        }
        layout.addView(TextView(this).apply { setText(R.string.wechat_article_verify_continue_hint) })
        val browserHost = FrameLayout(this)
        layout.addView(browserHost, LinearLayout.LayoutParams(-1, 0, 1f))
        layout.addView(Button(this).apply {
            setText(R.string.wechat_article_continue)
            setOnClickListener { service.continueSaving(); finish() }
        })
        layout.addView(Button(this).apply {
            setText(R.string.wechat_article_cancel)
            setOnClickListener {
                startService(Intent(this@WechatArticleSaveActivity, WechatArticleSaveService::class.java)
                    .setAction(WechatArticleSaveService.CANCEL))
                finish()
            }
        })
        setContentView(layout)
        service.onFinished = { finish() }
        if (!service.showVerification(browserHost)) finish()
    }

    override fun onDestroy() {
        verificationService?.let { it.onFinished = null; it.hideVerification() }
        verificationService = null
        super.onDestroy()
    }

    companion object {
        internal fun open(context: Context, copiedAfter: Long) = context.startActivity(
            Intent(context, WechatArticleSaveActivity::class.java).putExtra("copied_after", copiedAfter)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION))
    }
}
