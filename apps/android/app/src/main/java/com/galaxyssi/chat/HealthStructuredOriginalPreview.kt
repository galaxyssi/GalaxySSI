package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

internal class HealthStructuredOriginalPreview(
    private val activity: Activity, private val original: HealthOriginal, private val names: HealthOverviewDatabases,
    private val onSave: (() -> Unit)?
) : Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar) {
    private val ui = HealthCenterViews(activity)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var sheetControl: TextView
    private lateinit var status: TextView
    private lateinit var content: LinearLayout
    private var subdialog: AlertDialog? = null
    private var generation = 0
    private var released = false
    private val format = requireNotNull(HealthTableParser.format(original.name, original.mime))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setOwnerActivity(activity)
        window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val root = ui.column().apply { setBackgroundColor(activity.getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { dismiss() })
            addView(ui.text(original.name, 16f, bold = true).apply {
                gravity = Gravity.CENTER
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, -2, 1f))
            if (onSave == null) addView(View(activity), LinearLayout.LayoutParams(ui.dp(48), 1))
            else addView(ui.icon(R.drawable.ic_rich_download, R.string.health_save_original, onSave).apply { tag = "health-structured-save" })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        sheetControl = ui.text("", 14f, bold = true).apply {
            visibility = View.GONE
            tag = "health-structured-sheets"
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = ui.dp(48)
            setPadding(ui.dp(12), ui.dp(6), ui.dp(12), ui.dp(6))
            background = ui.background(stroke = activity.getColor(R.color.separator), radius = 8)
        }
        root.addView(sheetControl, LinearLayout.LayoutParams(-1, -2).apply {
            marginStart = ui.dp(12); marginEnd = ui.dp(12); bottomMargin = ui.dp(8)
        })
        status = ui.text("", 13f, muted = true).apply {
            setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(10))
            tag = "health-structured-status"
        }
        root.addView(status)
        content = ui.column().apply { tag = "health-structured-sample" }
        root.addView(ScrollView(activity).apply {
            addView(content, android.widget.FrameLayout.LayoutParams(-1, -2))
        }, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        window?.setLayout(-1, -1)
        setOnDismissListener {
            released = true; generation++
            subdialog?.dismiss(); subdialog = null
            sheetControl.setOnClickListener(null); sheetControl.text = ""; status.text = ""
            content.removeAllViews()
            main.removeCallbacksAndMessages(null)
            worker.shutdownNow()
        }
        load(null)
    }

    private fun load(sheet: Int?) {
        val request = ++generation
        content.removeAllViews()
        sheetControl.isEnabled = false
        status.setText(R.string.health_import_preparing)
        worker.execute {
            val result = runCatching {
                HealthOriginalStore(activity.applicationContext, names.originals, names.originalRoot(activity.applicationContext)).use {
                    HealthStructuredPreview.read(it, original, sheet) {
                        if (Thread.currentThread().isInterrupted) throw CancellationException()
                    }
                }
            }
            main.post {
                if (released || request != generation) return@post
                result.fold(::render) { failure ->
                    status.setText(if ((failure as? HealthImportFailure)?.code == "structured_preview_limit") R.string.health_structured_limit
                        else R.string.health_original_preview_failed)
                    sheetControl.isEnabled = true
                }
            }
        }
    }

    private fun render(sample: HealthStructuredSample) {
        sheetControl.visibility = if (sample.sheets.isEmpty()) View.GONE else View.VISIBLE
        sheetControl.isEnabled = sample.sheets.size > 1
        if (sample.sheets.isNotEmpty()) {
            val current = sample.sheets.indexOfFirst { it.index == sample.selectedSheet }
            val label = activity.getString(R.string.health_structured_sheet_name, sample.sheets[current].name)
            sheetControl.text = if (sample.sheets.size > 1) "$label  \u203a" else label
            sheetControl.setOnClickListener {
                show(AlertDialog.Builder(activity).setTitle(R.string.health_structured_sheet)
                    .setSingleChoiceItems(sample.sheets.map { it.name }.toTypedArray(), current) { dialog, index ->
                        dialog.dismiss()
                        if (index != current) load(sample.sheets[index].index)
                    }.setNegativeButton(android.R.string.cancel, null).create())
            }
        }
        if (sample.rows.isEmpty()) { status.setText(R.string.health_structured_empty); return }
        status.text = listOfNotNull(
            activity.getString(if (sample.more) R.string.health_structured_first_rows else R.string.health_structured_rows, sample.rows.size),
            if (sample.columnsClipped) activity.getString(R.string.health_structured_columns, HealthStructuredPreview.COLUMNS) else null
        ).joinToString(" · ")
        val columns = sample.rows.maxOf { it.cells.size }
        val widths = (0 until columns).map { if (format == "json" && (!sample.jsonKeys || it > 0)) 260 else 132 }
        val table = ui.column()
        val header = listOf("#") + (0 until columns).map {
            if (format == "json") activity.getString(if (sample.jsonKeys && it == 0) R.string.health_structured_key else R.string.health_structured_value)
            else ('A' + it).toString()
        }
        table.addView(row(header, widths, true, -1))
        for ((index, entry) in sample.rows.withIndex()) {
            table.addView(row(listOf(entry.number.toString()) + (0 until columns).map { entry.cells.getOrNull(it).orEmpty() }, widths, false, index))
            table.addView(View(activity).apply { setBackgroundColor(activity.getColor(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1)))
        }
        content.addView(HorizontalScrollView(activity).apply {
            addView(table, android.widget.FrameLayout.LayoutParams(-2, -2))
        }, LinearLayout.LayoutParams(-1, -2))
    }

    private fun row(values: List<String>, widths: List<Int>, header: Boolean, index: Int) = ui.line().apply {
        gravity = Gravity.TOP
        setBackgroundColor(activity.getColor(if (header || index % 2 != 0) R.color.page_bg else R.color.surface_bg))
        values.forEachIndexed { position, value ->
            addView(ui.text(value, 14f, bold = header, muted = position == 0).apply {
                setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8))
                minimumHeight = ui.dp(44)
                maxLines = 3
                ellipsize = TextUtils.TruncateAt.END
                if (!header && position > 0) {
                    typeface = Typeface.MONOSPACE
                    tag = "health-structured-cell-$index-${position - 1}"
                    if (value.isNotBlank()) setOnClickListener {
                        show(AlertDialog.Builder(activity).setTitle(R.string.health_structured_value)
                            .setMessage(value).setPositiveButton(android.R.string.ok, null).create())
                    }
                }
            }, LinearLayout.LayoutParams(ui.dp(if (position == 0) 62 else widths[position - 1]), -2))
        }
    }

    private fun show(dialog: AlertDialog) {
        subdialog?.dismiss()
        subdialog = dialog
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        dialog.setOnDismissListener { if (subdialog === dialog) subdialog = null }
        dialog.show()
    }
}
