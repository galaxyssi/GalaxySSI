package com.galaxyssi.chat

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.os.CancellationSignal
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import java.io.OutputStream
import java.math.BigDecimal
import java.math.RoundingMode
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

internal class HealthWeeklyText(private val context: Context) {
    private fun text(id: Int, vararg args: Any) = context.getString(id, *args)
    fun range(scope: HealthWeeklyScope) = text(R.string.health_weekly_range, scope.first, scope.end, scope.zone.id)
    fun version(snapshot: HealthWeeklySnapshot): String {
        val scope = snapshot.scope
        val material = listOf(HealthWeeklySnapshot.METHOD_VERSION, scope.first, scope.end, scope.zone.id, scope.records, scope.comparison,
            snapshot.versions.entries.sortedBy { it.key.ordinal }.joinToString("|") { "${it.key.name}:${it.value}" }).joinToString("|")
        val hash = MessageDigest.getInstance("SHA-256").digest(material.toByteArray(Charsets.UTF_8)).take(8).joinToString("") { "%02x".format(it.toInt() and 255) }
        return text(R.string.health_weekly_version, HealthWeeklySnapshot.METHOD_VERSION, hash, date(snapshot.calculatedAt, scope.zone))
    }
    fun title(metric: HealthMetric) = context.getString(metric.titleResource())
    fun summary(stat: HealthWeeklyStat): String = when {
        stat.validDays == 0 -> text(R.string.health_weekly_no_values)
        stat.metric == HealthMetric.BLOOD_PRESSURE -> text(R.string.health_weekly_bp_count, stat.exactRecords)
        else -> {
            val unit = when (stat.metric) {
                HealthMetric.SLEEP_DURATION -> text(R.string.health_weekly_minutes)
                HealthMetric.STEPS -> text(R.string.health_weekly_steps)
                else -> stat.metric.units.first()
            }
            "${decimal(requireNotNull(stat.mean), if (stat.metric == HealthMetric.STEPS) 0 else 1)} $unit"
        }
    }
    fun coverage(stat: HealthWeeklyStat) = text(R.string.health_weekly_coverage, stat.validDays, 7, stat.recordedDays, stat.records)
    fun comparison(snapshot: HealthWeeklySnapshot): List<String> {
        val sleep = snapshot.sleep ?: return emptyList()
        val scope = snapshot.scope
        val counts = text(R.string.health_weekly_compare_coverage, sleep.current.validDays, sleep.baseline.validDays)
        val baselineRange = text(R.string.health_weekly_baseline_range, scope.baselineFirst, scope.baselineLast)
        val delta = sleep.deltaMinutes ?: return listOf(text(R.string.health_weekly_compare_insufficient), counts, baselineRange)
        val recent = decimal(requireNotNull(sleep.current.mean), 1)
        val baseline = decimal(requireNotNull(sleep.baseline.mean), 1)
        val difference = decimal(delta, 1).let { if (delta.signum() > 0 && it != "0") "+$it" else it }
        return listOf(text(R.string.health_weekly_compare, recent, baseline, difference), counts, baselineRange)
    }
    fun raw(record: HealthWeeklyRecord, zone: ZoneId): Pair<String, String> {
        val values = record.metric.fields.mapNotNull { field -> record.values[field]?.let { value ->
            val unit = if (record.metric == HealthMetric.BLOOD_PRESSURE && field == "pulse") "bpm" else record.unit
            "${context.getString(healthFieldResource(field))}: $value $unit".trimEnd()
        } }.joinToString("  \u00b7  ")
        return "${date(record.time, zone)}  \u00b7  ${title(record.metric)}  \u00b7  ${context.getString(healthRecordSourceResource(record.source))}" to values
    }
    fun rawVersion(record: HealthWeeklyRecord) = "${record.id} / r${record.revision}"
    private fun date(ms: Long, zone: ZoneId) = Instant.ofEpochMilli(ms).atZone(zone).format(DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm"))
    private fun decimal(value: BigDecimal, scale: Int) = value.setScale(scale, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
}

internal object HealthWeeklyPdf {
    fun write(context: Context, store: HealthRecordStore, snapshot: HealthWeeklySnapshot, output: OutputStream,
        signal: CancellationSignal? = null) = render(context, store, snapshot, signal) { it.writeTo(output) }

    fun render(context: Context, store: HealthRecordStore, snapshot: HealthWeeklySnapshot, signal: CancellationSignal? = null,
        save: (PdfDocument) -> Unit) {
        val text = HealthWeeklyText(context)
        val document = PdfDocument()
        val canvas = ReportPages(context, document)
        try {
            canvas.block(text.range(snapshot.scope), 17f, true)
            canvas.block(text.version(snapshot), 9f)
            snapshot.stats.forEach { stat ->
                signal?.throwIfCanceled()
                canvas.block("${text.title(stat.metric)}  \u00b7  ${text.summary(stat)}", 14f, true)
                canvas.block(text.coverage(stat), 10f)
            }
            text.comparison(snapshot).takeIf { it.isNotEmpty() }?.let { comparison ->
                canvas.block(context.getString(R.string.health_weekly_attention), 14f, true)
                comparison.forEach { canvas.block(it, 11f) }
            }
            canvas.block(context.getString(R.string.health_weekly_method), 10f)
            canvas.block(context.getString(R.string.health_weekly_exclusions), 10f)
            canvas.block(context.getString(R.string.health_not_diagnosis), 10f)
            if (snapshot.scope.records) {
                canvas.block(context.getString(R.string.health_weekly_raw), 14f, true)
                HealthWeeklyRepository.rawRecords(store, snapshot, signal) { record ->
                    val (heading, value) = text.raw(record, snapshot.scope.zone)
                    canvas.block("$heading\n$value\n${text.rawVersion(record)}", 9f)
                }
            }
            canvas.finish()
            signal?.throwIfCanceled()
            HealthWeeklyRepository.requireCurrent(store, snapshot.stamp)
            save(document)
        } finally {
            canvas.finish()
            document.close()
        }
    }

    private class ReportPages(private val context: Context, private val document: PdfDocument) {
        private var number = 0
        private var page: PdfDocument.Page? = null
        private var y = 0f
        private fun paint(size: Float, bold: Boolean = false) = TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(25, 37, 34); textSize = size
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
        }
        private fun start() {
            finish()
            val next = document.startPage(PdfDocument.PageInfo.Builder(595, 842, ++number).create())
            page = next
            next.canvas.drawColor(Color.WHITE)
            next.canvas.drawText(context.getString(R.string.health_weekly_title), 40f, 44f, paint(17f, true))
            next.canvas.drawLine(40f, 55f, 555f, 55f, paint(10f))
            next.canvas.drawText(number.toString(), 545f, 817f, paint(10f))
            y = 70f
        }
        fun block(text: String, size: Float, bold: Boolean = false) {
            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint(size, bold), 515)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(true).setLineSpacing(2f, 1f).build()
            check(layout.height <= 700) { "Report block is too tall" }
            if (page == null || y + layout.height > 780) start()
            val canvas = requireNotNull(page).canvas
            canvas.save()
            canvas.translate(40f, y)
            layout.draw(canvas)
            canvas.restore()
            y += layout.height + 7
        }
        fun finish() { page?.let(document::finishPage); page = null }
    }
}
