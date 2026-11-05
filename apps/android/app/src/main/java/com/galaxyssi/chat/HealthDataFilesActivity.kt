package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.text.format.DateFormat
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import java.text.NumberFormat
import java.util.Date
import java.util.concurrent.Executors

class HealthDataFilesActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val repository by lazy { HealthDataFilesRepository(applicationContext, names) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val refresh = Runnable { load() }
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            main.removeCallbacks(refresh)
            if (started) main.postDelayed(refresh, 100)
        }
    }
    private lateinit var scroll: ScrollView
    private lateinit var recent: LinearLayout
    private val counts = ArrayList<TextView>(3)
    private var request: CancellationSignal? = null
    private var menu: AlertDialog? = null
    private var started = false
    private var returnScroll: Int? = null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.statusBarColor = getColor(R.color.surface_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        returnScroll = state?.getInt("scroll")
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            minimumHeight = ui.dp(56)
            setBackgroundColor(getColor(R.color.surface_bg))
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_export_data_files), 19f, bold = true).apply { gravity = Gravity.CENTER },
                LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                open(HealthCenterActivity::class.java) { putExtra("health_functions", true) }
            })
        }, LinearLayout.LayoutParams(-1, -2))
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        scroll = ScrollView(this).apply { addView(content) }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)

        ui.add(content, summary())
        ui.add(content, ui.line().apply {
            addView(action(R.string.common_import, R.drawable.ic_settings_upload, true) { importMenu() },
                LinearLayout.LayoutParams(0, -1, 1f).apply { marginEnd = ui.dp(8) })
            addView(action(R.string.common_export, R.drawable.ic_export, false) { exportMenu() },
                LinearLayout.LayoutParams(0, -1, 1f))
        }, 14)
        ui.add(content, heading(R.string.health_data_manage), 22)
        ui.add(content, group().apply {
            addView(manage(R.string.health_data_measurements, R.string.health_data_measurements_note, R.drawable.ic_health_data_chart, GREEN) {
                open(HealthCatalogActivity::class.java)
            })
            addView(divider())
            addView(manage(R.string.health_data_originals, R.string.health_data_originals_note, R.drawable.ic_agent_camera, ORANGE, ::library))
            addView(divider())
            addView(manage(R.string.health_data_tasks, R.string.health_data_tasks_note, R.drawable.ic_agent_history, BLUE, ::tasksMenu))
            addView(divider())
            addView(manage(R.string.health_data_backup, R.string.health_data_backup_note, R.drawable.ic_security_shield, PLUM, ::backupMenu))
        }, 8)
        ui.add(content, ui.line().apply {
            addView(heading(R.string.health_data_recent), LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.text(getString(R.string.health_data_view_all), 14f, bold = true).apply {
                minimumHeight = ui.dp(48); gravity = Gravity.CENTER_VERTICAL
                setPadding(ui.dp(8), 0, 0, 0); setTextColor(getColor(R.color.health_data_link_text))
                isFocusable = true; setOnClickListener { library() }
            })
        }, 16)
        recent = group()
        ui.add(content, recent, 4)
        showRecentStatus(R.string.health_data_loading_files)
    }

    override fun onStart() {
        super.onStart()
        started = true
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, observer)
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this).buildUpon().appendPath("originals").build(), false, observer)
        load()
    }

    override fun onStop() {
        started = false
        if (returnScroll == null) returnScroll = scroll.scrollY
        request?.cancel(); request = null
        main.removeCallbacks(refresh)
        contentResolver.unregisterContentObserver(observer)
        menu?.dismiss(); menu = null
        counts.forEach { it.setText(R.string.health_data_count_pending) }
        showRecentStatus(R.string.health_data_loading_files)
        super.onStop()
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt("scroll", returnScroll ?: scroll.scrollY)
    }

    private fun load() {
        if (!started) return
        request?.cancel()
        val signal = CancellationSignal().also { request = it }
        worker.execute {
            val files = runCatching {
                repository.load(signal) { overview ->
                    main.post {
                        if (!current(signal)) return@post
                        overview.fold({ (records, files) ->
                            counts[0].text = formatCount(records)
                            showRecent(files)
                        }, {
                            counts[0].setText(R.string.health_data_count_pending)
                            showRecentStatus(R.string.health_storage_error, retry = true)
                        })
                    }
                }
            }
            main.post {
                if (!current(signal)) return@post
                counts[1].text = files.getOrNull()?.let { formatCount(it.camera) } ?: getString(R.string.health_data_count_pending)
                counts[2].text = files.getOrNull()?.let { formatCount(it.uploads) } ?: getString(R.string.health_data_count_pending)
                if (files.isFailure && recent.findViewWithTag<View>("health-data-retry") == null) {
                    ui.add(recent, retryButton())
                }
            }
        }
    }

    private fun current(signal: CancellationSignal) = started && request === signal
    private fun formatCount(value: Long) = NumberFormat.getIntegerInstance().format(value)
    private fun heading(title: Int) = ui.text(getString(title), 18f, bold = true).apply { ViewCompat.setAccessibilityHeading(this, true) }
    private fun group() = ui.column().apply {
        setPadding(ui.dp(12), ui.dp(4), ui.dp(12), ui.dp(4))
        background = ui.background(stroke = getColor(R.color.separator), radius = 14)
    }

    private fun summary() = ui.column().apply {
        background = ui.background(getColor(R.color.health_data_summary_fill), getColor(R.color.health_data_summary_stroke), radius = 16)
        setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(16))
        addView(ui.text(getString(R.string.health_data_local), 13f).apply { setTextColor(getColor(R.color.health_data_link_text)) })
        ui.add(this, ui.text(getString(R.string.health_data_heading), 24f, bold = true).apply {
            setTextColor(getColor(R.color.text_primary)); ViewCompat.setAccessibilityHeading(this, true)
        }, 6)
        ui.add(this, ui.text(getString(R.string.health_data_note), 14f).apply { setTextColor(getColor(R.color.health_data_link_text)) }, 5)
        ui.add(this, ui.line().apply {
            gravity = Gravity.TOP
            val labels = listOf(R.string.health_data_record_count, R.string.health_data_camera_count, R.string.health_data_upload_count)
            labels.forEachIndexed { index, label ->
                if (index > 0) addView(View(this@HealthDataFilesActivity).apply { setBackgroundColor(getColor(R.color.health_data_summary_stroke)) },
                    LinearLayout.LayoutParams(ui.dp(1), -1))
                addView(ui.column().apply {
                    setPadding(ui.dp(4), 0, ui.dp(4), 0)
                    addView(ui.text(getString(R.string.health_data_count_pending), 25f, bold = true).apply {
                        tag = "health-data-count-$index"; gravity = Gravity.CENTER; counts.add(this)
                    })
                    addView(ui.text(getString(label), 12f).apply { gravity = Gravity.CENTER; setTextColor(getColor(R.color.health_data_link_text)) })
                }, LinearLayout.LayoutParams(0, -2, 1f))
            }
        }, 16)
    }

    private fun action(label: Int, icon: Int, primary: Boolean, click: () -> Unit) = ui.line().apply {
        gravity = Gravity.CENTER
        minimumHeight = ui.dp(48)
        setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
        background = if (primary) ui.background(getColor(R.color.accent_green), radius = 10)
            else ui.background(stroke = getColor(R.color.separator), radius = 10)
        val ink = if (primary) Color.rgb(8, 40, 29) else getColor(R.color.health_data_link_text)
        addView(glyph(icon, ink), LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)).apply { marginEnd = ui.dp(6) })
        addView(ui.text(getString(label), 16f, bold = true).apply { setTextColor(ink) })
        tag = if (primary) "health-data-import" else "health-data-export"
        setOnClickListener { click() }; isFocusable = true
    }

    private fun glyph(resource: Int, ink: Int) = ImageView(this).apply {
        setImageResource(resource); setColorFilter(ink); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private fun tile(resource: Int, accent: Accent) = glyph(resource, accent.ink).apply {
        val inset = ui.dp(9)
        background = ui.background(accent.fill, radius = 10)
        setPadding(inset, inset, inset, inset)
    }

    private fun manage(title: Int, note: Int, icon: Int, accent: Accent, click: () -> Unit) = ui.line().apply {
        minimumHeight = ui.dp(64); setPadding(0, ui.dp(10), 0, ui.dp(10))
        addView(tile(icon, accent), LinearLayout.LayoutParams(ui.dp(38), ui.dp(38)).apply { marginEnd = ui.dp(11) })
        addView(ui.column().apply {
            addView(ui.text(getString(title), 16f, bold = true))
            addView(ui.text(getString(note), 13f).apply { setTextColor(getColor(R.color.health_data_meta_text)) })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        addView(ui.text("\u203a", 24f, muted = true).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO })
        setOnClickListener { click() }; isFocusable = true
    }

    private fun divider() = View(this).apply {
        setBackgroundColor(getColor(R.color.separator))
        layoutParams = LinearLayout.LayoutParams(-1, ui.dp(1))
    }

    private fun showRecentStatus(text: Int, retry: Boolean = false) {
        recent.removeAllViews()
        recent.addView(ui.text(getString(text), 14f, muted = true).apply {
            setPadding(0, ui.dp(8), 0, ui.dp(8)); tag = "health-data-status"
        })
        if (retry) ui.add(recent, retryButton())
    }

    private fun retryButton() = ui.row(getString(R.string.common_retry)) { load() }.apply { tag = "health-data-retry" }

    private fun showRecent(files: List<HealthRecentFile>) {
        recent.removeAllViews()
        if (files.isEmpty()) showRecentStatus(R.string.health_no_originals)
        files.forEachIndexed { index, file ->
            if (index > 0) recent.addView(divider())
            recent.addView(fileRow(file))
        }
        returnScroll?.let { y ->
            scroll.post { if (started && returnScroll == y) { scroll.scrollTo(0, y); returnScroll = null } }
        }
    }

    private fun fileRow(file: HealthRecentFile) = ui.line().apply {
        tag = "health-data-original-${file.id}"
        minimumHeight = ui.dp(64); setPadding(0, ui.dp(10), 0, ui.dp(10))
        addView(tile(if (file.image) R.drawable.ic_process_image else R.drawable.ic_rich_file, if (file.image) ORANGE else BLUE),
            LinearLayout.LayoutParams(ui.dp(38), ui.dp(38)).apply { marginEnd = ui.dp(11) })
        addView(ui.column().apply {
            addView(ui.text(file.name, 15f, bold = true).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END })
            val date = Date(file.added)
            val source = when (file.source) {
                HealthDataFileSource.CAMERA -> R.string.health_data_camera
                HealthDataFileSource.UPLOAD -> R.string.health_data_upload
                HealthDataFileSource.CROP -> R.string.health_data_crop
                HealthDataFileSource.OTHER -> R.string.health_data_originals
            }
            addView(ui.text(getString(R.string.health_data_file_meta, DateFormat.getMediumDateFormat(this@HealthDataFilesActivity).format(date),
                DateFormat.getTimeFormat(this@HealthDataFilesActivity).format(date), getString(source),
                Formatter.formatShortFileSize(this@HealthDataFilesActivity, file.size)), 12f).apply {
                setTextColor(getColor(R.color.health_data_meta_text))
            })
            val state = when {
                !file.available -> R.string.health_data_missing
                file.linked -> R.string.health_data_linked
                else -> R.string.health_data_unlinked
            }
            addView(ui.text(getString(state), 12f, bold = true).apply {
                setTextColor(getColor(if (file.linked && file.available) R.color.health_data_link_text else R.color.health_data_warning_text))
            })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        setOnClickListener { open(HealthCaptureActivity::class.java) { putExtra("original", file.id) } }
        isFocusable = true
    }

    private fun open(activity: Class<*>, extras: Intent.() -> Unit = {}) =
        startActivity(Intent(this, activity).putHealthNavigationFixture(names).apply(extras))

    private fun library() = open(HealthOriginalLibraryActivity::class.java)
    private fun exportRecords(history: Boolean = false) = open(HealthRecordExportActivity::class.java) {
        putExtra("export_history", history); putExtra("health_record_export_test_id", names.fixture)
    }
    private fun backup(mode: String? = null) = open(HealthBackupActivity::class.java) {
        if (mode != null) putExtra(mode, true)
        putExtra("health_backup_test_id", names.fixture)
    }

    private fun importMenu() = choose(R.string.common_import,
        R.string.health_first_import_title to { open(HealthCenterActivity::class.java) { putExtra("health_import_center", true) } },
        R.string.health_export_import_originals to { open(HealthCaptureActivity::class.java) {
            putExtra("health_pick_files", true); putExtra("health_original_only", true)
        } })

    private fun exportMenu() = choose(R.string.common_export,
        R.string.health_export_records to { exportRecords() },
        R.string.health_library_export to ::library)

    private fun tasksMenu() = choose(R.string.health_data_tasks,
        R.string.health_import_queue_title to { open(HealthCaptureActivity::class.java) },
        R.string.health_export_history to { exportRecords(history = true) },
        R.string.health_library_export_history to { open(HealthOriginalExportHistoryActivity::class.java) {
            putExtra("health_original_export_test_id", names.fixture)
        } })

    private fun backupMenu() = choose(R.string.health_data_backup,
        R.string.health_backup_create to { backup() },
        R.string.health_backup_history to { backup("backup_history") },
        R.string.health_backup_verify to { backup("verify_backup") },
        R.string.health_restore_title to { open(HealthRestoreActivity::class.java) { putExtra("health_restore_test_id", names.fixture) } })

    private fun choose(title: Int, vararg options: Pair<Int, () -> Unit>) {
        menu?.dismiss()
        menu = AlertDialog.Builder(this).setTitle(title).setItems(options.map { getString(it.first) }.toTypedArray()) { _, index ->
            options[index].second()
        }.setNegativeButton(R.string.common_cancel, null).show()
    }

    private data class Accent(val fill: Int, val ink: Int)
    private companion object {
        val GREEN = Accent(Color.rgb(232, 247, 238), Color.rgb(30, 100, 68))
        val ORANGE = Accent(Color.rgb(255, 240, 226), Color.rgb(147, 77, 26))
        val BLUE = Accent(Color.rgb(236, 242, 255), Color.rgb(66, 96, 155))
        val PLUM = Accent(Color.rgb(244, 236, 250), Color.rgb(112, 79, 142))
    }
}
