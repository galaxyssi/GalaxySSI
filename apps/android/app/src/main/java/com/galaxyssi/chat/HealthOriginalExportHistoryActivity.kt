package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

class HealthOriginalExportHistoryActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val fixture by lazy { intent.getStringExtra("health_original_export_test_id").orEmpty().takeIf { BuildConfig.DEBUG && HealthProfilePolicy.uuid(it) } }
    private lateinit var body: LinearLayout
    private var cursor: Pair<Long, String>? = null
    private val previous = arrayListOf<Pair<Long, String>?>()
    private var active = false
    private var generation = 0
    private var loading = false
    private var dirty = false
    private var scroll: ScrollView? = null
    private var scrollY = 0
    private val observer = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean, uri: android.net.Uri?) {
            if (uri?.lastPathSegment == "exports" && active) {
                if (loading) dirty = true else load()
            }
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        cursor = decode(state?.getString("cursor"))
        state?.getStringArrayList("previous")?.forEach { previous += decode(it) }
        scrollY = state?.getInt("scroll") ?: 0
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_library_export_history), 19f, bold = true).apply {
                gravity = Gravity.CENTER
                maxLines = 1
                setAutoSizeTextTypeUniformWithConfiguration(12, 19, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
            },
                LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                startActivity(Intent(this@HealthOriginalExportHistoryActivity, HealthCenterActivity::class.java).putExtra("health_functions", true))
            })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column()
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    override fun onStart() {
        super.onStart()
        active = true
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this), true, observer)
        load()
    }
    override fun onStop() {
        active = false
        generation++
        loading = false
        dirty = false
        scrollY = scroll?.scrollY ?: scrollY
        scroll = null
        contentResolver.unregisterContentObserver(observer)
        body.removeAllViews()
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("cursor", encode(cursor))
        outState.putStringArrayList("previous", ArrayList(previous.map(::encode)))
        outState.putInt("scroll", scroll?.scrollY ?: scrollY)
        super.onSaveInstanceState(outState)
    }

    private fun encode(value: Pair<Long, String>?) = value?.let { "${it.first}|${it.second}" }.orEmpty()
    private fun decode(value: String?) = value?.split('|', limit = 2)?.let {
        val time = it.firstOrNull()?.toLongOrNull()
        val id = it.getOrNull(1)
        if (time != null && id != null && HealthProfilePolicy.uuid(id)) time to id else null
    }

    private fun load() {
        if (!active || loading) return
        loading = true
        if (body.childCount == 0) body.addView(ui.text(getString(R.string.health_loading)))
        val token = ++generation
        val after = cursor
        worker.execute {
            val result = runCatching {
                HealthExportShare.openOriginals(applicationContext, fixture).use {
                    HealthExportShare.originalLibrary(applicationContext, it, fixture).history(after)
                }
            }
            main.post {
                if (!active || token != generation) return@post
                loading = false
                result.fold(::render, {
                    body.removeAllViews()
                    body.addView(ui.text(getString(R.string.health_storage_error)))
                    body.addView(ui.command(R.string.common_retry) { load() })
                })
                if (dirty) { dirty = false; load() }
            }
        }
    }

    private fun render(values: List<HealthOriginalExportSession>) {
        scrollY = scroll?.scrollY ?: scrollY
        body.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        val panel = ScrollView(this).apply { addView(content) }
        scroll = panel
        body.addView(panel, LinearLayout.LayoutParams(-1, 0, 1f))
        if (values.isEmpty()) ui.add(content, ui.text(getString(R.string.health_export_no_history), 15f, muted = true), 12)
        val date = DateFormat.getDateTimeInstance()
        values.take(30).forEach { session ->
            val summary = getString(R.string.health_library_summary, session.count,
                android.text.format.Formatter.formatShortFileSize(this, session.sourceBytes))
            ui.add(content, ui.row(getString(session.title()), "${date.format(Date(session.createdAt))} \u00b7 $summary") {
                if (!loading) startActivity(Intent(this, HealthOriginalExportActivity::class.java)
                    .putExtra("export_id", session.id).putExtra("health_original_export_test_id", fixture))
            }.apply { tag = "health-original-history-${session.id}" }, 8)
        }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) {
            if (!loading) { cursor = previous.removeAt(previous.lastIndex); scroll = null; scrollY = 0; load() }
        }.apply { tag = "health-original-history-previous" }, 12)
        if (values.size > 30) ui.add(content, ui.command(R.string.health_next_page) {
            if (!loading) { previous += cursor; cursor = values[29].let { it.createdAt to it.id }; scroll = null; scrollY = 0; load() }
        }.apply { tag = "health-original-history-next" }, 12)
        panel.post { if (scroll === panel) panel.scrollTo(0, scrollY) }
    }
}
