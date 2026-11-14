package com.galaxyssi.chat

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

internal val healthGlucoseConditions = listOf("fasting", "after_meal_1h", "after_meal_2h", "after_meal", "non_fasting", "unspecified")
internal val healthNonFastingConditions = healthGlucoseConditions.filterNot { it in setOf("fasting", "unspecified") }.toSet()

internal data class HealthReportSupplement(val date: LocalDate? = null, val time: java.time.LocalTime? = null,
    val condition: String = "unspecified") {
    init { require(condition in healthGlucoseConditions) }
}
internal class HealthReportTimeInvalid : IllegalArgumentException()

internal data class HealthReportSupplementScope(val needsTime: Boolean = false, val needsDate: Boolean = false,
    val needsCondition: Boolean = false) {
    val needed get() = needsTime || needsCondition
    operator fun plus(other: HealthReportSupplementScope) = HealthReportSupplementScope(
        needsTime || other.needsTime, needsDate || other.needsDate, needsCondition || other.needsCondition)
}

internal fun healthReportSupplementTime(date: LocalDate, time: java.time.LocalTime, zone: ZoneId, now: Long): Long? {
    val local = LocalDateTime.of(date, time)
    return zone.rules.getValidOffsets(local).singleOrNull()?.let { local.toInstant(it).toEpochMilli() }
        ?.takeIf { it in 1..now }
}

internal enum class HealthReportDeferred { SAMPLE_TIME, UNIT, CONFLICT, INVALID;
    companion object {
        fun reason(draft: HealthDraft, conflicting: Boolean): HealthReportDeferred? {
            if (conflicting) return CONFLICT
            val evidence = requireNotNull(draft.evidence)
            return when (HealthObservationPolicy.validate(draft.copy(evidence = evidence.copy(confirmed = true)))?.issue) {
                null -> null
                HealthValidationIssue.INVALID_TIME -> SAMPLE_TIME
                HealthValidationIssue.INVALID_UNIT -> UNIT
                else -> INVALID
            }
        }
        fun conflicts(drafts: List<HealthDraft>) = drafts.groupBy { it.metric }.filterValues { rows ->
            rows.distinctBy { row ->
                row.values.mapValues { HealthResult.parse(it.value, row.metric.form)?.canonical } to row.unit
            }.size > 1
        }.keys
    }
}

internal data class HealthReportImportOutcome(
    val saved: Int, val duplicates: Int, val skipped: Int, val partial: Boolean, val imageBytes: Int,
    val recordIds: List<String>, val deferred: Map<Int, HealthReportDeferred> = emptyMap(),
    val pendingConfirmation: Boolean = false, val contextConfirmed: Boolean = false
) {
    init {
        require(listOf(saved, duplicates, skipped).all { it in 0..HealthReportVisionResult.MAX_ROWS })
        require(saved + duplicates + skipped <= HealthReportVisionResult.MAX_ROWS)
        require(imageBytes in 0..HealthReportCodexGateway.MAX_IMAGE_BYTES)
        require(recordIds.size <= saved + duplicates && recordIds.distinct() == recordIds &&
            recordIds.all(HealthProfilePolicy::uuid))
        require(deferred.size <= skipped && deferred.keys.all { it in 0 until HealthReportVisionResult.MAX_ROWS })
    }
    fun json() = JSONObject().put("saved", saved).put("duplicates", duplicates).put("skipped", skipped)
        .put("partial", partial).put("image_bytes", imageBytes).put("records", JSONArray(recordIds))
        .apply { if (deferred.isNotEmpty()) put("deferred", JSONObject(deferred.entries.associate { it.key.toString() to it.value.name })) }
        .apply { if (pendingConfirmation) put("pending_confirmation", true) }
        .apply { if (contextConfirmed) put("context_confirmed", true) }

    companion object {
        fun from(j: JSONObject) = HealthReportImportOutcome(j.getInt("saved"), j.getInt("duplicates"),
            j.getInt("skipped"), j.getBoolean("partial"), j.getInt("image_bytes"),
            j.getJSONArray("records").let { a -> List(a.length(), a::getString) },
            j.optJSONObject("deferred")?.let { d -> d.keys().asSequence().associate { it.toInt() to HealthReportDeferred.valueOf(d.getString(it)) } }.orEmpty(),
            j.optBoolean("pending_confirmation"), j.optBoolean("context_confirmed"))
    }
}
