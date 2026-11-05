package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.ColorStateList
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.StateListDrawable
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.CheckBox
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.view.OneShotPreDrawListener
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future

class HealthOriginalLibraryActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private fun openOriginals() = HealthExportShare.openOriginals(applicationContext, names.fixture)
    private fun library(originals: HealthOriginalStore) = HealthExportShare.originalLibrary(applicationContext, originals, names.fixture)
    private val worker = Executors.newSingleThreadExecutor()
    private val thumbnails = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private lateinit var results: LinearLayout
    private lateinit var footer: LinearLayout
    private lateinit var selectedCount: TextView
    private lateinit var export: TextView
    private val tabs = ArrayList<RadioButton>(3)
    private var search: EditText? = null
    private var query = ""
    private var filter = HealthLibraryFilter()
    private var grid = true
    private var selection = ""
    private var scrollY = 0
    private var scroll: ScrollView? = null
    private var active = false
    private var openedChild = false
    private var preparing = false
    private var generation = 0
    private var mutation = 0
    private var signal: CancellationSignal? = null
    private var dialog: AlertDialog? = null
    private val previous = arrayListOf<Pair<Long, String>?>()
    private var cursor: Pair<Long, String>? = null
    private var shown = emptyList<HealthOriginal>()
    private var count = 0L
    private val tiles = HashMap<String, Pair<View, CheckBox>>()
    private val images = arrayListOf<Pair<ImageView, Bitmap>>()
    private val tasks = arrayListOf<Future<*>>()
    private val pending = Runnable { load() }
    private val refresh = Runnable { load(keepPosition = true) }
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            if (!active || main.hasCallbacks(pending)) return
            main.removeCallbacks(refresh)
            main.postDelayed(refresh, 120)
        }
    }
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { clearQuery() }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        filter = runCatching {
            HealthLibraryFilter(state?.getString("kind")?.let(HealthOriginalKind::valueOf), state?.getLong("from") ?: 0,
                state?.getLong("until") ?: Long.MAX_VALUE, state?.getBoolean("files_only") == true)
        }.getOrDefault(HealthLibraryFilter())
        grid = state?.getBoolean("grid", true) ?: true
        selection = state?.getString("selection").orEmpty()
        scrollY = state?.getInt("scroll") ?: 0
        state?.getString("cursor")?.let { cursor = readCursor(it) }
        state?.getStringArrayList("previous")?.forEach { previous += readCursor(it) }
        window.statusBarColor = getColor(R.color.surface_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            minimumHeight = ui.dp(56)
            setBackgroundColor(getColor(R.color.surface_bg))
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_original_library), 19f, bold = true).apply { gravity = Gravity.CENTER },
                LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                open(HealthCenterActivity::class.java) { putExtra("health_functions", true) }
            })
        })
        body = ui.column().apply { isFocusableInTouchMode = true }
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        ContextCompat.registerReceiver(this, screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onStart() {
        super.onStart()
        active = true
        openedChild = false
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this).buildUpon().appendPath("originals").build(), false, observer)
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, observer)
        controls()
        load()
    }

    override fun onResume() {
        super.onResume()
        openedChild = false
    }

    override fun onStop() {
        active = false
        generation++
        signal?.cancel(); signal = null
        main.removeCallbacks(pending); main.removeCallbacks(refresh)
        contentResolver.unregisterContentObserver(observer)
        scrollY = scroll?.scrollY ?: scrollY
        if (!openedChild) clearQuery()
        preparing = false
        count = 0
        search?.setText(""); search = null
        tabs.clear()
        scroll = null
        dialog?.dismiss(); dialog = null
        clearResults()
        body.removeAllViews()
        super.onStop()
    }

    override fun onDestroy() {
        unregisterReceiver(screenOff)
        worker.shutdown()
        thumbnails.shutdownNow()
        super.onDestroy()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) clearQuery()
    }

    override fun onSaveInstanceState(out: Bundle) {
        out.putString("kind", filter.kind?.name)
        out.putBoolean("files_only", filter.filesOnly)
        out.putLong("from", filter.from); out.putLong("until", filter.until)
        out.putBoolean("grid", grid); out.putString("selection", selection)
        if (query.isBlank()) {
            out.putString("cursor", writeCursor(cursor))
            out.putStringArrayList("previous", ArrayList(previous.map(::writeCursor)))
            out.putInt("scroll", scroll?.scrollY ?: scrollY)
        }
        super.onSaveInstanceState(out)
    }

    private fun readCursor(text: String): Pair<Long, String>? =
        text.split('|', limit = 2).takeIf { it.size == 2 && HealthProfilePolicy.uuid(it[1]) }
            ?.let { parts -> parts[0].toLongOrNull()?.let { it to parts[1] } }
    private fun writeCursor(value: Pair<Long, String>?) = value?.let { "${it.first}|${it.second}" }.orEmpty()

    private fun controls() {
        val top = ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(6)) }
        search = EditText(this).apply {
            tag = "health-library-search"
            isSaveEnabled = false
            isSingleLine = true
            textSize = 15f
            minimumHeight = ui.dp(48)
            hint = getString(R.string.health_library_search)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            filters = arrayOf(InputFilter.LengthFilter(120))
            setTextColor(getColor(R.color.text_primary))
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(0, 0, ui.dp(8), 0)
            setText(query)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun afterTextChanged(s: Editable?) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    if (!active) return
                    query = s?.toString().orEmpty()
                    resetPosition(); cancelLoad()
                    clearResults()
                    status(R.string.health_library_searching)
                    updateTabs(null)
                    main.postDelayed(pending, 150)
                }
            })
        }.also { edit ->
            ui.add(top, ui.line().apply {
                background = ui.background(getColor(R.color.button_soft), radius = 8)
                setPadding(ui.dp(12), 0, 0, 0)
                addView(ImageView(this@HealthOriginalLibraryActivity).apply {
                    setImageResource(R.drawable.ic_hub_search)
                    imageTintList = ColorStateList.valueOf(getColor(R.color.text_secondary))
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)).apply { marginEnd = ui.dp(8) })
                addView(edit, LinearLayout.LayoutParams(0, -2, 1f))
            })
        }
        ui.add(top, RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            background = ui.background(getColor(R.color.button_soft), radius = 8)
            setPadding(ui.dp(3), ui.dp(3), ui.dp(3), ui.dp(3))
            tabTitles.forEachIndexed { index, title ->
                val tab = RadioButton(this@HealthOriginalLibraryActivity).apply {
                    id = View.generateViewId(); tag = "health-library-tab-$index"
                    setText(title); textSize = 13f
                    buttonDrawable = null; backgroundTintList = null; gravity = Gravity.CENTER; minWidth = 0
                    minimumHeight = ui.dp(44)
                    setPadding(ui.dp(4), ui.dp(6), ui.dp(4), ui.dp(6))
                    setTextColor(getColor(R.color.text_primary))
                    background = StateListDrawable().apply {
                        addState(intArrayOf(android.R.attr.state_checked), ui.background(getColor(R.color.surface_bg), radius = 6))
                        addState(intArrayOf(), ui.background(Color.TRANSPARENT, radius = 6))
                    }
                    setOnClickListener {
                        filter = filter.copy(kind = if (index == 1) HealthOriginalKind.IMAGE else null, filesOnly = index == 2)
                        reset()
                    }
                }
                tabs += tab
                addView(tab, RadioGroup.LayoutParams(0, -2, 1f))
            }
        }, 8)
        body.addView(top)
        results = ui.column()
        body.addView(results, LinearLayout.LayoutParams(-1, 0, 1f))
        footer = ui.column().apply {
            setBackgroundColor(getColor(R.color.surface_bg))
            setPadding(ui.dp(16), ui.dp(6), ui.dp(16), ui.dp(10))
        }
        selectedCount = ui.text("", 13f, muted = true).apply { tag = "health-library-count" }
        footer.addView(selectedCount)
        ui.add(footer, ui.line().apply {
            addView(ui.command(R.string.health_library_continue_import) {
                open(HealthCenterActivity::class.java) { putExtra("health_import_center", true) }
            }.apply {
                background = ui.background(stroke = getColor(R.color.separator), radius = 10)
                setTextColor(getColor(R.color.text_primary)); tag = "health-library-import"
            }, LinearLayout.LayoutParams(0, -1, 1f).apply { marginEnd = ui.dp(8) })
            export = ui.command(R.string.health_library_export) { prepareExport() }.apply { tag = "health-library-export" }
            addView(export, LinearLayout.LayoutParams(0, -1, 1f))
        }, 6)
        body.addView(footer)
        updateTabs(null)
        renderSelection(0, emptySet())
        body.requestFocus()
    }

    private fun updateTabs(counts: Map<HealthOriginalKind, Long>?) {
        val group = when {
            filter.kind == HealthOriginalKind.IMAGE -> 1
            filter.filesOnly || filter.kind != null -> 2
            else -> 0
        }
        val all = counts?.values?.sum() ?: 0L
        val photos = counts?.get(HealthOriginalKind.IMAGE) ?: 0L
        val sizes = listOf(all, photos, all - photos)
        tabs.forEachIndexed { index, tab ->
            tab.text = if (counts == null) getString(tabTitles[index]) else getString(R.string.health_library_tab_count,
                getString(tabTitles[index]), sizes[index])
        }
        tabs.getOrNull(group)?.let { (it.parent as RadioGroup).check(it.id) }
    }

    private fun clearQuery() {
        if (query.isEmpty()) return
        query = ""
        resetPosition()
        if (active) search?.setText("")
    }
    private fun clearResults() {
        tasks.forEach { it.cancel(true) }; tasks.clear()
        images.forEach { (view, bitmap) -> view.setImageDrawable(null); HealthOriginalThumbnail.clear(bitmap) }; images.clear()
        tiles.clear()
        shown = emptyList()
        results.removeAllViews()
        scroll = null
    }
    private fun resetPosition() { cursor = null; previous.clear(); scrollY = 0 }
    private fun reset() { resetPosition(); load() }
    private fun cancelLoad() {
        generation++
        signal?.cancel(); signal = null
        main.removeCallbacks(pending); main.removeCallbacks(refresh)
    }

    private fun load(keepPosition: Boolean = false) {
        if (!active || preparing) return
        if (keepPosition) scrollY = scroll?.scrollY ?: scrollY
        cancelLoad()
        val token = generation
        val cancellation = CancellationSignal().also { signal = it }
        val options = filter
        val text = query.trim()
        val after = cursor
        val selected = selection
        clearResults()
        status(if (text.isEmpty()) R.string.health_library_loading else R.string.health_library_searching)
        updateTabs(null)
        worker.execute {
            val result = runCatching {
                cancellation.throwIfCanceled()
                openOriginals().use { originals ->
                    val library = library(originals)
                    val existing = selected.takeIf(String::isNotBlank)?.let(library::session)
                    val id = existing?.takeIf { it.state == HealthOriginalExportState.SELECTING }?.id
                        ?: selected.takeIf { it.isNotBlank() && existing == null } ?: UUID.randomUUID().toString()
                    val page = if (text.isEmpty()) originals.library(options, after, cancellation) else {
                        val search = HealthOriginalLibrarySearch(text, ZoneId.systemDefault())
                        HealthRecordStore(applicationContext, names.records).use { records ->
                            originals.library(options, after, cancellation) { search.matches(it, records, cancellation) }
                        }
                    }
                    val counts = if (text.isEmpty()) originals.libraryCounts(options, cancellation) else null
                    LibrarySnapshot(id, page, library.selected(id, page.originals), library.count(id),
                        page.originals.filterNot(originals::present).map { it.id }.toSet(), counts)
                }
            }
            main.post {
                if (active && token == generation) result.fold({ selection = it.session; render(it, token) }, {
                    clearResults()
                    status(R.string.health_storage_error)
                    results.addView(ui.command(R.string.common_retry) { load() })
                })
            }
        }
    }

    private fun status(resource: Int) {
        results.addView(ui.text(getString(resource), 14f, muted = true).apply {
            setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(12))
        })
    }

    private fun render(data: LibrarySnapshot, token: Int) {
        results.removeAllViews()
        updateTabs(data.counts)
        val content = ui.column().apply { setPadding(ui.dp(16), 0, ui.dp(16), ui.dp(16)) }
        val currentScroll = ScrollView(this).apply { addView(content) }
        scroll = currentScroll
        results.addView(currentScroll, LinearLayout.LayoutParams(-1, -1))
        content.addView(ui.line().apply {
            addView(filterControl(R.string.health_library_type, getString(filter.kind?.title()
                ?: if (filter.filesOnly) R.string.health_library_tab_files else R.string.health_library_all), ::chooseType),
                LinearLayout.LayoutParams(0, -1, 1f).apply { marginEnd = ui.dp(6) })
            val dateLabel = if (filter.from == 0L && filter.until == Long.MAX_VALUE) getString(R.string.health_library_all_dates)
                else getString(R.string.health_library_date_range, date(filter.from), date(filter.until - 1))
            addView(filterControl(R.string.health_library_dates, dateLabel, ::chooseDates), LinearLayout.LayoutParams(0, -1, 1f))
            addView(ui.icon(if (grid) R.drawable.ic_chat_shortcut_list else R.drawable.ic_health_grid,
                if (grid) R.string.health_library_list else R.string.health_library_grid) { grid = !grid; scrollY = 0; load() }
                .apply { tag = "health-library-mode" })
        })
        val items = data.page.originals
        shown = items
        content.addView(ui.line().apply {
            addView(ui.text(getString(R.string.health_library_select_page), 14f, bold = true).apply {
                minimumHeight = ui.dp(48); gravity = Gravity.CENTER_VERTICAL
                setTextColor(getColor(R.color.health_data_link_text))
                isFocusable = true; setOnClickListener { select(items.map { it.id }, true) }
                isEnabled = items.isNotEmpty(); alpha = if (isEnabled) 1f else .45f
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_agent_progress_close, R.string.health_library_clear_selection) {
                changeSelection { store, id -> store.clearSelection(id) }
            })
        })
        if (items.isEmpty()) ui.add(content, ui.text(getString(if (query.isBlank()) R.string.health_no_originals
            else R.string.health_library_no_matches), 15f, muted = true).apply { tag = "health-library-empty" }, 16)
        val (photos, files) = if (grid) items.partition { HealthOriginalKind.of(it) == HealthOriginalKind.IMAGE } else emptyList<HealthOriginal>() to items
        val columns = if (resources.configuration.screenWidthDp >= 760) 3 else 2
        photos.chunked(columns).forEach { row ->
            ui.add(content, ui.line().apply {
                gravity = Gravity.TOP
                row.forEachIndexed { index, original ->
                    addView(tile(original, original.id in data.missing, token, preview = true), LinearLayout.LayoutParams(0, -2, 1f)
                        .apply { if (index < columns - 1) marginEnd = ui.dp(8) })
                }
                repeat(columns - row.size) { addView(View(this@HealthOriginalLibraryActivity), LinearLayout.LayoutParams(0, 1, 1f)) }
            }, 8)
        }
        files.forEach { original -> ui.add(content, tile(original, original.id in data.missing, token, preview = false), 8) }
        ui.add(content, ui.line().apply {
            if (previous.isNotEmpty()) addView(ui.command(R.string.health_previous_page) {
                cursor = previous.removeAt(previous.lastIndex); scrollY = 0; load()
            }.apply { tag = "health-library-previous" }, LinearLayout.LayoutParams(0, -2, 1f))
            data.page.next?.let { next -> addView(ui.command(R.string.health_next_page) {
                previous += cursor; cursor = next; scrollY = 0; load()
            }.apply { tag = "health-library-next" }, LinearLayout.LayoutParams(0, -2, 1f)) }
        }, 12)
        ui.add(content, ui.row(getString(R.string.health_library_export_history)) {
            open(HealthOriginalExportHistoryActivity::class.java) { putExtra("health_original_export_test_id", names.fixture) }
        }, 12)
        renderSelection(data.count, data.selected)
        OneShotPreDrawListener.add(currentScroll) {
            if (active && token == generation && scroll === currentScroll) currentScroll.scrollTo(0, scrollY)
        }
    }

    private fun filterControl(label: Int, value: String, click: () -> Unit) = ui.line().apply {
        minimumHeight = ui.dp(48)
        setPadding(ui.dp(8), ui.dp(5), ui.dp(6), ui.dp(5))
        background = ui.background(stroke = getColor(R.color.separator), radius = 8)
        contentDescription = getString(R.string.health_library_filter_value, getString(label), value)
        addView(ui.text(value, 13f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
        addView(ImageView(this@HealthOriginalLibraryActivity).apply {
            setImageResource(R.drawable.ic_chevron_down)
            imageTintList = ColorStateList.valueOf(getColor(R.color.text_primary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(ui.dp(16), ui.dp(16)))
        isFocusable = true
        setOnClickListener { click() }
    }

    private fun tile(original: HealthOriginal, missing: Boolean, token: Int, preview: Boolean): View {
        val kind = HealthOriginalKind.of(original)
        val card = ui.column().apply {
            tag = "health-library-original-${original.id}"
            setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
            background = ui.background(stroke = getColor(R.color.separator), radius = 8)
        }
        val check = CheckBox(this).apply {
            tag = "health-library-check-${original.id}"
            contentDescription = getString(R.string.health_library_select_named, original.name)
            setOnClickListener { if (preparing) isChecked = !isChecked else select(listOf(original.id), isChecked) }
        }
        tiles[original.id] = card to check
        val image = ImageView(this).apply {
            setImageResource(when (kind) {
                HealthOriginalKind.IMAGE -> R.drawable.ic_process_image
                HealthOriginalKind.TABLE -> R.drawable.ic_health_data_chart
                else -> R.drawable.ic_rich_file
            })
            setColorFilter(getColor(R.color.health_data_link_text))
            scaleType = ImageView.ScaleType.FIT_CENTER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val info = ui.column().apply {
            addView(ui.text(original.name, 14f, bold = true).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END })
            addView(ui.text(getString(R.string.health_library_file_meta, date(original.importedAt),
                Formatter.formatShortFileSize(this@HealthOriginalLibraryActivity, original.size)), 12f).apply {
                setTextColor(getColor(R.color.health_data_meta_text))
            })
            if (missing) addView(ui.text(getString(R.string.health_data_missing), 12f).apply {
                setTextColor(getColor(R.color.health_data_warning_text))
            })
        }
        if (preview) {
            card.addView(ui.line().apply { gravity = Gravity.END or Gravity.CENTER_VERTICAL; addView(check) })
            image.setPadding(ui.dp(8), ui.dp(4), ui.dp(8), ui.dp(4))
            image.setBackgroundColor(getColor(R.color.health_data_summary_fill))
            card.addView(image, LinearLayout.LayoutParams(-1, ui.dp(128)))
            ui.add(card, info, 8)
        } else {
            image.setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
            image.background = ui.background(getColor(R.color.health_data_summary_fill), radius = 8)
            card.addView(ui.line().apply {
                addView(image, LinearLayout.LayoutParams(ui.dp(36), ui.dp(36)).apply { marginEnd = ui.dp(8) })
                addView(info, LinearLayout.LayoutParams(0, -2, 1f))
                addView(check)
            })
        }
        card.setOnClickListener { open(HealthCaptureActivity::class.java) { putExtra("original", original.id) } }
        card.isFocusable = true
        if (!missing && preview) tasks += thumbnails.submit {
            val bitmap = runCatching { openOriginals().use { HealthOriginalThumbnail.load(it, original) } }.getOrNull()
            main.post {
                if (!active || generation != token) bitmap?.let(HealthOriginalThumbnail::clear)
                else if (bitmap != null) { image.clearColorFilter(); image.setImageBitmap(bitmap); images += image to bitmap }
            }
        }
        return card
    }

    private fun date(time: Long) = Instant.ofEpochMilli(time).atZone(ZoneId.systemDefault()).toLocalDate().toString()
    private fun select(ids: List<String>, selected: Boolean) =
        changeSelection { store, id -> store.select(id, ids, selected) }

    private fun renderSelection(total: Long, ids: Set<String>) {
        count = total
        selectedCount.text = getString(R.string.health_library_selected, total)
        export.text = getString(R.string.health_library_export_selected, total)
        updateExportButton()
        tiles.forEach { (id, tile) ->
            val (card, check) = tile
            check.isChecked = id in ids
            card.background = ui.background(stroke =
                getColor(if (check.isChecked) R.color.health_data_link_text else R.color.separator), radius = 8)
        }
    }
    private fun updateExportButton() {
        export.isEnabled = !preparing && count > 0
        export.alpha = if (export.isEnabled) 1f else .45f
    }

    private fun changeSelection(action: (HealthOriginalLibraryStore, String) -> Unit) {
        if (preparing || selection.isBlank()) return
        val id = selection
        val page = shown
        val token = generation
        val sequence = ++mutation
        worker.execute {
            val result = runCatching { openOriginals().use { originals ->
                val library = library(originals)
                library.ensureSelection(id)
                action(library, id)
                library.count(id) to library.selected(id, page)
            } }
            main.post {
                if (!active || selection != id || mutation != sequence) return@post
                result.fold({ (total, selected) ->
                    if (generation == token) renderSelection(total, selected)
                }, { error(); load(keepPosition = true) })
            }
        }
    }

    private fun prepareExport() {
        if (preparing || count == 0L || selection.isBlank()) return
        val id = selection
        preparing = true
        updateExportButton()
        worker.execute {
            val result = runCatching { openOriginals().use { library(it).prepare(id) } }
            main.post {
                if (!active || selection != id) return@post
                preparing = false
                updateExportButton()
                result.fold({
                    open(HealthOriginalExportActivity::class.java) {
                        putExtra("export_id", id); putExtra("health_original_export_test_id", names.fixture)
                        putExtra("health_return_to_selection", true)
                    }
                }, { error(); load(keepPosition = true) })
            }
        }
    }
    private fun error() = Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show()
    private fun open(type: Class<*>, extras: Intent.() -> Unit = {}) {
        if (preparing) return
        openedChild = true
        startActivity(Intent(this, type).putHealthNavigationFixture(names).apply(extras))
    }

    private fun chooseType() {
        val kinds = HealthOriginalKind.entries
        val labels = listOf(R.string.health_library_all, R.string.health_library_tab_files) + kinds.map { it.title() }
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_library_type)
            .setItems(labels.map(::getString).toTypedArray()) { _, index ->
                filter = filter.copy(kind = kinds.getOrNull(index - 2), filesOnly = index == 1)
                reset()
            }.setNegativeButton(R.string.common_cancel, null).show()
    }
    private fun chooseDates() {
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_library_dates)
            .setItems(arrayOf(getString(R.string.health_library_all_dates), getString(R.string.health_trend_custom))) { _, index ->
                if (index == 0) { filter = filter.copy(from = 0, until = Long.MAX_VALUE); reset() } else {
                    val today = LocalDate.now()
                    fun pick(value: LocalDate, title: Int, done: (LocalDate) -> Unit) {
                        dialog = DatePickerDialog(this, { _, y, m, d -> done(LocalDate.of(y, m + 1, d)) },
                            value.year, value.monthValue - 1, value.dayOfMonth).apply {
                            setTitle(title); datePicker.minDate = 0; datePicker.maxDate = System.currentTimeMillis(); show()
                        }
                    }
                    pick(today.minusDays(29), R.string.health_trend_from) { first -> pick(today, R.string.health_trend_until) { last ->
                        if (last.isBefore(first)) Toast.makeText(this, R.string.health_trend_invalid_dates, Toast.LENGTH_LONG).show()
                        else {
                            val dates = HealthLibraryFilter.dates(first, last, ZoneId.systemDefault())
                            filter = filter.copy(from = dates.from, until = dates.until)
                            reset()
                        }
                    } }
                }
            }.setNegativeButton(R.string.common_cancel, null).show()
    }

    private data class LibrarySnapshot(val session: String, val page: HealthLibraryPage, val selected: Set<String>, val count: Long,
                                       val missing: Set<String>, val counts: Map<HealthOriginalKind, Long>?)
    private companion object {
        val tabTitles = listOf(R.string.health_library_tab_all, R.string.health_library_tab_photos, R.string.health_library_tab_files)
    }
}

internal fun HealthOriginalKind.title(): Int = when (this) {
    HealthOriginalKind.IMAGE -> R.string.health_library_images
    HealthOriginalKind.PDF -> R.string.health_library_pdf
    HealthOriginalKind.TABLE -> R.string.health_library_tables
    HealthOriginalKind.OTHER -> R.string.health_library_other
}
