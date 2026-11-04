package com.galaxyssi.chat

import java.math.BigDecimal
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONObject

internal enum class HealthMetric(val fields: List<String>, val units: List<String>) {
    BLOOD_PRESSURE(listOf("systolic", "diastolic", "pulse"), listOf("mmHg")),
    GLUCOSE(listOf("glucose"), listOf("mmol/L", "mg/dL")),
    WEIGHT(listOf("weight"), listOf("kg", "lb")),
    HEART_RATE(listOf("pulse"), listOf("bpm"));
    val requiredFields get() = if (this == BLOOD_PRESSURE) fields.take(2) else fields
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
    val revision: Int = 0
) {
    fun hasInput() = values.values.any(String::isNotBlank) || note.isNotBlank()
    fun unitFor(field: String) = if (metric == HealthMetric.BLOOD_PRESSURE && field == "pulse") "bpm" else unit
    fun json() = JSONObject().put("metric", metric.name).put("values", JSONObject(values)).put("unit", unit)
        .put("component_units", JSONObject(values.keys.associateWith(::unitFor)))
        .put("measured_at", measuredAt).put("condition", condition).put("side", side).put("note", note)
        .put("record_id", recordId).put("revision", revision)

    companion object {
        fun from(json: JSONObject): HealthDraft {
            val values = json.getJSONObject("values")
            val draft = HealthDraft(HealthMetric.valueOf(json.getString("metric")),
                values.keys().asSequence().associateWith(values::getString), json.getString("unit"),
                json.getLong("measured_at"), json.getString("condition"), json.getString("side"),
                json.getString("note"), json.getString("record_id"), json.getInt("revision"))
            val units = json.getJSONObject("component_units")
            require(draft.values.keys.all { units.getString(it) == draft.unitFor(it) })
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
    val profileId: String = "self"
) {
    fun json() = JSONObject().put("format", 1).put("id", id).put("revision", revision).put("draft", draft.json())
        .put("received_at", receivedAt).put("source", source).put("profile_id", profileId)
    fun editable() = draft.copy(recordId = id, revision = revision)
    companion object {
        fun from(json: JSONObject): HealthObservation {
            require(json.getInt("format") == 1)
            return HealthObservation(json.getString("id"), json.getInt("revision"), HealthDraft.from(json.getJSONObject("draft")),
                json.getLong("received_at"), json.getString("source"), json.getString("profile_id"))
        }
    }
}

internal enum class HealthValidationIssue { MISSING_VALUE, INVALID_NUMBER, INVALID_UNIT, INVALID_TIME, INVALID_CONTEXT }
internal data class HealthValidationError(val issue: HealthValidationIssue, val field: String = "")

internal object HealthObservationPolicy {
    fun validate(draft: HealthDraft, now: Long = System.currentTimeMillis()): HealthValidationError? {
        if (draft.unit !in draft.metric.units) return HealthValidationError(HealthValidationIssue.INVALID_UNIT)
        if (draft.measuredAt <= 0 || draft.measuredAt > now + 60_000) return HealthValidationError(HealthValidationIssue.INVALID_TIME)
        if (draft.condition !in listOf("unspecified", "resting", "after_exercise", "fasting", "after_meal", "other") ||
            draft.side !in listOf("unspecified", "left", "right") || draft.note.length > 2000 ||
            draft.values.keys.any { it !in draft.metric.fields }) return HealthValidationError(HealthValidationIssue.INVALID_CONTEXT)
        for (field in draft.metric.fields) {
            val raw = draft.values[field].orEmpty().trim()
            if (raw.isBlank()) {
                if (field in draft.metric.requiredFields) return HealthValidationError(HealthValidationIssue.MISSING_VALUE, field)
                continue
            }
            if (canonicalNumber(raw) == null) return HealthValidationError(HealthValidationIssue.INVALID_NUMBER, field)
        }
        return null
    }

    fun canonicalNumber(raw: String): String? {
        val value = raw.trim().replace(',', '.')
        if (value.length > 20 || !value.matches(Regex("(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)"))) return null
        val decimal = value.toBigDecimalOrNull() ?: return null
        return decimal.takeIf { it > BigDecimal.ZERO }?.stripTrailingZeros()?.toPlainString()
    }

    fun normalize(draft: HealthDraft): HealthDraft = draft.copy(values = draft.metric.fields.mapNotNull { field ->
        draft.values[field]?.takeIf(String::isNotBlank)?.let { field to requireNotNull(canonicalNumber(it)) }
    }.toMap(), note = draft.note.trim())

    fun observation(draft: HealthDraft, now: Long = System.currentTimeMillis()): HealthObservation {
        require(validate(draft, now) == null)
        val normalized = normalize(draft)
        return HealthObservation(draft.recordId.ifBlank { UUID.randomUUID().toString() }, draft.revision + 1,
            normalized.copy(recordId = "", revision = 0), now)
    }

    fun duplicateKey(record: HealthObservation): String {
        val draft = record.draft
        val input = listOf(record.profileId, record.source, draft.metric.name, draft.unit, draft.measuredAt.toString(),
            draft.condition, draft.side) + draft.metric.fields.map { draft.values[it].orEmpty() }
        val bytes = input.joinToString("\u0000").toByteArray(Charsets.UTF_8)
        return try { MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } }
        finally { bytes.fill(0) }
    }
}
