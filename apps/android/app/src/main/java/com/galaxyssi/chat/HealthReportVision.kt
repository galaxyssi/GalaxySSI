package com.galaxyssi.chat

import java.time.ZoneId
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

internal data class HealthVisionRow(val metric: HealthMetric, val values: Map<String, String>,
    val unit: String, val reference: String, val source: String) {
    init {
        require(values.keys.containsAll(metric.requiredFields) && values.keys.all { it in metric.fields })
        require(values.values.all { HealthResult.parse(it, metric.form) != null })
        require(unit.isEmpty() || unit in metric.units)
        require(reference.length <= 200 && source.length in 1..400 && source.isNotBlank())
        require(listOf(reference, source).none { it.any(Char::isISOControl) })
    }
    fun json() = JSONObject().put("metric", metric.name).put("values", JSONObject(values))
        .put("unit", unit).put("reference", reference).put("source", source)

    companion object {
        fun from(j: JSONObject): HealthVisionRow {
            require(j.keys().asSequence().toSet() == setOf("metric", "values", "unit", "reference", "source"))
            val fields = j.getJSONObject("values")
            return HealthVisionRow(HealthMetric.valueOf(j.text("metric")), fields.keys().asSequence().associateWith(fields::text),
                j.text("unit"), j.text("reference"), j.text("source"))
        }
    }
}

internal data class HealthReportVisionResult(val rows: List<HealthVisionRow>, val collected: String, val partial: Boolean,
    val fasting: String = "") {
    init {
        require(rows.size in 1..MAX_ROWS && rows.distinct() == rows)
        require(collected.length <= 80 && collected.none(Char::isISOControl))
        require(fasting.isEmpty() || fasting in healthGlucoseConditions)
    }
    fun json() = JSONObject().put("rows", JSONArray(rows.map { it.json() })).put("collected", collected).put("partial", partial)
        .apply { if (fasting.isNotEmpty()) put("fasting", fasting) }

    private fun dateOnly(): LocalDate? = runCatching { LocalDate.parse(collected) }.getOrNull()

    fun drafts(job: HealthImportJob, original: HealthOriginal, zone: ZoneId, now: Long,
        supplement: HealthReportSupplement? = null): List<HealthDraft> {
        val measuredAt = HealthOcrSourceContext.readTimestamp(collected, zone)?.millis?.takeIf { it in 1..now } ?: 0L
        val timestamp = measuredAt.takeIf { it > 0 } ?: supplement?.let {
            val date = dateOnly() ?: it.date
            if (date == null || it.time == null) null else healthReportSupplementTime(date, it.time, zone, now)
        } ?: 0L
        return rows.map { row ->
            val values = row.values.mapValues { (_, raw) -> HealthResult.parse(raw, row.metric.form)!!.let {
                if (it.kind == HealthResultKind.NUMBER) it.number else it.raw
            } }
            val key = AgentNativeJsonCodec.sha256(mapOf("metric" to row.metric.name, "values" to row.values,
                "unit" to row.unit, "reference" to row.reference, "source" to row.source, "collected" to collected))
            HealthDraft(row.metric, values, row.unit, timestamp,
                condition = if (row.metric == HealthMetric.GLUCOSE) fasting.takeUnless { it.isBlank() || it == "unspecified" }
                    ?: supplement?.condition ?: "unspecified" else "unspecified",
                evidence = HealthEvidence(original.id, job.id,
                "model-$key", original.sha256, 1, row.source, documentPage = job.documentPage, recognition = HealthRecognition.MODEL),
                reference = row.reference, reportedValues = row.values.filter { (field, raw) -> raw != values[field] })
        }
    }

    fun supplementScope(job: HealthImportJob, source: HealthOriginal, receipt: HealthReportImportOutcome?,
        zone: ZoneId, now: Long): HealthReportSupplementScope {
        if (receipt?.contextConfirmed == true || receipt != null && !receipt.pendingConfirmation && receipt.skipped == 0)
            return HealthReportSupplementScope()
        val drafts = drafts(job, source, zone, now)
        val conflicts = HealthReportDeferred.conflicts(drafts)
        val repairable = drafts.filter { draft ->
            HealthReportDeferred.reason(draft, draft.metric in conflicts) in setOf(null, HealthReportDeferred.SAMPLE_TIME) &&
                (receipt == null || receipt.pendingConfirmation || draft.measuredAt == 0L)
        }
        val time = repairable.any { it.measuredAt == 0L }
        return HealthReportSupplementScope(time, time && dateOnly() == null,
            repairable.any { it.metric == HealthMetric.GLUCOSE && it.condition == "unspecified" })
    }

    fun deferredRows(outcome: HealthReportImportOutcome, job: HealthImportJob, original: HealthOriginal?): List<Pair<HealthVisionRow, HealthReportDeferred>> {
        if (outcome.skipped == 0) return emptyList()
        // Older receipts kept the transcribed rows, but not the reason individual rows were skipped.
        val issues = outcome.deferred.ifEmpty {
            if (original == null) emptyMap() else {
                val drafts = drafts(job, original, ZoneId.systemDefault(), job.createdAt)
                val conflicts = HealthReportDeferred.conflicts(drafts)
                drafts.mapIndexedNotNull { index, draft ->
                    HealthReportDeferred.reason(draft, draft.metric in conflicts)?.let { index to it }
                }.take(outcome.skipped).toMap()
            }
        }
        return issues.mapNotNull { (index, reason) -> rows.getOrNull(index)?.let { it to reason } }
    }

    companion object {
        const val MAX_ROWS = 80
        fun from(j: JSONObject): HealthReportVisionResult {
            require(j.keys().asSequence().filterNot { it == "fasting" }.toSet() == setOf("rows", "collected", "partial"))
            val rows = j.getJSONArray("rows")
            require(rows.length() in 1..MAX_ROWS)
            return HealthReportVisionResult(List(rows.length()) { HealthVisionRow.from(rows.getJSONObject(it)) },
                j.text("collected"), j.opt("partial") as? Boolean ?: throw HealthAnalysisInvalidReply(),
                if (j.has("fasting")) j.text("fasting") else "")
        }
        fun parse(response: String): HealthReportVisionResult = try {
            val text = response.trim().let {
                if (it.startsWith("```json\n") && it.endsWith("\n```")) it.substring(8, it.length - 4) else it
            }
            val reader = JSONTokener(text)
            val value = reader.nextValue() as? JSONObject ?: throw HealthAnalysisInvalidReply()
            require(reader.nextClean() == '\u0000')
            from(value)
        } catch (_: Exception) { throw HealthAnalysisInvalidReply() }
    }
}

private fun JSONObject.text(key: String): String = opt(key) as? String ?: throw HealthAnalysisInvalidReply()
