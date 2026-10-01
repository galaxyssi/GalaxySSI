package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Toast
import java.util.concurrent.Executors

/** User-initiated export outlives the clipboard handoff Activity, with explicit cancellation. */
class WechatArticleSaveService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false
    private var finished = false
    private var browser: WechatArticleBrowser? = null
    private var inOverlay = false
    private var overlayManager: WindowManager? = null
    private var started = false
    internal var needsVerification = false
        private set
    internal var onFinished: (() -> Unit)? = null
    private val timeout = Runnable { complete(R.string.wechat_article_failed) }
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == CANCEL) {
            complete(R.string.wechat_article_cancelled)
            return START_NOT_STICKY
        }
        if (started) {
            Toast.makeText(this, R.string.wechat_link_busy, Toast.LENGTH_SHORT).show()
            return START_NOT_STICKY
        }
        started = true
        active = this
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.wechat_article_save), NotificationManager.IMPORTANCE_LOW))
        val notification = notification(R.string.wechat_article_browser_loading)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(NOTIFICATION, notification)
        val url = intent?.getStringExtra("url")?.let(WechatArticleDocuments::articleUrl)
        if (url == null) {
            Log.w("WechatArticleSave", "stage=handoff failure=invalid_link")
            complete(R.string.wechat_article_failed)
            return START_NOT_STICKY
        }
        runCatching {
            browser = WechatArticleBrowser(this, ::export, ::verificationRequired) { complete(R.string.wechat_article_failed) }
            attachHiddenBrowser()
            handler.postDelayed(timeout, 300_000)
            browser!!.load(url)
        }.onFailure {
            Log.w("WechatArticleSave", "stage=browser_start failure=${it.javaClass.simpleName}")
            complete(R.string.wechat_article_failed)
        }
        return START_NOT_STICKY
    }

    private fun attachHiddenBrowser() {
        val view = browser?.view ?: return
        if (inOverlay || finished) return
        (view.parent as? ViewGroup)?.removeView(view)
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        // Real viewport for layout; alpha-zero and non-touchable leave WeChat unobscured and usable.
        val metrics = resources.displayMetrics
        val accessibility = GalaxySSIAccessibilityService.targetService()
        val host = WechatArticleBrowserPolicy.overlayHost(accessibility != null, Settings.canDrawOverlays(this))
        check(host != WechatArticleOverlayHost.UNAVAILABLE) { "article_overlay_unavailable" }
        val manager = (accessibility ?: this).getSystemService(WindowManager::class.java)
        val params = WindowManager.LayoutParams(metrics.widthPixels, metrics.heightPixels,
            if (host == WechatArticleOverlayHost.ACCESSIBILITY) WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            else WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT).apply { alpha = 0f }
        manager.addView(view, params)
        overlayManager = manager
        inOverlay = true
        Log.i("WechatArticleSave", "stage=browser_attached host=$host")
    }

    private fun detachBrowser() {
        val view = browser?.view ?: return
        if (inOverlay) {
            runCatching { overlayManager?.removeViewImmediate(view) }
            overlayManager = null
            inOverlay = false
        } else (view.parent as? ViewGroup)?.removeView(view)
    }

    internal fun showVerification(parent: ViewGroup): Boolean {
        if (!needsVerification || finished) return false
        val view = browser?.view ?: return false
        detachBrowser()
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        parent.addView(view, ViewGroup.LayoutParams(-1, -1))
        return true
    }

    internal fun hideVerification() {
        if (!finished) runCatching { attachHiddenBrowser() }.onFailure { complete(R.string.wechat_article_failed) }
    }

    internal fun continueSaving() {
        if (!needsVerification || finished) return
        needsVerification = false
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, 300_000)
        notifyProgress(R.string.wechat_article_browser_loading)
        browser?.continueAfterVerification()
    }

    private fun verificationRequired() {
        if (finished) return
        Log.i("WechatArticleSave", "stage=verification_required")
        needsVerification = true
        handler.removeCallbacks(timeout)
        // Verification waits for a user, but never retains the browser indefinitely.
        handler.postDelayed(timeout, 600_000)
        notifyProgress(R.string.wechat_article_verification)
        Toast.makeText(this, R.string.wechat_article_verification_notification, Toast.LENGTH_LONG).show()
    }

    private fun export(url: String, html: String) {
        if (finished) return
        Log.i("WechatArticleSave", "stage=export html_chars=${html.length}")
        needsVerification = false
        detachBrowser()
        browser?.close()
        browser = null
        notifyProgress(R.string.wechat_article_render)
        worker.execute {
            val deadline = SystemClock.elapsedRealtime() + 180_000
            val result = runCatching {
                WechatArticleExporter.export(this, url, html) {
                    check(!cancelled && !Thread.currentThread().isInterrupted) { "article_cancelled" }
                    check(SystemClock.elapsedRealtime() < deadline) { "article_export_timeout" }
                }
            }
            handler.post {
                if (!finished) result.fold({ complete(R.string.wechat_article_saved, it) }, {
                    Log.w("WechatArticleSave", "stage=export failure=${it.javaClass.simpleName}")
                    complete(R.string.wechat_article_failed)
                })
            }
        }
    }

    private fun notification(message: Int, saved: WechatSavedArticle? = null, terminal: Boolean = false): Notification {
        val text = if (saved == null) getString(message) else getString(message, saved.pages, saved.name)
        val builder = Notification.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(getString(R.string.wechat_article_save)).setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text)).setOnlyAlertOnce(true)
            .setOngoing(!terminal).setAutoCancel(terminal)
        if (!terminal) {
            val cancel = PendingIntent.getService(this, NOTIFICATION, Intent(this, javaClass).setAction(CANCEL),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.addAction(Notification.Action.Builder(null, getString(R.string.wechat_article_cancel), cancel).build())
        }
        if (needsVerification && !terminal) {
            val verify = PendingIntent.getActivity(this, NOTIFICATION, Intent(this, WechatArticleSaveActivity::class.java)
                .setAction(VERIFY), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.setContentIntent(verify)
            builder.addAction(Notification.Action.Builder(null, getString(R.string.wechat_article_verify), verify).build())
        }
        if (saved != null) {
            val open = PendingIntent.getActivity(this, NOTIFICATION + 1, Intent(Intent.ACTION_VIEW)
                .setDataAndType(saved.uri, "application/pdf").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.setContentIntent(open)
        }
        return builder.build()
    }

    private fun notifyProgress(message: Int) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(message))
    }

    private fun complete(message: Int, saved: WechatSavedArticle? = null) {
        if (finished) return
        Log.i("WechatArticleSave", "stage=finished saved=${saved != null} message=$message")
        finished = true
        cancelled = true
        handler.removeCallbacksAndMessages(null)
        detachBrowser()
        browser?.close()
        browser = null
        worker.shutdownNow()
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(message, saved, terminal = true))
        Toast.makeText(this, if (saved == null) getString(message) else getString(message, saved.pages, saved.name), Toast.LENGTH_LONG).show()
        onFinished?.invoke()
        onFinished = null
        if (active === this) active = null
        stopSelf()
    }

    override fun onDestroy() {
        if (!finished) complete(R.string.wechat_article_failed)
        super.onDestroy()
    }

    companion object {
        internal const val VERIFY = "com.galaxyssi.chat.WECHAT_ARTICLE_VERIFY"
        internal const val CANCEL = "com.galaxyssi.chat.WECHAT_ARTICLE_CANCEL"
        private const val CHANNEL = "galaxyssi_wechat_article_export"
        private const val NOTIFICATION = 4083
        internal var active: WechatArticleSaveService? = null
            private set
    }
}
