package com.galaxyssi.chat

import com.univocity.parsers.csv.CsvWriter
import com.univocity.parsers.csv.CsvWriterSettings
import java.io.OutputStream
import java.io.OutputStreamWriter
import java.time.Instant
import org.dhatim.fastexcel.Workbook

/** Long-form component rows share observation identity; components are never independent measurements. */
internal object HealthRecordExportRows {
    val headers = listOf("schema_version", "observation_id", "revision", "profile_id", "metric", "component", "result_kind", "reported_value",
        "canonical_value", "exact_number", "comparison", "upper_bound", "component_unit", "observation_unit", "measured_at_utc", "measured_at_epoch_ms",
        "received_at_utc", "source", "condition", "side", "original_id", "original_sha256", "source_page", "table_row", "table_sheet",
        "source_status_at_preview", "report_reference", "note", "source_text", "csv_tab_escaped_fields")
    fun count(record: HealthObservation) = record.draft.metric.fields.count { !record.draft.values[it].isNullOrBlank() }
    fun rows(item: HealthRecordExportItem): Sequence<List<String>> = sequence {
        val record = item.record; val d = record.draft; val e = d.evidence
        d.metric.fields.forEach { field ->
            val raw = d.values[field].orEmpty(); if (raw.isBlank()) return@forEach
            val result = requireNotNull(HealthResult.parse(raw, d.metric.form))
            yield(listOf("1", record.id, record.revision.toString(), record.profileId, d.metric.name, field, result.kind.name,
                d.reportedValues[field] ?: raw, result.canonical, result.exactNumber?.toPlainString().orEmpty(), result.operator, result.upper,
                d.unitFor(field), d.unit, Instant.ofEpochMilli(d.measuredAt).toString(), d.measuredAt.toString(), Instant.ofEpochMilli(record.receivedAt).toString(),
                record.source, d.condition, d.side, e?.originalId.orEmpty(), e?.sha256.orEmpty(), e?.page?.toString().orEmpty(),
                e?.tableRow?.takeIf { it > 0 }?.toString().orEmpty(), e?.tableSheet.orEmpty(), item.sourceStatus.name, d.reference, d.note, e?.rawText.orEmpty(), ""))
        }
    }
    fun csv(row: List<String>): List<String> {
        require(row.size == headers.size)
        val escaped = arrayListOf<String>()
        val values = row.dropLast(1).mapIndexed { index, value -> HealthCsvCellSafety.encoded(value).also { if (it.second) escaped += headers[index] }.first }
        return values + escaped.joinToString(";")
    }
}

internal interface HealthRecordExportSink : java.io.Closeable { fun append(item: HealthRecordExportItem) }
internal object HealthRecordExportFormats {
    fun open(session: HealthRecordExportSession, output: OutputStream, sheetRows: Int = 1_048_576): HealthRecordExportSink = when (session.scope.format) {
        HealthRecordExportFormat.CSV -> Csv(output)
        HealthRecordExportFormat.JSON -> Json(session, output)
        HealthRecordExportFormat.XLSX -> Xlsx(session, output, sheetRows)
    }
    private class Csv(output: OutputStream) : HealthRecordExportSink {
        private val writer = CsvWriter(OutputStreamWriter(HealthPrivateExportFile.borrowed(output), Charsets.UTF_8).apply { write('\uFEFF'.code) },
            CsvWriterSettings().apply {
                setQuoteAllFields(true); setIgnoreLeadingWhitespaces(false); setIgnoreTrailingWhitespaces(false)
                setNormalizeLineEndingsWithinQuotes(false); format.setLineSeparator("\r\n")
            })
        init { writer.writeHeaders(*HealthRecordExportRows.headers.toTypedArray()) }
        override fun append(item: HealthRecordExportItem) { HealthRecordExportRows.rows(item).forEach { writer.writeRow(*HealthRecordExportRows.csv(it).toTypedArray()) } }
        override fun close() = writer.close()
    }
    private class Json(private val session: HealthRecordExportSession, output: OutputStream) : HealthRecordExportSink {
        private val writer = OutputStreamWriter(HealthPrivateExportFile.borrowed(output), Charsets.UTF_8)
        private var count = 0L
        init {
            writer.write("{\"format\":\"galaxyssi-health-records\",\"version\":1,\"scope\":${session.scope.json()},\"prepared_at\":${session.preparedAt},\"confirmed_at\":${session.confirmedAt},\"contains_original_files\":false,\"records\":[")
        }
        override fun append(item: HealthRecordExportItem) {
            if (count > 0) writer.write(",")
            val value = item.record.json(includeDeviceGroup = false).put("source_status_at_preview", item.sourceStatus.name)
            writer.write(value.toString()); count++
        }
        override fun close() {
            writer.write("],\"observation_count\":$count}"); writer.close()
        }
    }
    private class Xlsx(session: HealthRecordExportSession, output: OutputStream, private val limit: Int) : HealthRecordExportSink {
        private val book = Workbook(HealthPrivateExportFile.borrowed(output), "GalaxySSI", "1.0000")
        private var sheet: org.dhatim.fastexcel.Worksheet
        private var number = 0; private var row = 1; private var buffered = 0
        init {
            require(limit in 2..1_048_576)
            book.newWorksheet("Metadata").apply {
                val fields = listOf("format" to "galaxyssi-health-records-v1", "confirmed_at" to Instant.ofEpochMilli(session.confirmedAt).toString(),
                    "prepared_at" to Instant.ofEpochMilli(session.preparedAt).toString(),
                    "observations" to session.count.toString(), "component_rows" to session.rows.toString(), "scope" to session.scope.json().toString(),
                    "contains_original_files" to "false", "numbers" to "Exact notation stored as text", "components" to "Rows with the same observation_id belong to one measurement")
                fields.forEachIndexed { index, pair -> inlineString(index, 0, pair.first); inlineString(index, 1, pair.second) }; finish()
            }
            sheet = next()
        }
        private fun next(): org.dhatim.fastexcel.Worksheet = book.newWorksheet("Records ${++number}").apply {
            HealthRecordExportRows.headers.forEachIndexed { col, label -> inlineString(0, col, label) }; freezePane(1, 1); row = 1
        }
        override fun append(item: HealthRecordExportItem) {
            HealthRecordExportRows.rows(item).forEach { values ->
                if (row >= limit) { sheet.finish(); sheet = next(); buffered = 0 }
                values.forEachIndexed { col, value -> require(value.length <= 32_767) { "XLSX cell limit exceeded" }; sheet.inlineString(row, col, value) }
                row++
            }
            if (++buffered >= 30) { sheet.flush(); buffered = 0 }
        }
        override fun close() { sheet.finish(); book.close() }
    }
}
