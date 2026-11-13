package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject

/** Local appointment logistics, independent of clinical actions and model grants. */
internal data class HealthCareAppointmentRef(val encounter: String, val revision: Int) {
    init { require(HealthProfilePolicy.uuid(encounter) && revision > 0) }
    val reminderId get() = id(encounter)
    fun json() = JSONObject().put("encounter", encounter).put("revision", revision)
    companion object {
        fun id(encounter: String) = UUID.nameUUIDFromBytes("appointment:$encounter".toByteArray(Charsets.UTF_8)).toString()
        fun from(j: JSONObject) = HealthCareAppointmentRef(j.getString("encounter"), j.getInt("revision"))
    }
}

internal object HealthCareAppointmentPolicy {
    fun available(visit: HealthCareEncounter, now: Long): Boolean =
        visit.details.state in setOf(HealthCareEncounterState.PLANNED, HealthCareEncounterState.BOOKING_RECORDED) &&
            visit.details.plannedAt?.let { it > now } == true

    fun allowed(issue: HealthCareConcern, settings: HealthCareSettings, privacy: HealthPrivacyPolicy): Boolean =
        issue.open && issue.stage != HealthCareStage.PAUSED && settings.enabled && privacy.metrics && privacy.profile

    private fun anchor(issue: HealthCareConcern, ref: HealthCareAppointmentRef) =
        AgentNativeJsonCodec.sha256(mapOf("concern" to issue.id, "appointment" to ref.json().toString()))

    fun schedule(issue: HealthCareConcern, visit: HealthCareEncounter, settings: HealthCareSettings,
        privacy: HealthPrivacyPolicy, at: Long, now: Long): HealthCareReminder {
        if (visit.concernId != issue.id || !available(visit, now) || !allowed(issue, settings, privacy)) throw HealthCareConflict()
        require(now > 0 && at > now && at < visit.details.plannedAt!!)
        val ref = HealthCareAppointmentRef(visit.id, visit.revision)
        return HealthCareReminder(ref.reminderId, issue.id, UUID.randomUUID().toString(), anchor(issue, ref),
            privacy.version, at, now, appointment = ref)
    }

    fun current(value: HealthCareReminder, issue: HealthCareConcern, visit: HealthCareEncounter?,
        settings: HealthCareSettings, privacy: HealthPrivacyPolicy, now: Long): Boolean {
        val ref = value.appointment ?: return false
        return visit != null && visit.id == ref.encounter && visit.revision == ref.revision && visit.concernId == issue.id &&
            value.concernId == issue.id && value.privacyVersion == privacy.version && value.anchor == anchor(issue, ref) &&
            available(visit, now) && value.dueAt < visit.details.plannedAt!! && allowed(issue, settings, privacy)
    }
}
