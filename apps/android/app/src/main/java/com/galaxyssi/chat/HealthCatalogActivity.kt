package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.widget.ArrayAdapter
import android.widget.AdapterView
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.Toast
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

/** Static catalog searches never decrypt the complete observation history. Record mode uses keyset pages. */
class HealthCatalogActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private lateinit var results: LinearLayout
    private var active = false
    @Volatile private var generation = 0
    private var mode = 0
    private var group = -1
    private var query = ""
    private var cursor: HealthPageCursor? = null
    private val previous = arrayListOf<HealthPageCursor?>()
    private var search: EditText? = null
    private val pending = Runnable { load() }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        mode = state?.getInt("mode")?.coerceIn(0, 2) ?: 0
        group = state?.getInt("group")?.takeIf { it in HealthMetricGroup.entries.indices } ?: -1
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_catalog_title), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                startActivity(Intent(this@HealthCatalogActivity, HealthCenterActivity::class.java).putExtra("health_functions", true))
            })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() { super.onStart(); active = true; controls(); load() }
    override fun onStop() {
        active = false; generation++; main.removeCallbacks(pending); query = ""; search = null
        resetPage(); if (::results.isInitialized) results.removeAllViews()
        if (::body.isInitialized) body.removeAllViews()
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(state: Bundle) { state.putInt("mode", mode); state.putInt("group", group); super.onSaveInstanceState(state) }
    private fun controls() {
        body.removeAllViews()
        val filters = ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(8)) }
        search = EditText(this).apply {
            tag = "health-catalog-search"; isSaveEnabled = false; hint = getString(R.string.health_catalog_search)
            isSingleLine = true; textSize = 15f; setTextColor(getColor(R.color.text_primary)); minimumHeight = ui.dp(48)
            setBackgroundColor(android.graphics.Color.TRANSPARENT); setPadding(0, ui.dp(4), ui.dp(8), ui.dp(4))
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            this.filters = arrayOf(android.text.InputFilter.LengthFilter(80))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun afterTextChanged(s: Editable?) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    query = s.toString(); resetPage(); generation++; main.removeCallbacks(pending); main.postDelayed(pending, 150)
                }
            })
        }.also { edit -> filters.addView(ui.line().apply {
            background = ui.background(getColor(R.color.button_soft), radius = 8)
            setPadding(ui.dp(12), 0, 0, 0)
            addView(android.widget.ImageView(this@HealthCatalogActivity).apply {
                setImageResource(R.drawable.ic_hub_search)
                imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.text_secondary))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)).apply { marginEnd = ui.dp(8) })
            addView(edit, LinearLayout.LayoutParams(0, -2, 1f))
        }) }
        filters.addView(RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL; tag = "health-catalog-tabs"
            background = ui.background(getColor(R.color.button_soft), radius = 8); setPadding(ui.dp(3), ui.dp(3), ui.dp(3), ui.dp(3))
            listOf(R.string.health_catalog_daily, R.string.health_catalog_laboratory, R.string.health_all_records).forEachIndexed { index, label ->
                addView(RadioButton(this@HealthCatalogActivity).apply {
                    id = View.generateViewId(); tag = "health-catalog-mode-$index"; text = getString(label); textSize = 13f
                    buttonDrawable = null; backgroundTintList = null; gravity = Gravity.CENTER; minWidth = 0
                    setPadding(ui.dp(4), ui.dp(6), ui.dp(4), ui.dp(6))
                    background = android.graphics.drawable.StateListDrawable().apply {
                        addState(intArrayOf(android.R.attr.state_checked), ui.background(getColor(R.color.surface_bg), radius = 6))
                        addState(intArrayOf(), ui.background(android.graphics.Color.TRANSPARENT, radius = 6))
                    }
                    minHeight = ui.dp(48); setTextColor(getColor(R.color.text_primary)); isChecked = mode == index
                    setOnClickListener { if (mode != index) { mode = index; resetPage(); load() } }
                }, RadioGroup.LayoutParams(0, -2, 1f))
            }
        })
        filters.addView(Spinner(this).apply {
            tag = "health-catalog-group"; minimumHeight = ui.dp(48)
            adapter = ArrayAdapter(this@HealthCatalogActivity, android.R.layout.simple_spinner_dropdown_item,
                listOf(getString(R.string.health_catalog_all_groups)) + HealthMetricGroup.entries.map { getString(it.titleResource()) })
            setSelection(group + 1, false)
            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onNothingSelected(parent: AdapterView<*>?) = Unit
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    if (group != position - 1) { group = position - 1; resetPage(); load() }
                }
            }
        })
        body.addView(filters)
        results = ui.column().apply { setPadding(ui.dp(16), 0, ui.dp(16), ui.dp(24)) }
        body.addView(ScrollView(this).apply { addView(results); isFillViewport = true }, LinearLayout.LayoutParams(-1, 0, 1f))
    }
    private fun resetPage() { cursor = null; previous.clear() }
    private fun load() {
        if (!active || !::results.isInitialized) return
        val token = ++generation; val recordMode = mode == 2; val pageCursor = cursor
        val entries = HealthMetricCatalog.search(query, when (mode) { 0 -> false; 1 -> true; else -> null }, HealthMetricGroup.entries.getOrNull(group))
        results.removeAllViews(); results.addView(ui.text(getString(R.string.health_loading), 14f, muted = true))
        worker.execute {
            if (token != generation) return@execute
            val data = runCatching { HealthRecordStore(applicationContext).use { store ->
                if (recordMode) emptyMap<HealthMetric, HealthObservation?>() to store.page(after = pageCursor, metrics = entries.map { it.metric }.toSet())
                else entries.associate { it.metric to store.page(metric = it.metric, limit = 1).records.firstOrNull() } to HealthRecordPage(emptyList(), null)
            } }
            main.post {
                if (!active || token != generation) return@post
                data.fold({ (latest, page) ->
                    results.removeAllViews()
                    if (recordMode) {
                        page.records.forEach { record -> recordRow(record) }
                        if (page.records.isEmpty()) results.addView(ui.text(getString(R.string.health_no_records), 14f, muted = true))
                        if (previous.isNotEmpty()) ui.add(results, ui.command(R.string.health_previous_page) { cursor = previous.removeAt(previous.lastIndex); load() }, 12)
                        page.next?.let { next -> ui.add(results, ui.command(R.string.health_next_page) { previous += cursor; cursor = next; load() }, 12) }
                    } else {
                        if (entries.isEmpty()) results.addView(ui.text(getString(R.string.health_catalog_no_match), 14f, muted = true))
                        entries.forEach { entry -> catalogRow(entry, latest[entry.metric]) }
                    }
                }, { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show()
                    results.removeAllViews(); results.addView(ui.command(R.string.common_retry) { load() }) })
            }
        }
    }
    private fun catalogRow(entry: HealthMetricEntry, latest: HealthObservation?) {
        val row = ui.row(getString(entry.metric.titleResource()), entry.aliases.joinToString(" / ")) {
            startActivity(Intent(this, HealthTrendActivity::class.java).putExtra("health_metric", entry.metric.name))
        }.apply { tag = "health-catalog-${entry.metric.name}" }
        val text = row.getChildAt(0) as LinearLayout
        val color = when (entry.group) {
            HealthMetricGroup.SLEEP -> 0xff8063ae.toInt()
            HealthMetricGroup.ACTIVITY -> 0xffbd741e.toInt()
            HealthMetricGroup.CARDIOVASCULAR -> 0xff168c6e.toInt()
            else -> 0xff3a77ad.toInt()
        }
        row.addView(android.widget.ImageView(this).apply {
            setImageResource(if (entry.laboratory) R.drawable.ic_rich_file else R.drawable.ic_health_heart)
            imageTintList = android.content.res.ColorStateList.valueOf(color)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, 0, LinearLayout.LayoutParams(ui.dp(28), ui.dp(28)).apply { marginEnd = ui.dp(12); gravity = Gravity.TOP; topMargin = ui.dp(4) })
        ui.add(text, ui.text(entry.metric.units.filter(String::isNotBlank).joinToString(" / ").ifBlank { getString(R.string.health_unit_not_applicable) }, 12f, muted = true), 4)
        ui.add(text, ui.text(latest?.let(::display) ?: getString(R.string.health_no_measurement), 17f, bold = latest != null), 6)
        latest?.let { ui.add(text, ui.text(date(it.draft.measuredAt) + " \u00b7 " + getString(healthRecordSourceResource(it.source)), 12f, muted = true), 3) }
        results.addView(row); separator()
    }
    private fun recordRow(record: HealthObservation) {
        results.addView(ui.row(getString(record.draft.metric.titleResource()), display(record) + "\n" + date(record.draft.measuredAt) + " \u00b7 " + getString(healthRecordSourceResource(record.source))) {
            startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", record.id))
        }); separator()
    }
    private fun separator() { results.addView(View(this).apply { setBackgroundColor(getColor(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1))) }
    private fun date(time: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(time))
    private fun display(record: HealthObservation): String = healthDisplayValue(record.draft)
}

internal fun healthDisplayValue(draft: HealthDraft): String {
    fun value(field: String) = draft.reportedValues[field] ?: draft.values[field].orEmpty()
    val values = if (draft.metric == HealthMetric.BLOOD_PRESSURE) "${value("systolic")} / ${value("diastolic")}" else value(draft.metric.requiredFields.first())
    return (values + " " + draft.unit).trim()
}
internal fun healthRecordSourceResource(source: String) = when (source) {
    "ocr" -> R.string.health_source_ocr
    "table" -> R.string.health_source_table
    "manual" -> R.string.health_source_manual
    "health_connect" -> R.string.health_sources_platform_name
    else -> R.string.health_trend_other_source
}
