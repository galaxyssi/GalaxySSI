package com.galaxyssi.chat

import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.Locale
import org.json.JSONObject

internal enum class HealthTableState { READING, MAPPING, VALIDATING, READY, SAVING, SAVED, UNDOING, UNDONE, FAILED }
internal enum class HealthTableRowState { PENDING, VALID, DUPLICATE, MISSING, INVALID, SAVED, UNDONE, EDITED }
internal enum class HealthTableDate(val pattern: String) {
    ISO("ISO 8601"), YMD("uuuu-MM-dd HH:mm"), YMD_SECONDS("uuuu-MM-dd HH:mm:ss"),
    SLASH_YMD("uuuu/MM/dd HH:mm"), DMY("dd/MM/uuuu HH:mm"), MDY("MM/dd/uuuu HH:mm")
}
internal data class HealthTableMapping(
    val metric: HealthMetric = HealthMetric.BLOOD_PRESSURE,
    val columns: Map<String, String> = emptyMap(), val timeColumn: String = "", val unitColumn: String = "",
    val unit: String = "", val noteColumn: String = "", val date: HealthTableDate = HealthTableDate.ISO,
    val zone: String = ZoneId.systemDefault().id
) {
    fun json() = JSONObject().put("metric", metric.name).put("columns", JSONObject(columns)).put("time", timeColumn)
        .put("unit_column", unitColumn).put("unit", unit).put("note", noteColumn).put("date", date.name).put("zone", zone)
    fun valid(headers: List<String>): Boolean = timeColumn in headers && metric.requiredFields.all { columns[it] in headers } &&
        columns.keys.all { it in metric.fields } && columns.values.filter(String::isNotBlank).let { it.size == it.distinct().size } &&
        (unitColumn in headers || unitColumn.isBlank() && unit in metric.units) &&
        (noteColumn.isBlank() || noteColumn in headers) && runCatching { ZoneId.of(zone) }.isSuccess
    companion object {
        fun from(j: JSONObject) = HealthTableMapping(HealthMetric.valueOf(j.getString("metric")), j.getJSONObject("columns").let { c ->
            c.keys().asSequence().associateWith(c::getString)
        }, j.getString("time"), j.getString("unit_column"), j.getString("unit"), j.getString("note"),
            HealthTableDate.valueOf(j.getString("date")), j.getString("zone"))
    }
}
internal data class HealthTableRow(val number: Long, val cells: Map<String, String>, val issue: String = "") {
    fun json() = JSONObject().put("number", number).put("cells", JSONObject(cells)).put("issue", issue)
    companion object {
        fun from(j: JSONObject) = HealthTableRow(j.getLong("number"), j.getJSONObject("cells").let { c ->
            c.keys().asSequence().associateWith(c::getString)
        }, j.getString("issue"))
    }
}
internal data class HealthTableBatch(
    val id: String, val originalId: String, val sha256: String, val name: String, val format: String,
    val headers: List<String> = emptyList(), val rows: Long = 0, val cursor: Long = 0,
    val state: HealthTableState = HealthTableState.READING, val mapping: HealthTableMapping = HealthTableMapping(),
    val mappingRevision: Int = 0, val error: String = ""
) {
    fun json() = JSONObject().put("id", id).put("original", originalId).put("sha256", sha256).put("name", name).put("format", format)
        .put("headers", org.json.JSONArray(headers)).put("rows", rows).put("cursor", cursor).put("state", state.name)
        .put("mapping", mapping.json()).put("revision", mappingRevision).put("error", error)
    companion object {
        fun from(j: JSONObject) = HealthTableBatch(j.getString("id"), j.getString("original"), j.getString("sha256"), j.getString("name"),
            j.getString("format"), j.getJSONArray("headers").let { a -> (0 until a.length()).map(a::getString) }, j.getLong("rows"),
            j.getLong("cursor"), HealthTableState.valueOf(j.getString("state")), HealthTableMapping.from(j.getJSONObject("mapping")),
            j.getInt("revision"), j.getString("error"))
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
        fun match(field: String) = headers.filter { header -> aliases[field].orEmpty().any { name(it) == name(header) } }.singleOrNull().orEmpty()
        return HealthTableMapping(metric, metric.fields.associateWith(::match), match("time"), match("unit"), noteColumn = match("note"))
    }
    fun measuredAt(raw: String, mapping: HealthTableMapping): Long? = runCatching {
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
    fun evaluate(batch: HealthTableBatch, row: HealthTableRow, now: Long = System.currentTimeMillis()): HealthTableEvaluation {
        fun error(state: HealthTableRowState, issue: String) = HealthTableEvaluation(null, state, issue)
        if (row.issue.isNotBlank()) return error(HealthTableRowState.INVALID, row.issue)
        val m = batch.mapping
        if (!m.valid(batch.headers)) return error(HealthTableRowState.INVALID, "mapping")
        val values = m.metric.fields.associateWith { row.cells[m.columns[it]].orEmpty().trim() }
        if (m.metric.requiredFields.any { values[it].isNullOrBlank() } || row.cells[m.timeColumn].isNullOrBlank())
            return error(HealthTableRowState.MISSING, "missing")
        val time = measuredAt(row.cells[m.timeColumn].orEmpty(), m) ?: return error(HealthTableRowState.INVALID, "time")
        val rawUnit = if (m.unitColumn.isBlank()) m.unit else row.cells[m.unitColumn].orEmpty().trim()
        if (rawUnit.isBlank()) return error(HealthTableRowState.MISSING, "unit")
        val unit = m.metric.units.singleOrNull { it.equals(rawUnit, true) } ?: return error(HealthTableRowState.INVALID, "unit")
        val source = (listOf("Row ${row.number}", "${m.timeColumn}: ${row.cells[m.timeColumn]}") +
            m.metric.fields.mapNotNull { field -> m.columns[field]?.takeIf(String::isNotBlank)?.let { "$it: ${row.cells[it].orEmpty()}" } } +
            "Unit: $rawUnit").joinToString("\n")
        if (source.length > 8000) return error(HealthTableRowState.INVALID, "cell_size")
        val evidence = HealthEvidence(batch.originalId, batch.id, "table-row-${row.number}", batch.sha256, 1, source,
            confirmed = true, kind = "table", tableRow = row.number)
        val draft = HealthDraft(m.metric, values, unit, time, note = row.cells[m.noteColumn].orEmpty(), evidence = evidence)
        val validation = HealthObservationPolicy.validate(draft, now)
        return if (validation == null) HealthTableEvaluation(draft, HealthTableRowState.VALID, "")
            else error(if (validation.issue == HealthValidationIssue.MISSING_VALUE) HealthTableRowState.MISSING else HealthTableRowState.INVALID,
                when (validation.issue) { HealthValidationIssue.INVALID_TIME -> "time"; HealthValidationIssue.INVALID_NUMBER -> "number"; else -> "value" })
    }
}
