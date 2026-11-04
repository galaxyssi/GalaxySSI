package com.galaxyssi.chat

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.time.temporal.ChronoField
import java.util.Locale
import org.json.JSONObject

internal enum class HealthTableState { READING, SHEET_SELECTION, MAPPING, VALIDATING, READY, SAVING, SAVED, UNDOING, UNDONE, FAILED }
internal val HealthTableState.working: Boolean get() = this in listOf(HealthTableState.READING, HealthTableState.VALIDATING, HealthTableState.SAVING, HealthTableState.UNDOING)
internal enum class HealthTableRowState { PENDING, VALID, DUPLICATE, MISSING, INVALID, SAVED, UNDONE, EDITED }
internal enum class HealthTableDate(val pattern: String) {
    ISO("ISO 8601"), YMD("uuuu-MM-dd HH:mm"), YMD_SECONDS("uuuu-MM-dd HH:mm:ss"),
    SLASH_YMD("uuuu/MM/dd HH:mm"), DMY("dd/MM/uuuu HH:mm"), MDY("MM/dd/uuuu HH:mm"), EXCEL("Excel")
}
internal data class HealthTableMapping(
    val metric: HealthMetric = HealthMetric.BLOOD_PRESSURE,
    val columns: Map<String, String> = emptyMap(), val timeColumn: String = "", val unitColumn: String = "",
    val unit: String = "", val noteColumn: String = "", val date: HealthTableDate = HealthTableDate.ISO,
    val zone: String = ZoneId.systemDefault().id, val allowFormulaCache: Boolean = false, val dateOnlyTime: String = "", val referenceColumn: String = ""
) {
    fun json() = JSONObject().put("metric", metric.name).put("columns", JSONObject(columns)).put("time", timeColumn)
        .put("unit_column", unitColumn).put("unit", unit).put("note", noteColumn).put("date", date.name).put("zone", zone)
        .put("formula_cache", allowFormulaCache).put("date_only_time", dateOnlyTime)
        .put("reference_column", referenceColumn)
    fun valid(headers: List<String>): Boolean = timeColumn in headers && metric.requiredFields.all { columns[it] in headers } &&
        columns.keys.all { it in metric.fields } && columns.values.filter(String::isNotBlank).let { it.size == it.distinct().size } &&
        (unitColumn in headers || unitColumn.isBlank() && unit in metric.selectableUnits) &&
        (noteColumn.isBlank() || noteColumn in headers) && (referenceColumn.isBlank() || referenceColumn in headers) && runCatching { ZoneId.of(zone) }.isSuccess
    companion object {
        fun from(j: JSONObject) = HealthTableMapping(HealthMetric.valueOf(j.getString("metric")), j.getJSONObject("columns").let { c ->
            c.keys().asSequence().associateWith(c::getString)
        }, j.getString("time"), j.getString("unit_column"), j.getString("unit"), j.getString("note"),
            HealthTableDate.valueOf(j.getString("date")), j.getString("zone"), j.optBoolean("formula_cache"), j.optString("date_only_time"), j.optString("reference_column"))
    }
}
internal data class HealthTableRow(val number: Long, val cells: Map<String, String>, val issue: String = "", val sourceRow: Long = number,
    val formulas: Map<String, String> = emptyMap(), val numbers: Map<String, String> = emptyMap(),
    val excelDates: Map<String, String> = emptyMap(), val errors: Set<String> = emptySet(), val addresses: Map<String, String> = emptyMap()) {
    fun json() = JSONObject().put("number", number).put("cells", JSONObject(cells)).put("issue", issue).put("source_row", sourceRow)
        .put("formulas", JSONObject(formulas)).put("numbers", JSONObject(numbers)).put("excel_dates", JSONObject(excelDates))
        .put("errors", org.json.JSONArray(errors.toList())).put("addresses", JSONObject(addresses))
    companion object {
        fun from(j: JSONObject) = HealthTableRow(j.getLong("number"), j.getJSONObject("cells").let { c ->
            c.keys().asSequence().associateWith(c::getString)
        }, j.getString("issue"), j.optLong("source_row", j.getLong("number")), strings(j, "formulas"), strings(j, "numbers"), strings(j, "excel_dates"),
            j.optJSONArray("errors")?.let { a -> (0 until a.length()).map(a::getString).toSet() }.orEmpty(), strings(j, "addresses"))
        private fun strings(j: JSONObject, key: String): Map<String, String> = j.optJSONObject(key)?.let { c -> c.keys().asSequence().associateWith(c::getString) }.orEmpty()
    }
}
internal data class HealthXlsxSheet(val index: Int, val name: String, val visibility: String) {
    fun json() = JSONObject().put("index", index).put("name", name).put("visibility", visibility)
    companion object { fun from(j: JSONObject) = HealthXlsxSheet(j.getInt("index"), j.getString("name"), j.getString("visibility")) }
}
internal data class HealthTableBatch(
    val id: String, val originalId: String, val sha256: String, val name: String, val format: String,
    val headers: List<String> = emptyList(), val rows: Long = 0, val cursor: Long = 0,
    val state: HealthTableState = HealthTableState.READING, val mapping: HealthTableMapping = HealthTableMapping(),
    val mappingRevision: Int = 0, val error: String = "", val sheets: List<HealthXlsxSheet> = emptyList(),
    val sheetIndex: Int = -1, val headerRow: Int = 1, val date1904: Boolean = false
) {
    fun json() = JSONObject().put("id", id).put("original", originalId).put("sha256", sha256).put("name", name).put("format", format)
        .put("headers", org.json.JSONArray(headers)).put("rows", rows).put("cursor", cursor).put("state", state.name)
        .put("mapping", mapping.json()).put("revision", mappingRevision).put("error", error)
        .put("sheets", org.json.JSONArray(sheets.map { it.json() })).put("sheet_index", sheetIndex).put("header_row", headerRow).put("date_1904", date1904)
    companion object {
        fun from(j: JSONObject) = HealthTableBatch(j.getString("id"), j.getString("original"), j.getString("sha256"), j.getString("name"),
            j.getString("format"), j.getJSONArray("headers").let { a -> (0 until a.length()).map(a::getString) }, j.getLong("rows"),
            j.getLong("cursor"), HealthTableState.valueOf(j.getString("state")), HealthTableMapping.from(j.getJSONObject("mapping")),
            j.getInt("revision"), j.getString("error"), j.optJSONArray("sheets")?.let { a -> (0 until a.length()).map { HealthXlsxSheet.from(a.getJSONObject(it)) } }.orEmpty(),
            j.optInt("sheet_index", -1), j.optInt("header_row", 1), j.optBoolean("date_1904"))
    }
}
internal data class HealthTablePreview(val row: HealthTableRow, val state: HealthTableRowState, val issue: String, val recordId: String = "")
internal data class HealthTableCounts(val states: Map<HealthTableRowState, Long>) {
    operator fun get(state: HealthTableRowState): Long = states[state] ?: 0L
}
internal data class HealthTableEvaluation(val draft: HealthDraft?, val state: HealthTableRowState, val issue: String)

internal object HealthTablePolicy {
    private fun name(value: String) = value.trim().lowercase(Locale.ROOT).replace(Regex("[\\s_()\\[\\]-]"), "")
    private val aliases = mapOf(
        "systolic" to listOf("systolic", "sbp", "\u9ad8\u538b", "\u6536\u7f29\u538b"),
        "diastolic" to listOf("diastolic", "dbp", "\u4f4e\u538b", "\u8212\u5f20\u538b"),
        "pulse" to listOf("pulse", "heart rate", "hr", "\u5fc3\u7387", "\u8109\u640f"),
        "weight" to listOf("weight", "\u4f53\u91cd"), "glucose" to listOf("glucose", "\u8840\u7cd6", "\u8461\u8404\u7cd6"),
        "cholesterol" to listOf("cholesterol", "\u603b\u80c6\u56fa\u9187"), "hemoglobin" to listOf("hemoglobin", "hgb", "\u8840\u7ea2\u86cb\u767d"),
        "time" to listOf("date", "time", "datetime", "measured_at", "\u65e5\u671f", "\u65f6\u95f4", "\u6d4b\u91cf\u65f6\u95f4"),
        "unit" to listOf("unit", "units", "\u5355\u4f4d"), "note" to listOf("note", "notes", "\u5907\u6ce8")
    )
    fun suggest(headers: List<String>, metric: HealthMetric): HealthTableMapping {
        fun match(field: String): String {
            val names = aliases[field].orEmpty() + if (metric.fields.size == 1 && field == metric.fields.first()) HealthMetricCatalog.aliases(metric) else emptyList()
            return headers.filter { header -> names.any { name(it) == name(header) } }.singleOrNull().orEmpty()
        }
        val reference = headers.filter { name(it) in listOf("reference", "referencerange", "referenceinterval", "\u53c2\u8003\u8303\u56f4", "\u53c2\u8003\u533a\u95f4") }.singleOrNull().orEmpty()
        return HealthTableMapping(metric, metric.fields.associateWith(::match), match("time"), match("unit"), noteColumn = match("note"), referenceColumn = reference)
    }
    fun measuredAt(raw: String, mapping: HealthTableMapping): Long? = runCatching {
        require(mapping.date != HealthTableDate.EXCEL)
        val value = raw.trim()
        if (mapping.date == HealthTableDate.ISO) runCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }.getOrElse {
            localTime(LocalDateTime.parse(value, DateTimeFormatter.ISO_LOCAL_DATE_TIME), mapping.zone)
        } else localTime(LocalDateTime.parse(value, DateTimeFormatter.ofPattern(mapping.date.pattern, Locale.ROOT)
            .withResolverStyle(ResolverStyle.STRICT)), mapping.zone)
    }.getOrNull()
    private fun localTime(time: LocalDateTime, zone: String): Long {
        val offsets = ZoneId.of(zone).rules.getValidOffsets(time)
        require(offsets.size == 1) { "Ambiguous or nonexistent local time; use an ISO timestamp with its offset" }
        return time.toInstant(offsets.single()).toEpochMilli()
    }
    private fun dateOnlyTime(mapping: HealthTableMapping): LocalTime {
        require(mapping.dateOnlyTime.matches(Regex("(?:[01][0-9]|2[0-3]):[0-5][0-9]")))
        return LocalTime.parse(mapping.dateOnlyTime)
    }
    private fun xlsxDateOnly(raw: String, mapping: HealthTableMapping): Long? = runCatching {
        val parsed = DateTimeFormatter.ISO_DATE.parse(raw.trim())
        val local = LocalDate.from(parsed).atTime(dateOnlyTime(mapping))
        if (parsed.isSupported(ChronoField.OFFSET_SECONDS)) local.toInstant(ZoneOffset.from(parsed)).toEpochMilli()
        else localTime(local, mapping.zone)
    }.getOrNull()
    fun evaluate(batch: HealthTableBatch, row: HealthTableRow, now: Long = System.currentTimeMillis()): HealthTableEvaluation {
        fun error(state: HealthTableRowState, issue: String) = HealthTableEvaluation(null, state, issue)
        if (row.issue.isNotBlank()) return error(HealthTableRowState.INVALID, row.issue)
        val m = batch.mapping
        if (!m.valid(batch.headers)) return error(HealthTableRowState.INVALID, "mapping")
        val selected = (m.columns.values + listOf(m.timeColumn, m.unitColumn, m.noteColumn, m.referenceColumn)).filter(String::isNotBlank).toSet()
        if (row.errors.any { it in selected }) return error(HealthTableRowState.INVALID, "excel_error")
        val formulas = row.formulas.filterKeys { it in selected }
        if (formulas.isNotEmpty() && !m.allowFormulaCache) return error(HealthTableRowState.INVALID, "formula_ack")
        if (formulas.keys.any { row.cells[it].isNullOrBlank() }) return error(HealthTableRowState.MISSING, "formula_cache")
        val values = m.metric.fields.associateWith { field -> m.columns[field].let { row.numbers[it] ?: row.cells[it] }.orEmpty().trim() }
        if (m.metric.requiredFields.any { values[it].isNullOrBlank() } || row.cells[m.timeColumn].isNullOrBlank())
            return error(HealthTableRowState.MISSING, "missing")
        val rawTime = row.cells[m.timeColumn].orEmpty()
        val time = if (m.date != HealthTableDate.EXCEL) {
            measuredAt(rawTime, m) ?: if (batch.format == "xlsx" && m.date == HealthTableDate.ISO) xlsxDateOnly(rawTime, m) else null
        } else runCatching {
            require(batch.format == "xlsx")
            var local = LocalDateTime.parse(requireNotNull(row.excelDates[m.timeColumn]))
            if (row.cells[m.timeColumn]?.toBigDecimalOrNull()?.remainder(java.math.BigDecimal.ONE)?.signum() == 0) {
                local = local.toLocalDate().atTime(dateOnlyTime(m))
            }
            localTime(local, m.zone)
        }.getOrNull()
        if (time == null) return error(HealthTableRowState.INVALID, "time")
        val rawUnit = if (m.unitColumn.isBlank()) m.unit else row.cells[m.unitColumn].orEmpty().trim()
        val results = values.values.filter(String::isNotBlank).map { HealthResult.parse(it, m.metric.form) ?: return error(HealthTableRowState.INVALID, "number") }
        val unitlessLabel = results.isNotEmpty() && results.all { it.kind == HealthResultKind.QUALITATIVE }
        if (rawUnit.isBlank() && !unitlessLabel) return error(HealthTableRowState.MISSING, "unit")
        val unit = if (rawUnit.isBlank() && unitlessLabel) "" else m.metric.units.singleOrNull { it.equals(rawUnit, true) } ?: return error(HealthTableRowState.INVALID, "unit")
        val sheet = batch.sheets.singleOrNull { it.index == batch.sheetIndex }?.name.orEmpty()
        val source = (listOf("Row ${row.sourceRow}", "${m.timeColumn}: ${row.cells[m.timeColumn]}") +
            m.metric.fields.mapNotNull { field -> m.columns[field]?.takeIf(String::isNotBlank)?.let { "$it: ${row.cells[it].orEmpty()}" } } +
            listOf("Unit: $rawUnit") + (if (m.referenceColumn.isBlank()) emptyList() else listOf("Reference [${m.referenceColumn}]: ${row.cells[m.referenceColumn].orEmpty()}")) +
            if (batch.format == "xlsx") listOf("Sheet: $sheet",
                if (m.date == HealthTableDate.EXCEL) "Excel epoch: ${if (batch.date1904) 1904 else 1900}" else "Time format: ${m.date.pattern}",
                "Interpreted time: ${java.time.Instant.ofEpochMilli(time)}; zone: ${m.zone}") +
                (if (m.dateOnlyTime.isBlank()) emptyList() else listOf("Confirmed date-only time: ${m.dateOnlyTime}")) +
                formulas.map { (column, formula) -> "${row.addresses[column].orEmpty()} $column: =$formula; cached=${row.cells[column].orEmpty()} (not recalculated)" }
            else emptyList()).joinToString("\n")
        if (source.length > 8000) return error(HealthTableRowState.INVALID, "cell_size")
        val evidence = HealthEvidence(batch.originalId, batch.id, "table-row-${row.sourceRow}", batch.sha256, if (batch.format == "xlsx") batch.sheetIndex + 1 else 1, source,
            confirmed = true, kind = "table", tableRow = row.sourceRow, tableSheet = sheet)
        val draft = HealthDraft(m.metric, values, unit, time, note = row.cells[m.noteColumn].orEmpty(), evidence = evidence,
            reference = row.cells[m.referenceColumn].orEmpty())
        val validation = HealthObservationPolicy.validate(draft, now)
        return if (validation == null) HealthTableEvaluation(draft, HealthTableRowState.VALID, "")
            else error(if (validation.issue == HealthValidationIssue.MISSING_VALUE) HealthTableRowState.MISSING else HealthTableRowState.INVALID,
                when (validation.issue) { HealthValidationIssue.INVALID_TIME -> "time"; HealthValidationIssue.INVALID_NUMBER -> "number"; else -> "value" })
    }
}
