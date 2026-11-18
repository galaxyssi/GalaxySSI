package com.galaxyssi.chat

import android.view.Gravity
import android.widget.LinearLayout
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date

internal class HealthOverviewRecordsView(private val activity: HealthCenterActivity, private val names: HealthOverviewDatabases, private val period: HealthMeasurementPeriod?,
    private val abnormal: Boolean, private val outsideIds: Set<String>, initialCursor: HealthPageCursor? = null,
    initialHistory: List<HealthPageCursor?> = emptyList()) {
    private val ui get() = activity.ui
    val root = ui.column().apply { tag = "health-overview-record-expansion" }
    @Volatile private var alive = true
    @Volatile private var request = 0
    private val previous = ArrayList(initialHistory)
    private var after = initialCursor
    val cursor get() = after
    val history get() = previous.toList()
    fun clear() { alive = false; request++; root.removeAllViews() }
    fun show() {
        root.removeAllViews()
        root.addView(ui.text(activity.getString(if (activity.measurementRecordsExpanded) R.string.health_period_collapse_records else R.string.health_period_expand_records), 14f).apply {
            tag = "health-overview-all-records"
            gravity = Gravity.CENTER; minimumHeight = ui.dp(56); isFocusable = true
            setTextColor(activity.getColor(R.color.health_overview_green))
            setOnClickListener { activity.measurementRecordsExpanded = !activity.measurementRecordsExpanded; request++; after = null; previous.clear(); show() }
        })
        if (activity.measurementRecordsExpanded) load()
    }
    private fun load() {
        while (root.childCount > 1) root.removeViewAt(1)
        ui.add(root, ui.text(activity.getString(R.string.health_loading), 13f, muted = true), 8)
        val token = ++request; val cursor = after
        activity.queryCancellable({ store, check ->
          fun read(): HealthRecordPage {
            val zone = ZoneId.systemDefault(); val now = System.currentTimeMillis()
            val from = period?.from(zone) ?: 0; val until = minOf(now + 1, period?.until(zone) ?: Long.MAX_VALUE)
            var position = cursor
            val visible = arrayListOf<HealthObservation>()
            var done = false
            while (!done && visible.size <= 30) {
                check(); if (!alive || token != request) throw java.util.concurrent.CancellationException()
                val page = store.measurementPage(from, until, position, check = check)
                for (row in page.records) {
                    position = HealthPageCursor(row.draft.measuredAt, row.id)
                    if (!abnormal || row.id in outsideIds || HealthOverviewRangePolicy.report(row)?.outside == true) visible += row
                    if (visible.size > 30) break
                }
                done = page.next == null || page.records.isEmpty()
            }
            return HealthRecordPage(visible.take(30), if (visible.size > 30) visible[29].let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
          }
          if (period == null && !abnormal) read() else HealthPrivacyStore.track(activity.applicationContext,
              HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMeasurementPeriods.metrics), names.privacy) { read() }
        }) { page ->
            if (!alive || token != request || !activity.measurementRecordsExpanded) return@queryCancellable
            while (root.childCount > 1) root.removeViewAt(1)
            val rows = ui.column().apply { tag = "health-overview-expanded-records" }
            root.addView(rows)
            page.records.forEach { row ->
                rows.addView(ui.row(activity.getString(row.draft.metric.titleResource()), healthDisplayValue(row.draft) + "\n" +
                    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(row.draft.measuredAt)) + " \u00b7 " +
                    activity.getString(healthContextResource(row.draft.condition))) { activity.open("detail", row.draft.metric, row.id) }.apply { tag = "health-expanded-record-${row.id}" })
            }
            if (page.records.isEmpty()) rows.addView(ui.text(activity.getString(R.string.health_no_records), 13f, muted = true))
            if (previous.isNotEmpty()) rows.addView(ui.row(activity.getString(R.string.health_previous_page)) {
                after = previous.removeAt(previous.lastIndex); load()
            })
            page.next?.let { next -> rows.addView(ui.row(activity.getString(R.string.health_next_page)) {
                previous += after; after = next; load()
            }.apply { tag = "health-expanded-next-page" }) }
        }
    }
}
