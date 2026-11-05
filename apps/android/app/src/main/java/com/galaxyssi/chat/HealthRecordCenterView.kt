package com.galaxyssi.chat

import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout

internal class HealthRecordCenterView(
    private val activity: HealthCenterActivity,
    private val names: HealthOverviewDatabases,
) {
    private val ui get() = activity.ui
    private fun label(id: Int) = activity.getString(id)
    private fun start(type: Class<*>, extras: Intent.() -> Unit = {}) {
        activity.startActivity(Intent(activity, type).putHealthNavigationFixture(names).apply(extras))
    }

    fun show(content: LinearLayout, loaded: () -> Unit) {
        content.addView(ui.text(label(R.string.health_record_center_heading), 23f, bold = true).apply { tag = "health-record-center" })
        ui.add(content, ui.text(label(R.string.health_capture_heading), 14f, muted = true), 4)
        val camera = tile(R.drawable.ic_agent_camera, Accent.ORANGE, R.string.health_record_center_photo,
            R.string.health_record_center_photo_note, "camera") {
            start(HealthCaptureActivity::class.java) {
                putExtra("health_capture_entry", HealthCaptureEntry.CAMERA.name)
                putExtra("health_capture_return_to_record_center", true)
            }
        }
        val manual = tile(R.drawable.ic_hub_compose, Accent.GREEN, R.string.health_record_center_manual,
            R.string.health_measurement_context, "manual") { activity.open("manual") }
        val upload = tile(R.drawable.ic_settings_upload, Accent.BLUE, R.string.health_record_center_upload,
            R.string.health_record_center_import_note, "import") { activity.open("import") }
        val sources = tile(R.drawable.ic_settings_devices, Accent.VIOLET, R.string.health_record_center_devices,
            R.string.health_record_center_sources_note, "sources") {
            start(HealthSourcesActivity::class.java) { names.fixture?.let { putExtra("health_sources_test_id", it) } }
        }
        val configuration = activity.resources.configuration
        val columns = if (configuration.screenWidthDp / configuration.fontScale.coerceAtLeast(1f) < 325f) 1 else 2
        listOf(camera, manual, upload, sources).chunked(columns).forEach { tiles ->
            ui.add(content, ui.line().apply {
                gravity = Gravity.TOP
                tiles.forEachIndexed { index, tile ->
                    addView(tile, LinearLayout.LayoutParams(0, -1, 1f).apply { if (index > 0) marginStart = ui.dp(8) })
                }
            }, 8)
        }

        ui.add(content, ui.text(label(R.string.health_record_center_review), 18f, bold = true), 20)
        val reviews = ui.column()
        ui.add(content, reviews, 4)
        ui.add(content, ui.row(label(R.string.health_import_tasks)) { start(HealthCaptureActivity::class.java) }
            .apply { tag = "health-record-center-tasks" })
        ui.add(content, ui.text(label(R.string.health_recent), 18f, bold = true), 16)
        val recent = ui.column()
        ui.add(content, recent, 4)
        ui.add(content, ui.row(label(R.string.health_records)) { activity.open("records") }
            .apply { tag = "health-record-center-all-records" })
        ui.add(content, ui.row(label(R.string.health_export_data_files)) { start(HealthDataFilesActivity::class.java) }
            .apply { tag = "health-record-center-data" }, 8)
        reviews.addView(ui.text(label(R.string.health_loading), 14f, muted = true))
        recent.addView(ui.text(label(R.string.health_loading), 14f, muted = true))
        activity.query({ records ->
            val now = System.currentTimeMillis()
            val pending = runCatching { HealthOverviewRepository.pendingReviews(activity.applicationContext, records, names, limit = 4) }
            val measurements = runCatching { records.recentSelf(now, limit = 5) }
            pending to measurements
        }) { (pending, measurements) ->
            reviews.removeAllViews()
            recent.removeAllViews()
            pending.onSuccess { items ->
                if (items.isEmpty()) reviews.addView(ui.text(label(R.string.health_record_center_no_review), 14f, muted = true)
                    .apply { tag = "health-record-center-no-review" })
                items.forEach { item -> ui.add(reviews, recordRow(R.drawable.ic_rich_file, Accent.ORANGE,
                    item.name.ifBlank { label(reviewLabel(item.kind)) },
                    "${label(reviewLabel(item.kind))} \u00b7 ${activity.date(item.time)}") {
                    when (item.kind) {
                        HealthOverviewReviewKind.OCR -> start(HealthCaptureActivity::class.java) { putExtra("health_job", item.jobId) }
                        HealthOverviewReviewKind.TABLE -> start(HealthTableActivity::class.java) { putExtra("health_table", item.jobId) }
                    }
                }.apply {
                    tag = "health-record-center-review-${item.jobId}"
                    val night = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
                    background = ui.background(if (night) activity.getColor(R.color.surface_bg) else 0xfffff5e5.toInt(),
                        stroke = if (night) activity.getColor(R.color.separator) else 0xffefd5a5.toInt(), radius = 8)
                }, 6) }
            }.onFailure { retry(reviews) }
            measurements.onSuccess { items ->
                if (items.isEmpty()) recent.addView(ui.text(label(R.string.health_no_records), 14f, muted = true)
                    .apply { tag = "health-record-center-no-records" })
                items.forEach { record ->
                    val report = record.draft.evidence != null
                    recent.addView(recordRow(if (report) R.drawable.ic_rich_file else R.drawable.ic_health_heart,
                        if (report) Accent.BLUE else Accent.GREEN,
                        "${label(record.draft.metric.titleResource())} \u00b7 ${healthDisplayValue(record.draft)}",
                        "${activity.date(record.draft.measuredAt)} \u00b7 ${label(healthRecordSourceResource(record.source))}") {
                        activity.open("detail", record.draft.metric, record.id)
                    }.apply { tag = "health-record-center-record-${record.id}" })
                }
            }.onFailure { retry(recent) }
            loaded()
        }
    }

    private fun retry(content: LinearLayout) {
        content.addView(ui.row(label(R.string.common_retry), label(R.string.health_storage_error)) {
            activity.open("record_center")
        })
    }

    private fun reviewLabel(kind: HealthOverviewReviewKind) = when (kind) {
        HealthOverviewReviewKind.OCR -> R.string.health_overview_ocr_review
        HealthOverviewReviewKind.TABLE -> R.string.health_overview_table_review
    }

    private fun recordRow(icon: Int, accent: Accent, title: String, subtitle: String, action: () -> Unit) = ui.line().apply {
        minimumHeight = ui.dp(66)
        isFocusable = true
        setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8))
        addView(glyph(icon, accent), LinearLayout.LayoutParams(ui.dp(36), ui.dp(36)).apply { marginEnd = ui.dp(10) })
        addView(ui.column().apply {
            addView(ui.text(title, 15f, bold = true))
            ui.add(this, ui.text(subtitle, 13f, muted = true), 2)
        }, LinearLayout.LayoutParams(0, -2, 1f))
        addView(ui.text("\u203a", 22f, muted = true))
        setOnClickListener { action() }
    }

    private fun tile(icon: Int, accent: Accent, title: Int, subtitle: Int, key: String, action: () -> Unit) =
        ui.column().apply {
            tag = "health-record-center-$key"
            isFocusable = true
            setPadding(ui.dp(12), ui.dp(12), ui.dp(12), ui.dp(12))
            background = ui.background(stroke = activity.getColor(R.color.separator), radius = 8)
            addView(glyph(icon, accent), LinearLayout.LayoutParams(ui.dp(36), ui.dp(36)))
            ui.add(this, ui.text(label(title), 16f, bold = true), 6)
            ui.add(this, ui.text(label(subtitle), 13f, muted = true), 4)
            setOnClickListener { action() }
        }

    private fun glyph(icon: Int, accent: Accent) = ImageView(activity).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(accent.color.toInt())
        background = ui.background(accent.tint.toInt(), radius = 8)
        setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private enum class Accent(val color: Long, val tint: Long) {
        ORANGE(0xffa85518, 0xfff8e7d8), GREEN(0xff167347, 0xffddf1e5),
        BLUE(0xff305bb2, 0xffe0edfa), VIOLET(0xff674698, 0xffece5fa)
    }
}
