package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.util.TypedValue
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.math.RoundingMode

internal class HealthOverviewView(private val activity: HealthCenterActivity, private val names: HealthOverviewDatabases) {
    private val ui get() = activity.ui
    private val prefs get() = activity.getSharedPreferences(names.prefs, android.content.Context.MODE_PRIVATE)
    private fun label(id: Int, vararg args: Any) = activity.getString(id, *args)
    private fun color(id: Int) = activity.getColor(id)
    private fun start(type: Class<*>, extras: Intent.() -> Unit = {}) {
        if (names.fixture == null) activity.startActivity(Intent(activity, type).apply(extras))
    }

    fun show(content: LinearLayout, snapshot: HealthOverviewSnapshot) {
        content.removeAllViews()
        val heading = ui.line().apply {
            addView(ui.text(label(R.string.health_overview_title), 23f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_chat_shortcut_list, R.string.health_overview_sort) { chooseOrder(content, snapshot) })
        }
        content.addView(heading)
        if (snapshot.hasRecords || snapshot.attention.isNotEmpty() || snapshot.reviewUnavailable || !snapshot.derived.permitted) {
            val section = ui.column().apply { tag = "health-overview-attention" }
            val order = runCatching { HealthOverviewOrder.valueOf(prefs.getString("order", "")!!) }.getOrDefault(HealthOverviewOrder.CHANGES_FIRST)
            val ordered = HealthOverviewPolicy.sort(snapshot.attention, order)
            section.addView(ui.text(label(R.string.health_overview_attention), 18f, bold = true))
            if (ordered.isEmpty()) ui.add(section, ui.text(label(if (snapshot.reviewUnavailable || snapshot.derived.unavailable)
                R.string.health_overview_partial else R.string.health_overview_no_attention), 14f, muted = true), 8)
            ordered.forEach { ui.add(section, attention(it), 8) }
            if (!snapshot.derived.permitted) ui.add(section, ui.profileRow(label(R.string.health_overview_permission)) {
                if (names.fixture == null) activity.startActivity(activity.healthPrivacyIntent())
            }.apply { tag = "health-overview-privacy-blocked" }, 4)
            if (ordered.isNotEmpty() && (snapshot.reviewUnavailable || snapshot.derived.unavailable))
                ui.add(section, ui.text(label(R.string.health_overview_partial), 13f, muted = true), 6)
            ui.add(content, section, 12)
        }
        val newest = snapshot.metrics.mapNotNull { it.record?.draft?.measuredAt }.maxOrNull()
        val recent = snapshot.metrics.count { it.freshness == HealthOverviewFreshness.RECENT }
        if (snapshot.hasRecords) {
            ui.add(content, ui.text(label(R.string.health_overview_coverage, recent, snapshot.metrics.size), 13f, muted = true), 12)
            newest?.let { ui.add(content, ui.text(label(R.string.health_overview_latest, activity.date(it)), 12f, muted = true), 4) }
        } else {
            ui.add(content, ui.text(label(R.string.health_first_title), 19f, bold = true).apply { tag = "health-overview-first" }, 14)
            ui.add(content, ui.text(label(R.string.health_first_description), 14f, muted = true), 6)
        }
        ui.add(content, quicks(), 16)
        ui.add(content, ui.profileRow(label(R.string.health_key_metrics), label(R.string.health_catalog_title)) {
            start(HealthCatalogActivity::class.java)
        }, 12)
        snapshot.metrics.take(4).chunked(2).forEach { pair ->
            val line = ui.line().apply { gravity = Gravity.TOP }
            pair.forEachIndexed { i, metric -> line.addView(card(metric, snapshot), LinearLayout.LayoutParams(0, -1, 1f).apply {
                if (i == 0) marginEnd = ui.dp(4) else marginStart = ui.dp(4)
            }) }
            ui.add(content, line, 8)
        }
        val extras = snapshot.metrics.drop(4)
        extras.filter { it.record != null }.forEach { item ->
            val record = requireNotNull(item.record)
            ui.add(content, ui.profileRow("${label(item.metric.titleResource())} \u00b7 ${healthDisplayValue(record.draft)}",
                "${label(freshness(item.freshness))} \u00b7 ${source(record)}") { openRecord(record) }
                .apply { tag = "health-overview-extra-${item.metric.name}" }, 4)
        }
        val missing = extras.filter { it.freshness == HealthOverviewFreshness.MISSING }
        if (missing.isNotEmpty()) ui.add(content, ui.text(label(R.string.health_overview_missing_metrics,
            missing.joinToString(", ") { label(it.metric.titleResource()) }), 14f, muted = true).apply { tag = "health-overview-missing" }, 12)
        ui.add(content, ui.text(label(R.string.health_overview_no_data_warning), 13f, muted = true), 6)
        ui.add(content, ui.profileRow(label(R.string.health_weekly_title)) { start(HealthWeeklyActivity::class.java) }, 12)
        ui.add(content, ui.profileRow(label(R.string.health_assistant_title)) { start(HealthAssistantActivity::class.java) })
        ui.add(content, ui.profileRow(label(R.string.health_export_data_files)) { start(HealthDataFilesActivity::class.java) })
        if (!snapshot.hasRecords) {
            ui.add(content, ui.profileRow(label(R.string.health_profile_title)) { start(HealthProfileActivity::class.java) })
            ui.add(content, ui.profileRow(label(R.string.health_privacy_title)) {
                if (names.fixture == null) activity.startActivity(activity.healthPrivacyIntent())
            })
        }
    }

    private fun attention(item: HealthOverviewAttention) = when (item) {
        is HealthOverviewAttention.Change -> ui.profileRow(label(R.string.health_sleep_alert_title),
            label(R.string.health_sleep_alert_decrease, minutes(item.alert.evidence.decrease))) {
            start(HealthReminderActivity::class.java) { putExtra("health_sleep_alert_id", item.alert.id) }
        }.apply { tag = "health-overview-change" }
        is HealthOverviewAttention.Review -> ui.profileRow(label(if (item.kind == HealthOverviewReviewKind.OCR)
            R.string.health_overview_ocr_review else R.string.health_overview_table_review), activity.date(item.time)) {
            if (item.kind == HealthOverviewReviewKind.OCR) start(HealthCaptureActivity::class.java) { putExtra("health_job", item.jobId) }
            else start(HealthTableActivity::class.java) { putExtra("health_table", item.jobId) }
        }.apply { tag = "health-overview-review-${item.kind.name}" }
    }
    private fun chooseOrder(content: LinearLayout, snapshot: HealthOverviewSnapshot) {
        val options = HealthOverviewOrder.entries
        val current = options.indexOfFirst { it.name == prefs.getString("order", null) }.coerceAtLeast(0)
        activity.showHealthDialog(AlertDialog.Builder(activity).setTitle(R.string.health_overview_sort)
            .setSingleChoiceItems(options.map { label(orderLabel(it)) }.toTypedArray(), current) { dialog, index ->
                prefs.edit().putString("order", options[index].name).apply()
                dialog.dismiss(); show(content, snapshot)
            }.setNegativeButton(android.R.string.cancel, null).create())
    }
    private fun orderLabel(order: HealthOverviewOrder) = when (order) {
        HealthOverviewOrder.CHANGES_FIRST -> R.string.health_overview_order_changes
        HealthOverviewOrder.REVIEW_FIRST -> R.string.health_overview_order_review
        HealthOverviewOrder.MOST_RECENT -> R.string.health_overview_order_recent
    }
    private fun quicks() = ui.line().apply {
        fun item(icon: Int, title: Int, key: String, action: () -> Unit) {
            addView(ui.column().apply {
                tag = key; gravity = Gravity.CENTER; minimumHeight = ui.dp(72); isFocusable = true
                setPadding(ui.dp(4), ui.dp(6), ui.dp(4), ui.dp(6))
                background = ui.background(stroke = color(R.color.separator), radius = 8)
                addView(ImageView(activity).apply {
                    setImageResource(icon); imageTintList = ColorStateList.valueOf(color(R.color.text_primary))
                    importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)))
                ui.add(this, ui.text(label(title), 13f, bold = true).apply { gravity = Gravity.CENTER }, 5)
                setOnClickListener { action() }
            }, LinearLayout.LayoutParams(0, -1, 1f).apply { marginEnd = ui.dp(if (childCount < 3) 4 else 0) })
        }
        item(R.drawable.ic_agent_camera, R.string.health_overview_photo, "health-overview-photo") { start(HealthCaptureActivity::class.java) }
        item(R.drawable.ic_health_heart, R.string.health_manual, "health-overview-manual") { activity.open("manual") }
        item(R.drawable.ic_chat_shortcut_file, R.string.health_overview_import, "health-overview-import") {
            start(HealthCaptureActivity::class.java) { putExtra("health_pick_files", true) }
        }
        item(R.drawable.ic_protocol_link, R.string.health_sources_quick, "health-overview-sources") { start(HealthSourcesActivity::class.java) }
    }
    private fun card(item: HealthOverviewMetric, snapshot: HealthOverviewSnapshot): LinearLayout {
        val weekly = snapshot.derived.sleep?.takeIf { item.metric == HealthMetric.SLEEP_DURATION && it.mean != null }
        val value = weekly?.mean?.let { label(R.string.health_overview_sleep_mean, minutes(it)) }
            ?: item.record?.let { healthDisplayValue(it.draft) } ?: label(R.string.health_overview_unrecorded)
        return ui.column().apply {
            tag = "health-overview-${item.metric.name}-${item.freshness.name}"
            background = ui.background(stroke = color(R.color.separator), radius = 8)
            setPadding(ui.dp(12), ui.dp(10), ui.dp(12), ui.dp(10)); minimumHeight = ui.dp(132); isFocusable = true
            addView(ui.text(label(item.metric.titleResource()), 14f, muted = true, bold = true))
            ui.add(this, ui.text(value, 20f, bold = true).apply {
                maxLines = 2
                setAutoSizeTextTypeUniformWithConfiguration(12, 20, 1, TypedValue.COMPLEX_UNIT_SP)
            }, 4)
            if (weekly != null || item.record != null) ui.add(this, ui.text(if (weekly != null)
                label(R.string.health_overview_sleep_days, weekly.validDays) else label(freshness(item.freshness)), 12f, muted = true), 6)
            item.record?.let {
                val caption = if (weekly != null) label(R.string.health_overview_latest, source(it)) else source(it)
                ui.add(this, ui.text(caption, 12f, muted = true), 4)
            }
            setOnClickListener {
                when {
                    weekly != null -> start(HealthWeeklyActivity::class.java)
                    item.record != null -> openRecord(item.record)
                    else -> activity.open("manual", item.metric)
                }
            }
        }
    }
    private fun freshness(value: HealthOverviewFreshness) = when (value) {
        HealthOverviewFreshness.RECENT -> R.string.health_overview_recent
        HealthOverviewFreshness.STALE -> R.string.health_overview_stale
        HealthOverviewFreshness.MISSING -> R.string.health_overview_unrecorded
    }
    private fun minutes(value: java.math.BigDecimal) = value.setScale(1, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
    private fun source(record: HealthObservation) =
        label(R.string.health_overview_source, activity.date(record.draft.measuredAt), label(healthRecordSourceResource(record.source)))
    private fun openRecord(record: HealthObservation) = start(HealthRecordRevisionActivity::class.java) {
        putExtra("health_record", record.id); putExtra("health_revision", record.revision)
    }
}
