package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import java.text.NumberFormat

internal class HealthReportImportView(private val activity: Activity, private val ui: HealthCenterViews) {
    private fun label(id: Int, vararg args: Any) = activity.getString(id, *args)
    private fun color(id: Int) = activity.getColor(id)

    private fun divider(content: LinearLayout, top: Int = 0) {
        content.addView(View(activity).apply { setBackgroundColor(color(R.color.separator)) },
            LinearLayout.LayoutParams(-1, ui.dp(1)).apply { topMargin = ui.dp(top) })
    }
    private fun badge(icon: Int, tint: Int, round: Boolean) = ImageView(activity).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(tint)
        background = ui.background(color(R.color.button_soft), radius = if (round) 20 else 8)
        setPadding(ui.dp(10), ui.dp(10), ui.dp(10), ui.dp(10))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        layoutParams = LinearLayout.LayoutParams(ui.dp(40), ui.dp(40)).apply { marginEnd = ui.dp(12) }
    }
    private fun file(content: LinearLayout, name: String, bytes: Int) {
        ui.add(content, ui.line().apply {
            addView(badge(R.drawable.ic_chat_shortcut_file, color(R.color.composer_send_icon), false))
            addView(ui.column().apply {
                addView(ui.text(name.ifBlank { label(R.string.health_report_import_title) }, 16f, bold = true))
                val size = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }.format(bytes / 1000.0)
                addView(ui.text(if (bytes > 0) label(R.string.health_report_payload_size, size)
                    else label(R.string.health_report_provider), 13f, muted = true))
            }, LinearLayout.LayoutParams(0, -2, 1f))
        })
        divider(content, 15)
    }
    private fun summary(content: LinearLayout, icon: Int, title: String, description: String, failed: Boolean = false) {
        ui.add(content, ui.line().apply {
            addView(badge(icon, color(if (failed) R.color.unread_red else R.color.composer_send_icon), true))
            addView(ui.column().apply {
                addView(ui.text(title, 22f, bold = true).apply {
                    tag = "health-report-import-summary"; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
                })
                addView(ui.text(description, 14f, muted = true))
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }, 18)
    }
    private fun command(content: LinearLayout, labelId: Int, tagName: String, action: () -> Unit) {
        content.addView(ui.command(labelId, action).apply {
            tag = tagName
            setPadding(ui.dp(14), 0, ui.dp(14), 0)
            background = ui.background(color(R.color.composer_send_icon), radius = 8)
            setTextColor(android.graphics.Color.WHITE)
        }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = ui.dp(16) })
    }
    fun progress(content: LinearLayout, state: HealthReportImportScreen, retry: () -> Unit) {
        file(content, state.name, state.bytes)
        if (state.failure != null) {
            summary(content, R.drawable.ic_agent_progress_close, label(R.string.health_report_not_imported), label(state.failure), failed = true)
            command(content, if (state.legacy) R.string.common_retry else R.string.health_vision_continue, "health-report-import-retry", retry)
            return
        }
        val active = when (state.stage) {
            HealthReportImportStage.COMPRESSING -> R.string.health_report_compressing
            HealthReportImportStage.SENDING -> R.string.health_report_recognizing
            HealthReportImportStage.SAVING -> R.string.health_report_saving
        }
        ui.add(content, ui.line().apply {
            addView(ProgressBar(activity).apply { isIndeterminate = true },
                LinearLayout.LayoutParams(ui.dp(22), ui.dp(22)).apply { marginEnd = ui.dp(12) })
            addView(ui.text(label(active), 18f, bold = true).apply {
                tag = "health-report-import-stage"; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }, 18)
        val stages = listOf(R.string.health_report_compress_stage, R.string.health_report_model_stage, R.string.health_report_save_stage)
        stages.forEachIndexed { i, stage ->
            if (!state.legacy || i == 2) line(content, label(stage), label(when {
                i < state.stage.ordinal -> R.string.health_report_stage_done
                i == state.stage.ordinal -> R.string.health_report_stage_active
                else -> R.string.health_report_stage_wait
            }), bold = i == state.stage.ordinal)
        }
    }
    private fun line(content: LinearLayout, name: String, value: String, bold: Boolean) {
        ui.add(content, ui.line().apply {
            minimumHeight = ui.dp(44)
            addView(ui.text(name, 14f), LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = ui.dp(8) })
            addView(ui.text(value, 14f, bold = bold, muted = !bold).apply { gravity = Gravity.END },
                LinearLayout.LayoutParams(0, -2, 1f))
        }, 4)
        divider(content)
    }
    fun result(content: LinearLayout, name: String, outcome: HealthReportImportOutcome, records: List<HealthObservation>,
        deferred: List<Pair<HealthVisionRow, HealthReportDeferred>>, rejected: Map<HealthReportRowIssue, Int>,
        openRecords: () -> Unit) {
        file(content, name, outcome.imageBytes)
        val imported = outcome.saved > 0
        val matched = outcome.duplicates > 0
        val incomplete = outcome.partial || outcome.skipped > 0
        summary(content, when {
            incomplete -> R.drawable.ic_agent_attach
            imported || matched -> R.drawable.ic_attention_check
            else -> R.drawable.ic_agent_progress_close
        }, when {
            imported -> label(R.string.health_report_import_count, outcome.saved)
            matched -> label(R.string.health_report_existing)
            deferred.isNotEmpty() -> label(R.string.health_report_recognized_only, deferred.size)
            else -> label(R.string.health_report_not_imported)
        }, when {
            imported -> label(R.string.health_report_saved_note)
            matched -> label(R.string.health_report_existing_note, outcome.duplicates)
            deferred.isNotEmpty() -> label(R.string.health_report_recognized_note)
            else -> label(R.string.health_report_no_usable_fields)
        }, failed = !imported && !matched && deferred.isEmpty())
        records.forEach { line(content, label(it.draft.metric.titleResource()), healthDisplayValue(it.draft), bold = true) }
        if (deferred.isNotEmpty()) {
            if (imported || matched) ui.add(content, ui.text(label(R.string.health_report_recognized_note), 14f, bold = true), 14)
            deferred.forEach { (row, reason) ->
                val value = row.metric.fields.mapNotNull(row.values::get).joinToString(" / ")
                line(content, label(row.metric.titleResource()), listOf(value, row.unit).filter(String::isNotBlank).joinToString(" "), bold = false)
                ui.add(content, ui.text(label(when (reason) {
                    HealthReportDeferred.SAMPLE_TIME -> R.string.health_report_reason_time
                    HealthReportDeferred.UNIT -> R.string.health_report_reason_unit
                    HealthReportDeferred.CONFLICT -> R.string.health_report_reason_conflict
                    HealthReportDeferred.INVALID -> R.string.health_report_reason_invalid
                }), 13f, muted = true), 4)
            }
        }
        val unclassified = (outcome.skipped - deferred.size).coerceAtLeast(0)
        if (unclassified > 0) ui.add(content,
            ui.text(label(R.string.health_report_skipped_note, unclassified), 13f, muted = true), 12)
        if (outcome.partial && rejected.isEmpty()) ui.add(content, ui.text(label(R.string.health_report_partial_note), 13f, muted = true), 8)
        rejected.forEach { (issue, count) ->
            ui.add(content, ui.text(label(when (issue) {
                HealthReportRowIssue.UNSUPPORTED_METRIC -> R.string.health_vision_rejected_metric
                HealthReportRowIssue.INVALID_UNIT -> R.string.health_vision_rejected_unit
                HealthReportRowIssue.INVALID_FIELDS -> R.string.health_vision_rejected_fields
                HealthReportRowIssue.DUPLICATE -> R.string.health_vision_rejected_duplicate
            }, count), 13f, muted = true), 8)
        }
        if (imported && matched) ui.add(content, ui.text(label(R.string.health_report_existing_note, outcome.duplicates), 13f, muted = true), 8)
        if (records.isNotEmpty()) command(content, R.string.health_report_open_records, "health-report-open-records", openRecords)
    }
}
