package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executors

class HealthOriginalLibraryActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }; private val worker = Executors.newSingleThreadExecutor()
    private val thumbnails = Executors.newFixedThreadPool(2); private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout; private var active = false; @Volatile private var generation = 0
    private var filter = HealthLibraryFilter(); private var grid = true; private var selection = ""; private var scrollY = 0
    private var signal: CancellationSignal? = null; private var dialog: AlertDialog? = null; private var scroll: ScrollView? = null
    private val previous = arrayListOf<Pair<Long, String>?>(); private var cursor: Pair<Long, String>? = null
    private val images = arrayListOf<Pair<ImageView, android.graphics.Bitmap>>()
    private val tasks = arrayListOf<java.util.concurrent.Future<*>>()
    private val observer = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean, uri: android.net.Uri?) { if (uri?.lastPathSegment == "originals") load() }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        filter = runCatching { HealthLibraryFilter(state?.getString("kind")?.let(HealthOriginalKind::valueOf), state?.getLong("from") ?: 0, state?.getLong("until") ?: Long.MAX_VALUE) }.getOrDefault(HealthLibraryFilter())
        grid = state?.getBoolean("grid", true) ?: true; selection = state?.getString("selection").orEmpty(); scrollY = state?.getInt("scroll") ?: 0
        state?.getString("cursor")?.let { cursor = readCursor(it) }; state?.getStringArrayList("previous")?.forEach { previous += readCursor(it) }
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_original_library), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthOriginalLibraryActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() { super.onStart(); active = true; contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this), true, observer); load() }
    override fun onStop() {
        active = false; generation++; signal?.cancel(); contentResolver.unregisterContentObserver(observer)
        scrollY = scroll?.scrollY ?: scrollY; scroll = null; dialog?.dismiss(); dialog = null; clearImages(); body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); thumbnails.shutdownNow(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("kind", filter.kind?.name); out.putLong("from", filter.from); out.putLong("until", filter.until); out.putBoolean("grid", grid)
        out.putString("selection", selection); out.putString("cursor", writeCursor(cursor)); out.putStringArrayList("previous", ArrayList(previous.map(::writeCursor))); out.putInt("scroll", scroll?.scrollY ?: scrollY)
        super.onSaveInstanceState(out)
    }
    private fun readCursor(text: String): Pair<Long, String>? = text.takeIf { it.isNotBlank() }?.split('|')?.let { it[0].toLong() to it[1] }
    private fun writeCursor(value: Pair<Long, String>?) = value?.let { "${it.first}|${it.second}" }.orEmpty()
    private fun clearImages() { tasks.forEach { it.cancel(true) }; tasks.clear(); images.forEach { (view, bitmap) -> view.setImageDrawable(null); HealthOriginalThumbnail.clear(bitmap) }; images.clear() }
    private fun reset() { cursor = null; previous.clear(); scrollY = 0; load() }
    private fun load() {
        if (!active) return
        val token = ++generation; signal?.cancel(); val cancellation = CancellationSignal(); signal = cancellation
        clearImages(); body.removeAllViews(); body.addView(ui.text(getString(R.string.health_loading)))
        val query = filter; val after = cursor; val selected = selection
        worker.execute {
            val result = runCatching { HealthOriginalStore(applicationContext).use { originals ->
                val library = HealthOriginalLibraryStore(applicationContext, originals)
                val session = selected.takeIf { it.isNotBlank() }?.let(library::session)?.takeIf { it.state == HealthOriginalExportState.SELECTING }
                    ?: HealthOriginalExportSession(selected.takeIf { it.isNotBlank() && library.session(it) == null } ?: java.util.UUID.randomUUID().toString(), HealthOriginalExportState.SELECTING, System.currentTimeMillis())
                val page = originals.library(query, after, cancellation)
                LibrarySnapshot(session.id, page, library.selected(session.id, page.originals), library.count(session.id), library.latest()?.id,
                    page.originals.filterNot(originals::present).map { it.id }.toSet())
            } }
            main.post { if (active && token == generation) result.fold({ selection = it.session; render(it, token) }, { body.removeAllViews(); body.addView(ui.text(getString(R.string.health_storage_error))); body.addView(ui.command(R.string.common_retry) { load() }) }) }
        }
    }
    private fun render(data: LibrarySnapshot, token: Int) {
        body.removeAllViews(); val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(20)) }
        scroll = ScrollView(this).apply { addView(content) }.also { body.addView(it, LinearLayout.LayoutParams(-1, 0, 1f)) }
        content.addView(ui.line().apply {
            addView(ui.row(getString(R.string.health_library_type), getString(filter.kind?.title() ?: R.string.health_library_all)) { chooseType() }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(if (grid) R.drawable.ic_chat_shortcut_list else R.drawable.ic_health_grid, if (grid) R.string.health_library_list else R.string.health_library_grid) { grid = !grid; load() }.apply { tag = "health-library-mode" })
        })
        ui.add(content, ui.row(getString(R.string.health_library_dates), if (filter.from == 0L && filter.until == Long.MAX_VALUE) getString(R.string.health_library_all_dates) else date(filter.from) + " - " + date(filter.until - 1)) { chooseDates() })
        content.addView(ui.line().apply {
            addView(ui.command(R.string.health_library_select_page) { select(data.page.originals.map { it.id }, true) }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_attention_select, R.string.health_library_clear_selection) { mutate { store, id -> store.clearSelection(id) } })
        })
        if (data.page.originals.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_originals), 15f, muted = true).apply { tag = "health-library-empty" }, 16)
        val columns = if (!grid) 1 else if (resources.configuration.screenWidthDp >= 600) 3 else 2
        data.page.originals.chunked(columns).forEach { row ->
            val line = ui.line().apply { gravity = Gravity.TOP }
            row.forEach { original ->
                line.addView(tile(original, original.id in data.selected, original.id in data.missing, token), LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = ui.dp(6); topMargin = ui.dp(10) })
            }
            repeat(columns - row.size) { line.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f)) }; content.addView(line)
        }
        ui.add(content, ui.line().apply {
            if (previous.isNotEmpty()) addView(ui.command(R.string.health_previous_page) { cursor = previous.removeAt(previous.lastIndex); scrollY = 0; load() }, LinearLayout.LayoutParams(0, -2, 1f))
            data.page.next?.let { next -> addView(ui.command(R.string.health_next_page) { previous += cursor; cursor = next; scrollY = 0; load() }, LinearLayout.LayoutParams(0, -2, 1f)) }
        }, 16)
        data.lastExport?.let { id -> ui.add(content, ui.row(getString(R.string.health_library_last_export)) { openExport(id) }, 16) }
        body.addView(ui.column().apply {
            setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(12))
            addView(ui.text(getString(R.string.health_library_selected, data.count), 13f, muted = true).apply { tag = "health-library-count" })
            addView(ui.command(R.string.health_library_export) { mutate { store, id -> store.prepare(id) } }.apply { isEnabled = data.count > 0; alpha = if (isEnabled) 1f else .4f; tag = "health-library-export" })
        })
        scroll?.post { if (active && token == generation) scroll?.scrollTo(0, scrollY) }
    }
    private fun tile(original: HealthOriginal, selected: Boolean, missing: Boolean, token: Int): View {
        val card = ui.column().apply { setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8)); background = ui.background(radius = 8) }
        val top = ui.line(); val check = CheckBox(this).apply {
            isChecked = selected; contentDescription = getString(R.string.health_library_select_named, original.name)
            setOnCheckedChangeListener { _, value -> select(listOf(original.id), value) }
        }; top.addView(check)
        val image = ImageView(this).apply { setImageResource(if (HealthOriginalKind.of(original) == HealthOriginalKind.IMAGE) R.drawable.ic_process_image else R.drawable.ic_rich_file); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = original.name }
        if (grid) { card.addView(top); card.addView(image, LinearLayout.LayoutParams(-1, ui.dp(128))) }
        else { top.addView(image, LinearLayout.LayoutParams(ui.dp(56), ui.dp(56))); card.addView(top) }
        card.addView(ui.text(original.name, 14f, bold = true).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END })
        card.addView(ui.text("${date(original.importedAt)} \u00b7 ${android.text.format.Formatter.formatShortFileSize(this, original.size)}", 12f, muted = true))
        if (missing) card.addView(ui.text(getString(R.string.health_original_missing), 12f, muted = true))
        card.setOnClickListener { startActivity(Intent(this, HealthCaptureActivity::class.java).putExtra("original", original.id)) }; card.isFocusable = true
        if (!missing && HealthOriginalKind.of(original) in listOf(HealthOriginalKind.IMAGE, HealthOriginalKind.PDF)) tasks += thumbnails.submit {
            val bitmap = runCatching { HealthOriginalStore(applicationContext).use { HealthOriginalThumbnail.load(it, original) } }.getOrNull()
            main.post { if (!active || generation != token) bitmap?.let(HealthOriginalThumbnail::clear) else if (bitmap != null) { image.setImageBitmap(bitmap); images += image to bitmap } }
        }
        return card
    }
    private fun date(time: Long) = Instant.ofEpochMilli(time).atZone(ZoneId.systemDefault()).toLocalDate().toString()
    private fun select(ids: List<String>, selected: Boolean) = mutate { store, id -> store.select(id, ids, selected) }
    private fun mutate(action: (HealthOriginalLibraryStore, String) -> Any) {
        val id = selection; val token = generation; val y = scroll?.scrollY ?: scrollY
        worker.execute {
            val result = runCatching { HealthOriginalStore(applicationContext).use { originals ->
                val library = HealthOriginalLibraryStore(applicationContext, originals); library.ensureSelection(id); action(library, id)
            } }
            main.post { if (active && token == generation) result.fold({ value ->
                if (value is HealthOriginalExportSession && value.state == HealthOriginalExportState.REVIEW) openExport(id) else { scrollY = y; load() }
            }, { android.widget.Toast.makeText(this, R.string.health_storage_error, android.widget.Toast.LENGTH_LONG).show(); load() }) }
        }
    }
    private fun openExport(id: String) { startActivity(Intent(this, HealthOriginalExportActivity::class.java).putExtra("export_id", id)) }
    private fun chooseType() {
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_library_type).setItems((listOf(getString(R.string.health_library_all)) + HealthOriginalKind.entries.map { getString(it.title()) }).toTypedArray()) { _, index ->
            filter = filter.copy(kind = if (index == 0) null else HealthOriginalKind.entries[index - 1]); reset()
        }.setNegativeButton(R.string.common_cancel, null).show()
    }
    private fun chooseDates() {
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_library_dates).setItems(arrayOf(getString(R.string.health_library_all_dates), getString(R.string.health_trend_custom))) { _, index ->
            if (index == 0) { filter = filter.copy(from = 0, until = Long.MAX_VALUE); reset() } else {
                val today = LocalDate.now()
                fun pick(value: LocalDate, title: Int, done: (LocalDate) -> Unit) {
                    dialog = DatePickerDialog(this, { _, y, m, d -> done(LocalDate.of(y, m + 1, d)) }, value.year, value.monthValue - 1, value.dayOfMonth).apply { setTitle(title); datePicker.minDate = 0; datePicker.maxDate = System.currentTimeMillis(); show() }
                }
                pick(today.minusDays(29), R.string.health_trend_from) { first -> pick(today, R.string.health_trend_until) { last ->
                    if (last.isBefore(first)) android.widget.Toast.makeText(this, R.string.health_trend_invalid_dates, android.widget.Toast.LENGTH_LONG).show()
                    else { filter = HealthLibraryFilter.dates(first, last, ZoneId.systemDefault(), filter.kind); reset() }
                } }
            }
        }.setNegativeButton(R.string.common_cancel, null).show()
    }
    private data class LibrarySnapshot(val session: String, val page: HealthLibraryPage, val selected: Set<String>, val count: Long, val lastExport: String?, val missing: Set<String>)
}
internal fun HealthOriginalKind.title(): Int = when (this) { HealthOriginalKind.IMAGE -> R.string.health_library_images; HealthOriginalKind.PDF -> R.string.health_library_pdf; HealthOriginalKind.TABLE -> R.string.health_library_tables; HealthOriginalKind.OTHER -> R.string.health_library_other }
