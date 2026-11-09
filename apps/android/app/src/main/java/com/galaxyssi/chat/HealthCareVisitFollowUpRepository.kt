package com.galaxyssi.chat

import android.content.Context

internal data class HealthCareVisitFollowUpSnapshot(val visit: HealthCareEncounterSnapshot,
    val followUp: HealthCareVisitFollowUp?, val history: HealthCareVisitFollowUpPage)

internal class HealthCareVisitFollowUpRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    private val encounters = HealthCareEncounterRepository(context, names)
    fun load(id: String, encounter: String, before: Int = Int.MAX_VALUE): HealthCareVisitFollowUpSnapshot {
        val visit = encounters.load(id, selectedId = encounter)
        val result = encounters.commit(visit) {
            val value = it.visitFollowUp(encounter)
            if (value != null && value.concernId != id) throw HealthCareConflict()
            HealthCareVisitFollowUpSnapshot(visit, value, it.visitFollowUpHistory(id, encounter, before))
        }
        encounters.commit(visit) { }
        return result
    }
    fun record(snapshot: HealthCareVisitFollowUpSnapshot, input: HealthCareVisitFollowUpInput, operation: String,
        now: Long = System.currentTimeMillis()) = encounters.commit(snapshot.visit) {
        it.recordVisitFollowUp(snapshot.visit.issue.id, snapshot.visit.issue.revision, snapshot.visit.selected!!.id,
            snapshot.visit.selected.revision, snapshot.followUp?.revision, input, operation, now)
    }
    fun delete(snapshot: HealthCareVisitFollowUpSnapshot, now: Long = System.currentTimeMillis()) = encounters.commit(snapshot.visit) {
        it.deleteVisitFollowUp(snapshot.visit.issue.id, snapshot.visit.issue.revision, snapshot.visit.selected!!.id,
            snapshot.followUp?.revision ?: throw HealthCareConflict(), now)
    }
}
