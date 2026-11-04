package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import org.json.JSONObject

internal enum class HealthProfileField { NAME, BIRTH_DATE, REFERENCE_SEX, HEIGHT, PHYSIOLOGICAL_CONTEXT }
internal enum class HealthReferenceSex { FEMALE, MALE, OTHER, NOT_DISCLOSED }
internal enum class HealthBackgroundKind { HISTORY, MEDICATION, ALLERGY }
internal data class HealthProfileInput(val text: String = "", val unit: String = "") {
    fun json() = JSONObject().put("text", text).put("unit", unit)
    companion object { fun from(j: JSONObject) = HealthProfileInput(j.getString("text"), j.getString("unit")) }
}
internal data class HealthProfileCell(val value: HealthProfileInput?, val token: String, val updatedAt: Long)
internal data class HealthProfileDraft(val generation: String, val changes: Map<HealthProfileField, HealthProfileInput>, val expected: Map<HealthProfileField, String>) {
    init { require(changes.keys == expected.keys) }
    fun json() = JSONObject().put("generation", generation).put("changes", JSONObject().apply { changes.forEach { (k, v) -> put(k.name, v.json()) } })
        .put("expected", JSONObject().apply { expected.forEach { (k, v) -> put(k.name, v) } })
    companion object {
        fun from(j: JSONObject): HealthProfileDraft {
            val values = j.getJSONObject("changes"); val expected = j.getJSONObject("expected")
            return HealthProfileDraft(j.getString("generation"), values.keys().asSequence().associate { HealthProfileField.valueOf(it) to HealthProfileInput.from(values.getJSONObject(it)) },
                expected.keys().asSequence().associate { HealthProfileField.valueOf(it) to expected.getString(it) })
        }
    }
}
internal data class HealthBackgroundEntry(val id: String, val kind: HealthBackgroundKind, val name: String, val detail: String = "",
    val dose: String = "", val timing: String = "", val token: String = "", val updatedAt: Long = 0) {
    fun json() = JSONObject().put("id", id).put("profile", "self").put("source", "self_reported").put("kind", kind.name)
        .put("name", name).put("detail", detail).put("dose", dose).put("timing", timing).put("token", token).put("updated", updatedAt)
    companion object {
        fun from(j: JSONObject): HealthBackgroundEntry {
            require(j.getString("profile") == "self" && j.getString("source") == "self_reported")
            return HealthBackgroundEntry(j.getString("id"), HealthBackgroundKind.valueOf(j.getString("kind")), j.getString("name"),
                j.getString("detail"), j.getString("dose"), j.getString("timing"), j.getString("token"), j.getLong("updated"))
        }
    }
}
internal data class HealthBackgroundDraft(val generation: String, val entry: HealthBackgroundEntry, val expected: String = "") {
    val key get() = if (expected.isEmpty()) "new:${entry.kind.name}" else "edit:${entry.id}"
    fun json() = JSONObject().put("generation", generation).put("entry", entry.json()).put("expected", expected)
    companion object { fun from(j: JSONObject) = HealthBackgroundDraft(j.getString("generation"), HealthBackgroundEntry.from(j.getJSONObject("entry")), j.getString("expected")) }
}
internal data class HealthProfileSnapshot(val generation: String, val cells: Map<HealthProfileField, HealthProfileCell>,
    val counts: Map<HealthBackgroundKind, Long>, val draft: HealthProfileDraft?, val token: String)
internal data class HealthBackgroundCursor(val kind: HealthBackgroundKind, val updatedAt: Long, val id: String, val version: String)
internal data class HealthBackgroundPage(val entries: List<HealthBackgroundEntry>, val next: HealthBackgroundCursor?, val stamp: HealthProfileStamp)
internal data class HealthProfileStamp(val generation: String, val versions: Map<String, String>) {
    fun json() = JSONObject().put("generation", generation).put("versions", JSONObject(versions))
    companion object { fun from(j: JSONObject): HealthProfileStamp { val values = j.getJSONObject("versions"); return HealthProfileStamp(j.getString("generation"), values.keys().asSequence().associateWith(values::getString)) } }
}
internal data class HealthProfileContext(val fields: Map<HealthProfileField, HealthProfileInput?>, val entries: List<HealthBackgroundEntry>, val stamp: HealthProfileStamp) {
    val source = "self_reported"
    val profileId = "self"
}
internal data class HealthProfileDeletePreview(val fields: Int, val entries: Long, val drafts: Long, val token: String)
internal class HealthProfileConflict : IllegalStateException("Health profile changed")
internal class HealthProfileValidation(val code: String) : IllegalArgumentException(code)

internal object HealthProfilePolicy {
    fun uuid(value: String) = runCatching { UUID.fromString(value).toString() == value }.getOrDefault(false)
    fun draftText(text: String, max: Int) = text.length <= max && text.none { it == '\u0000' || it.isISOControl() && it !in "\n\r\t" }
    fun normalize(field: HealthProfileField, input: HealthProfileInput, today: LocalDate = LocalDate.now()): HealthProfileInput? {
        val text = input.text.trim()
        if (text.isEmpty()) return null
        if (!draftText(text, if (field == HealthProfileField.PHYSIOLOGICAL_CONTEXT) 1000 else 160)) throw HealthProfileValidation("text")
        if (field != HealthProfileField.HEIGHT && input.unit.isNotEmpty()) throw HealthProfileValidation("unit")
        return when (field) {
            HealthProfileField.NAME -> { if (text.any(Char::isISOControl) || text.length > 80) throw HealthProfileValidation("name"); HealthProfileInput(text) }
            HealthProfileField.BIRTH_DATE -> {
                val date = runCatching { LocalDate.parse(text) }.getOrNull() ?: throw HealthProfileValidation("date")
                if (date.year !in 1..9999 || date > today || date.toString() != text) throw HealthProfileValidation("date")
                HealthProfileInput(text)
            }
            HealthProfileField.REFERENCE_SEX -> { if (HealthReferenceSex.entries.none { it.name == text }) throw HealthProfileValidation("sex"); HealthProfileInput(text) }
            HealthProfileField.HEIGHT -> {
                if (input.unit !in listOf("cm", "in")) throw HealthProfileValidation("unit")
                val number = HealthResult.parse(text, HealthResultForm.POSITIVE)?.exactNumber ?: throw HealthProfileValidation("height")
                HealthProfileInput(number.toPlainString(), input.unit)
            }
            HealthProfileField.PHYSIOLOGICAL_CONTEXT -> HealthProfileInput(text)
        }
    }
    fun centimeters(value: HealthProfileInput) = requireNotNull(normalize(HealthProfileField.HEIGHT, value)).let { it.text.toBigDecimal() * if (it.unit == "in") BigDecimal("2.54") else BigDecimal.ONE }
    fun entry(value: HealthBackgroundEntry): HealthBackgroundEntry {
        if (!uuid(value.id)) throw HealthProfileValidation("identity")
        val normalized = value.copy(name = value.name.trim(), detail = value.detail.trim(), dose = value.dose.trim(), timing = value.timing.trim())
        if (normalized.name.isEmpty() || !draftText(normalized.name, 160) || normalized.name.any(Char::isISOControl)) throw HealthProfileValidation("entry_name")
        if (!draftText(normalized.detail, 4000) || !draftText(normalized.dose, 200) || !draftText(normalized.timing, 300)) throw HealthProfileValidation("text")
        if (value.kind != HealthBackgroundKind.MEDICATION && (normalized.dose.isNotEmpty() || normalized.timing.isNotEmpty())) throw HealthProfileValidation("kind")
        return normalized
    }
    fun validateDraft(value: HealthProfileDraft) {
        require(value.changes.keys == value.expected.keys && value.changes.values.all { draftText(it.text, 1000) && it.unit.length <= 16 })
    }
    fun validateDraft(value: HealthBackgroundDraft) {
        require(uuid(value.entry.id) && draftText(value.entry.name, 160) && draftText(value.entry.detail, 4000) && draftText(value.entry.dose, 200) && draftText(value.entry.timing, 300))
    }
}
