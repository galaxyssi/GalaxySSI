package com.galaxyssi.chat

import java.math.BigDecimal
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONObject

internal enum class HealthResultForm { POSITIVE, NONNEGATIVE, COUNT, LABORATORY, QUALITATIVE }
internal enum class HealthMetric(val fields: List<String>, val units: List<String>, val form: HealthResultForm = HealthResultForm.POSITIVE) {
    BLOOD_PRESSURE(listOf("systolic", "diastolic", "pulse"), listOf("mmHg", "kPa")),
    GLUCOSE(listOf("glucose"), listOf("mmol/L", "mg/dL"), HealthResultForm.LABORATORY),
    WEIGHT(listOf("weight"), listOf("kg", "lb")),
    HEART_RATE(listOf("pulse"), listOf("bpm")),
    CHOLESTEROL(listOf("cholesterol"), listOf("mmol/L", "mg/dL"), HealthResultForm.LABORATORY),
    HEMOGLOBIN(listOf("hemoglobin"), listOf("g/L", "g/dL"), HealthResultForm.LABORATORY),
    RESTING_HEART_RATE(listOf("resting_pulse"), listOf("bpm")),
    SLEEP_DURATION(listOf("sleep_duration"), listOf("h", "min"), HealthResultForm.NONNEGATIVE),
    STEPS(listOf("steps"), listOf("steps"), HealthResultForm.COUNT),
    TEMPERATURE(listOf("temperature"), listOf("\u00b0C", "\u00b0F")),
    OXYGEN_SATURATION(listOf("spo2"), listOf("%")),
    HEIGHT(listOf("height"), listOf("cm", "m", "in")),
    WAIST(listOf("waist"), listOf("cm", "in")),
    BODY_FAT(listOf("body_fat"), listOf("%")),
    LDL(listOf("ldl"), listOf("mmol/L", "mg/dL"), HealthResultForm.LABORATORY),
    HDL(listOf("hdl"), listOf("mmol/L", "mg/dL"), HealthResultForm.LABORATORY),
    TRIGLYCERIDES(listOf("triglycerides"), listOf("mmol/L", "mg/dL"), HealthResultForm.LABORATORY),
    HBA1C(listOf("hba1c"), listOf("%", "mmol/mol"), HealthResultForm.LABORATORY),
    WHITE_BLOOD_CELLS(listOf("wbc"), listOf("10^9/L", "10^3/uL"), HealthResultForm.LABORATORY),
    PLATELETS(listOf("platelets"), listOf("10^9/L", "10^3/uL"), HealthResultForm.LABORATORY),
    ALT(listOf("alt"), listOf("U/L"), HealthResultForm.LABORATORY),
    AST(listOf("ast"), listOf("U/L"), HealthResultForm.LABORATORY),
    CREATININE(listOf("creatinine"), listOf("umol/L", "mg/dL"), HealthResultForm.LABORATORY),
    URIC_ACID(listOf("uric_acid"), listOf("umol/L", "mg/dL"), HealthResultForm.LABORATORY),
    CRP(listOf("crp"), listOf("mg/L", "mg/dL"), HealthResultForm.LABORATORY),
    TSH(listOf("tsh"), listOf("mIU/L", "uIU/mL"), HealthResultForm.LABORATORY),
    URINE_PROTEIN(listOf("urine_protein"), listOf(""), HealthResultForm.QUALITATIVE);
    val requiredFields get() = if (this == BLOOD_PRESSURE) fields.take(2) else fields
    val selectableUnits get() = if (form == HealthResultForm.LABORATORY) listOf("") + units else units
}

internal data class HealthDraft(
    val metric: HealthMetric = HealthMetric.BLOOD_PRESSURE,
    val values: Map<String, String> = emptyMap(),
    val unit: String = metric.units.first(),
    val measuredAt: Long = System.currentTimeMillis(),
    val condition: String = "unspecified",
    val side: String = "unspecified",
    val note: String = "",
    val recordId: String = "",
    val revision: Int = 0,
    val evidence: HealthEvidence? = null,
    val reference: String = "",
    val reportedValues: Map<String, String> = emptyMap()
) {
    fun hasInput() = evidence != null || values.values.any(String::isNotBlank) || note.isNotBlank() || reference.isNotBlank()
    fun unitFor(field: String) = if (metric == HealthMetric.BLOOD_PRESSURE && field == "pulse") "bpm" else unit
    fun json() = JSONObject().put("metric", metric.name).put("values", JSONObject(values)).put("unit", unit)
        .put("component_units", JSONObject(values.keys.associateWith(::unitFor)))
        .put("measured_at", measuredAt).put("condition", condition).put("side", side).put("note", note)
        .put("record_id", recordId).put("revision", revision)
        .put("reference", reference).put("reported_values", JSONObject(reportedValues))
        .put("results", JSONObject(values.mapNotNull { (field, raw) -> HealthResult.parse(raw, metric.form)?.let { field to it.json() } }.toMap()))
        .apply { evidence?.let { put("evidence", it.json()) } }

    companion object {
        fun from(json: JSONObject): HealthDraft {
            val values = json.getJSONObject("values")
            val draft = HealthDraft(HealthMetric.valueOf(json.getString("metric")),
                values.keys().asSequence().associateWith(values::getString), json.getString("unit"),
                json.getLong("measured_at"), json.getString("condition"), json.getString("side"),
                json.getString("note"), json.getString("record_id"), json.getInt("revision"), json.optJSONObject("evidence")?.let(HealthEvidence::from),
                json.optString("reference"), json.optJSONObject("reported_values")?.let { v -> v.keys().asSequence().associateWith(v::getString) }.orEmpty())
            val units = json.getJSONObject("component_units")
            require(draft.values.keys.all { units.getString(it) == draft.unitFor(it) })
            json.optJSONObject("results")?.let { results ->
                require(results.keys().asSequence().all { field ->
                    val actual = HealthResult.parse(draft.values[field].orEmpty(), draft.metric.form)
                    actual != null && HealthResult.from(results.getJSONObject(field)) == actual
                })
            }
            return draft
        }
    }
}

internal data class HealthObservation(
    val id: String,
    val revision: Int,
    val draft: HealthDraft,
    val receivedAt: Long,
    val source: String = "manual",
    val profileId: String = "self",
    val platformOrigin: String = "",
) {
    fun json() = JSONObject().put("format", 1).put("id", id).put("revision", revision).put("draft", draft.json())
        .put("received_at", receivedAt).put("source", source).put("profile_id", profileId)
        .apply { if (platformOrigin.isNotEmpty()) put("platform_origin", platformOrigin) }
    fun editable() = draft.copy(recordId = id, revision = revision)
    companion object {
        fun from(json: JSONObject): HealthObservation {
            require(json.getInt("format") == 1)
            return HealthObservation(json.getString("id"), json.getInt("revision"), HealthDraft.from(json.getJSONObject("draft")),
                json.getLong("received_at"), json.getString("source"), json.getString("profile_id"), json.optString("platform_origin"))
                .also { record -> require(record.draft.reportedValues.all { (field, raw) ->
                    HealthResult.parse(raw, record.draft.metric.form)?.canonical == HealthResult.parse(record.draft.values[field].orEmpty(), record.draft.metric.form)?.canonical
                }) }
        }
    }
}

internal enum class HealthValidationIssue { MISSING_VALUE, INVALID_NUMBER, INVALID_UNIT, INVALID_TIME, INVALID_CONTEXT, UNCONFIRMED_SOURCE }
internal data class HealthValidationError(val issue: HealthValidationIssue, val field: String = "")

internal object HealthObservationPolicy {
    fun validate(draft: HealthDraft, now: Long = System.currentTimeMillis()): HealthValidationError? {
        if (draft.evidence?.let { !it.valid() || !it.confirmed } == true) return HealthValidationError(HealthValidationIssue.UNCONFIRMED_SOURCE)
        val recorded = draft.values.values.filter(String::isNotBlank)
        val unitlessLabel = draft.unit.isBlank() && recorded.isNotEmpty() && recorded.all { HealthResult.parse(it, draft.metric.form)?.kind == HealthResultKind.QUALITATIVE }
        if (draft.unit !in draft.metric.units && !unitlessLabel) return HealthValidationError(HealthValidationIssue.INVALID_UNIT)
        if (draft.measuredAt <= 0 || draft.measuredAt > now + 60_000) return HealthValidationError(HealthValidationIssue.INVALID_TIME)
        if (draft.condition !in listOf("unspecified", "resting", "after_exercise", "fasting", "after_meal", "other") ||
            draft.side !in listOf("unspecified", "left", "right") || draft.note.length > 2000 ||
            draft.values.keys.any { it !in draft.metric.fields } || draft.reference.length > 200 || draft.reference.any(Char::isISOControl) ||
            draft.reportedValues.any { (field, raw) -> field !in draft.metric.fields || raw.length > HealthResult.MAX_LENGTH || raw.any(Char::isISOControl) })
            return HealthValidationError(HealthValidationIssue.INVALID_CONTEXT)
        for (field in draft.metric.fields) {
            val raw = draft.values[field].orEmpty().trim()
            if (raw.isBlank()) {
                if (field in draft.metric.requiredFields) return HealthValidationError(HealthValidationIssue.MISSING_VALUE, field)
                continue
            }
            if (HealthResult.parse(raw, draft.metric.form) == null) return HealthValidationError(HealthValidationIssue.INVALID_NUMBER, field)
        }
        return null
    }

    fun canonicalNumber(raw: String): String? {
        val value = raw.trim().replace(',', '.')
        if (value.length > 20 || !value.matches(Regex("(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)"))) return null
        val decimal = value.toBigDecimalOrNull() ?: return null
        return decimal.takeIf { it > BigDecimal.ZERO }?.stripTrailingZeros()?.toPlainString()
    }

    fun normalize(draft: HealthDraft): HealthDraft {
        val values = draft.metric.fields.mapNotNull { field -> draft.values[field]?.takeIf(String::isNotBlank)?.let {
            field to requireNotNull(HealthResult.parse(it, draft.metric.form))
        } }.toMap()
        return draft.copy(values = values.mapValues { (_, result) -> if (result.kind == HealthResultKind.NUMBER) result.canonical else result.raw },
            reportedValues = values.mapValues { (field, result) -> draft.reportedValues[field]?.takeIf {
                HealthResult.parse(it, draft.metric.form)?.canonical == result.canonical
            } ?: result.raw }, note = draft.note.trim(), reference = draft.reference.trim())
    }

    fun observation(draft: HealthDraft, now: Long = System.currentTimeMillis()): HealthObservation {
        require(validate(draft, now) == null)
        val normalized = normalize(draft)
        return HealthObservation(draft.recordId.ifBlank { UUID.randomUUID().toString() }, draft.revision + 1,
            normalized.copy(recordId = "", revision = 0), now, source = draft.evidence?.let { if (it.kind == "table") "table" else "ocr" } ?: "manual")
    }

    fun duplicateKey(record: HealthObservation): String {
        val draft = record.draft
        val input = listOf(record.profileId, record.source, draft.metric.name, draft.unit, draft.measuredAt.toString(),
            draft.condition, draft.side) + draft.metric.fields.map { HealthResult.parse(draft.values[it].orEmpty(), draft.metric.form)?.canonical.orEmpty() }
        val bytes = input.joinToString("\u0000").toByteArray(Charsets.UTF_8)
        return try { MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } }
        finally { bytes.fill(0) }
    }
}
