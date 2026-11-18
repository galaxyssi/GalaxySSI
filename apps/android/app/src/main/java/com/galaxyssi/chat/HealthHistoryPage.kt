package com.galaxyssi.chat

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import java.util.concurrent.Executors

internal abstract class HealthHistoryPage : Activity() {
    protected val names by lazy { intent.healthNavigationDatabases() }
    protected val ui by lazy { HealthCenterViews(this) }
    protected lateinit var content: LinearLayout
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var generation = 0
    @Volatile private var active = false
    private val dialogs = mutableSetOf<android.app.Dialog>()
    protected abstract val heading: Int
    protected abstract fun refresh()
    private val changes = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (active) { dialogs.toList().forEach { it.dismiss() }; generation++; content.removeAllViews(); refresh() }
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.toolbar(heading, { finish() }), LinearLayout.LayoutParams(-1, ui.dp(56)))
        content = ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(24)) }
        root.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }
    override fun onStart() {
        super.onStart(); active = true
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, names.privacy), false, changes)
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, changes)
        refresh()
    }
    override fun onStop() {
        active = false; generation++; contentResolver.unregisterContentObserver(changes)
        dialogs.toList().forEach { it.dismiss() }; dialogs.clear(); content.removeAllViews()
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    protected fun show(dialog: android.app.Dialog) {
        dialogs.add(dialog); dialog.setOnDismissListener { dialogs.remove(dialog) }; dialog.show()
    }
    protected fun <T> query(work: (() -> Unit) -> T, done: (T) -> Unit) {
        val token = ++generation
        worker.execute {
            val check = { if (!active || token != generation) throw java.util.concurrent.CancellationException() }
            val result = runCatching { check(); work(check).also { check() } }
            main.post { if (active && token == generation) result.fold(done) {
                content.removeAllViews()
                content.addView(ui.text(getString(if (it is HealthAccessBlocked) R.string.health_privacy_trend_blocked else R.string.health_storage_error)))
                ui.add(content, ui.command(R.string.common_retry) { refresh() }, 12)
            } }
        }
    }
}
