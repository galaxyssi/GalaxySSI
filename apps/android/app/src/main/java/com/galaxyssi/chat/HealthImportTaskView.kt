package com.galaxyssi.chat

import android.content.Context
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/** Keep progress-only events from rebuilding the scroll container or moving its current anchor. */
internal class HealthImportTaskView(
    context: Context, private val ui: HealthCenterViews,
    private val cancel: (HealthImportJob) -> Unit, private val retry: (HealthImportJob) -> Unit,
    private val review: (HealthImportJob) -> Unit, private val original: (HealthImportJob) -> Unit,
    private val capture: (HealthImportJob) -> Unit = {}
) : LinearLayout(context) {
    private val name: TextView
    private val status: TextView
    private val progress: ProgressBar
    private val actions: LinearLayout
    private var actionKey = ""
    init {
        orientation = VERTICAL; setPadding(ui.dp(18), ui.dp(18), ui.dp(18), ui.dp(18))
        background = ui.background(stroke = context.getColor(R.color.separator))
        name = ui.text("", bold = true).apply { maxLines = 2 }; addView(name)
        status = ui.text("", 13f, muted = true); ui.add(this, status, 6)
        progress = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal)
        addView(progress, LayoutParams(-1, ui.dp(12)))
        actions = ui.column().apply { minimumHeight = ui.dp(144) }; addView(actions)
    }
    fun bind(job: HealthImportJob, description: String) {
        name.text = job.name.ifBlank { context.getString(R.string.health_import_preparing) }
        status.text = description
        val running = job.state in listOf(HealthImportState.QUEUED, HealthImportState.COPYING, HealthImportState.RECOGNIZING)
        progress.visibility = if (running) View.VISIBLE else View.INVISIBLE
        progress.isIndeterminate = !(job.state == HealthImportState.COPYING && job.totalBytes > 0)
        if (!progress.isIndeterminate) { progress.max = 100; progress.progress = (job.copiedBytes * 100 / job.totalBytes).coerceIn(0, 100).toInt() }
        val nextKey = "${job.state}|${job.nextPage > 0}|${job.originalId}"
        if (nextKey == actionKey) return
        actionKey = nextKey; actions.removeAllViews()
        if (running) actions.addView(ui.row(context.getString(R.string.common_cancel)) { cancel(job) })
        if (job.state in listOf(HealthImportState.CANCELLED, HealthImportState.FAILED)) actions.addView(ui.row(context.getString(R.string.common_retry)) { retry(job) })
        if (job.nextPage > 0) actions.addView(ui.row(context.getString(R.string.health_review_title)) { review(job) })
        if (job.state == HealthImportState.TABLE_REVIEW) actions.addView(ui.row(context.getString(R.string.health_table_title)) { review(job) })
        if (job.originalId.isNotBlank()) actions.addView(ui.row(context.getString(R.string.health_view_original)) { original(job) })
        if (job.captureBatch.isNotBlank()) actions.addView(ui.row(context.getString(if (job.captureSubmitted) R.string.health_photo_view_pages else R.string.health_photo_arrange)) { capture(job) })
    }
}
