package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.os.Handler
import android.os.Looper
import android.widget.ScrollView
import android.widget.Toast
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

/** A page is released on dismissal/background; no decrypted archive is retained by the UI. */
internal class HealthCareHistoryReview(private val activity: Activity, private val names: HealthOverviewDatabases) {
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var dialog: AlertDialog? = null
    fun clear() { generation++; dialog?.dismiss(); dialog = null }
    fun destroy() { clear(); worker.shutdown() }
    fun show(id: String, after: HealthPageCursor? = null, version: String? = null) {
        clear(); val token = generation
        worker.execute {
            val result = runCatching {
                HealthCareEngine.evaluate(activity.applicationContext, names)
                HealthPrivacyStore(activity, names.privacy).use { privacy ->
                    val permission = privacy.policy()
                    check(permission.metrics && permission.profile)
                    HealthCareStore(activity, names.care).use { care ->
                        val issue = care.concern(id) ?: throw HealthCareConflict()
                        if (version != null && version != issue.inputVersion) throw HealthCareConflict()
                        val settings = care.settings()
                        HealthRecordStore(activity, names.records).use { records ->
                            fun current() = issue.inputVersion == HealthCareEngine.inputVersion(settings.version, permission.version, records.metricVersion(issue.metric)) &&
                                privacy.policy() == permission && care.settings() == settings && care.concern(id)?.revision == issue.revision
                            if (!current()) throw HealthCareConflict()
                            val page = privacy.track(HealthAccessScope(HealthAccessPurpose.PROACTIVE_CARE, setOf(issue.metric))) {
                                records.careHistory(System.currentTimeMillis(), issue.metric, after)
                            }
                            if (!current()) throw HealthCareConflict()
                            issue to page
                        }
                    }
                }
            }
            main.post { if (token == generation && !activity.isFinishing && !activity.isDestroyed) result.fold({ render(it.first, it.second) }, {
                Toast.makeText(activity, R.string.health_care_changed, Toast.LENGTH_LONG).show()
            }) }
        }
    }
    private fun render(issue: HealthCareConcern, page: HealthRecordPage) {
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(16)); tag = "health-care-history-page" }
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        val current = issue.assessment.sample
        ui.add(content, ui.text(activity.getString(R.string.health_series_notice), 14f, muted = true), 8)
        ui.add(content, ui.text(activity.getString(if (page.next == null) R.string.health_series_end else R.string.health_series_earlier), 14f), 8)
        page.records.forEach { record ->
            val sample = HealthCareSample.of(record)
            val values = sample.metric.fields.filter { !sample.values[it].isNullOrBlank() }.joinToString(" / ") {
                "${sample.values[it]} ${sample.unitFor(it)}"
            }
            ui.add(content, ui.text(date.format(Date(sample.measuredAt)), 14f, muted = true), 18)
            ui.add(content, ui.text(values, 19f, bold = true).apply { tag = "health-series-value" }, 4)
            val old = issue.context?.takeIf { it.record == sample.record }
                ?: issue.assessment.comparison?.previousContext?.takeIf { it.record == sample.record }
            if (current != null && sample.record != current.record) {
                val gaps = HealthCareComparisonPolicy.gaps(sample, current, old, issue.context?.takeIf { it.record == current.record })
                ui.add(content, ui.text(gaps.joinToString("\n") { activity.getString(HealthCareComparisonPresentation.gapResource(it)) }, 13f, muted = true), 6)
            }
        }
        dialog = AlertDialog.Builder(activity).setTitle(R.string.health_series_title)
            .setView(ScrollView(activity).apply { addView(content) })
            .setPositiveButton(R.string.common_cancel, null)
            .apply { page.next?.let { cursor -> setNeutralButton(R.string.health_series_more) { _, _ -> show(issue.id, cursor, issue.inputVersion) } } }
            .create().also { d -> d.setOnDismissListener { content.removeAllViews(); if (dialog === d) dialog = null }; d.show() }
    }
}
