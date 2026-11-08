package com.galaxyssi.chat

import java.time.ZoneId
import org.json.JSONObject

internal enum class HealthCareEncounterState { PLANNED, BOOKING_RECORDED, ATTENDED, CANCELLED }

/** A local self-report, never a hospital booking receipt or a verified clinical instruction. */
internal data class HealthCareEncounterDraft(
    val purpose: String, val facility: String = "", val state: HealthCareEncounterState = HealthCareEncounterState.PLANNED,
    val plannedAt: Long? = null, val attendedAt: Long? = null, val zone: String = "UTC", val note: String = ""
) {
    init {
        require(purpose.isNotBlank() && purpose.length <= 500 && facility.length <= 500 && note.length <= 4000)
        require(purpose == purpose.trim() && facility == facility.trim() && note == note.trim())
        require(plannedAt == null || plannedAt > 0)
        require(attendedAt == null || attendedAt > 0)
        require((state == HealthCareEncounterState.ATTENDED) == (attendedAt != null))
        require(state != HealthCareEncounterState.BOOKING_RECORDED || plannedAt != null)
        ZoneId.of(zone)
    }
    fun json() = JSONObject().put("purpose", purpose).put("facility", facility).put("state", state.name)
        .put("planned_at", plannedAt ?: JSONObject.NULL).put("attended_at", attendedAt ?: JSONObject.NULL)
        .put("zone", zone).put("note", note)
    companion object {
        fun from(j: JSONObject) = HealthCareEncounterDraft(j.getString("purpose"), j.getString("facility"),
            HealthCareEncounterState.valueOf(j.getString("state")), j.takeUnless { it.isNull("planned_at") }?.getLong("planned_at"),
            j.takeUnless { it.isNull("attended_at") }?.getLong("attended_at"), j.getString("zone"), j.getString("note"))
    }
}

internal data class HealthCareEncounter(val id: String, val concernId: String, val revision: Int,
    val sourceRecord: HealthCareRecordRef?, val createdAt: Long, val updatedAt: Long, val details: HealthCareEncounterDraft) {
    init {
        require(HealthProfilePolicy.uuid(id) && HealthProfilePolicy.uuid(concernId) && revision > 0)
        require(createdAt > 0 && updatedAt >= createdAt)
    }
    fun json() = JSONObject().put("id", id).put("concern", concernId).put("revision", revision)
        .put("source_record", sourceRecord?.json() ?: JSONObject.NULL).put("created_at", createdAt)
        .put("updated_at", updatedAt).put("details", details.json()).put("provenance", "user_reported")
    companion object {
        fun from(j: JSONObject): HealthCareEncounter {
            require(j.getString("provenance") == "user_reported")
            return HealthCareEncounter(j.getString("id"), j.getString("concern"), j.getInt("revision"),
                j.optJSONObject("source_record")?.let(HealthCareRecordRef::from), j.getLong("created_at"), j.getLong("updated_at"),
                HealthCareEncounterDraft.from(j.getJSONObject("details")))
        }
    }
}

internal data class HealthCareEncounterReceipt(val operationId: String, val expectedConcernRevision: Int,
    val expectedEncounterRevision: Int?, val encounter: HealthCareEncounter) {
    init {
        require(HealthProfilePolicy.uuid(operationId) && expectedConcernRevision > 0 && expectedConcernRevision < Int.MAX_VALUE)
        require(expectedEncounterRevision == null || expectedEncounterRevision in 1..expectedConcernRevision)
        require(encounter.revision == expectedConcernRevision + 1)
    }
    fun json() = JSONObject().put("operation", operationId).put("expected_concern", expectedConcernRevision)
        .put("expected_encounter", expectedEncounterRevision ?: JSONObject.NULL).put("encounter", encounter.json())
    companion object {
        fun from(j: JSONObject) = HealthCareEncounterReceipt(j.getString("operation"), j.getInt("expected_concern"),
            j.takeUnless { it.isNull("expected_encounter") }?.getInt("expected_encounter"), HealthCareEncounter.from(j.getJSONObject("encounter")))
    }
}

internal data class HealthCareEncounterPage(val items: List<HealthCareEncounter>, val next: Int?, val concernRevision: Int = 0)

internal object HealthCareEncounterPolicy {
    fun apply(issue: HealthCareConcern, before: HealthCareEncounter?, id: String, details: HealthCareEncounterDraft, now: Long): HealthCareEncounter {
        require(now > 0 && issue.revision < Int.MAX_VALUE)
        require(details.attendedAt == null || details.attendedAt <= now)
        if (before != null && (before.id != id || before.concernId != issue.id)) throw HealthCareConflict()
        return HealthCareEncounter(id, issue.id, issue.revision + 1, if (before != null) before.sourceRecord else issue.assessment.record,
            before?.createdAt ?: now, maxOf(now, before?.updatedAt ?: now, issue.updatedAt), details)
    }
}
