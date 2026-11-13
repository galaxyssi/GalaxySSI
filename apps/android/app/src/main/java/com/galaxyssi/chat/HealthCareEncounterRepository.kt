package com.galaxyssi.chat

import android.content.Context

internal data class HealthCareEncounterSnapshot(val issue: HealthCareConcern, val privacy: HealthPrivacyPolicy,
    val settingsVersion: String, val recordClock: String, val page: HealthCareEncounterPage,
    val selected: HealthCareEncounter? = null, val history: HealthCareEncounterPage? = null,
    val reminder: HealthCareReminder? = null, val canRemind: Boolean = false, val notifications: Boolean = false)

internal class HealthCareEncounterRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    fun load(id: String, before: Int = Int.MAX_VALUE, expectedRevision: Int? = null,
        selectedId: String? = null, historyBefore: Int? = null): HealthCareEncounterSnapshot {
        val permission = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        allowed(permission)
        HealthCareEngine.evaluate(context, names)
        return HealthCareStore(context, names.care).use { store ->
            val issue = store.concern(id) ?: throw HealthCareConflict()
            val clock = HealthRecordStore(context, names.records).use { it.metricVersion(issue.metric) }
            val selected = selectedId?.let { store.encounter(it)?.takeIf { entry -> entry.concernId == id } ?: throw HealthCareConflict() }
            val page = if (selected == null) store.encounters(id, before, expectedRevision = expectedRevision)
                else HealthCareEncounterPage(emptyList(), null, issue.revision)
            val settings = store.settings()
            val result = HealthCareEncounterSnapshot(issue, permission, settings.version, clock, page, selected,
                if (selected != null && historyBefore != null) store.encounterHistory(id, selected.id, historyBefore) else null,
                selected?.let { store.appointmentReminder(it.id) },
                selected != null && HealthCareAppointmentPolicy.allowed(issue, settings, permission) &&
                    HealthCareAppointmentPolicy.available(selected, System.currentTimeMillis()),
                selected != null && HealthReminderStore(context, names.reminders).use { it.settings().notifications } &&
                    HealthReminderWork.systemAllowed(context))
            checkCurrent(result, store, HealthPrivacyStore(context, names.privacy).use { it.policy() })
            result
        }
    }
    fun save(snapshot: HealthCareEncounterSnapshot, id: String, expectedEntry: Int?, draft: HealthCareEncounterDraft,
        operationId: String, now: Long = System.currentTimeMillis()) = commit(snapshot) { store ->
        store.saveEncounter(snapshot.issue.id, snapshot.issue.revision, id, expectedEntry, draft, operationId, now)
    }
    fun delete(snapshot: HealthCareEncounterSnapshot, value: HealthCareEncounter, now: Long = System.currentTimeMillis()) = commit(snapshot) {
        require(value.concernId == snapshot.issue.id)
        it.deleteEncounter(snapshot.issue.id, snapshot.issue.revision, value.id, value.revision, now)
    }
    fun scheduleAppointment(snapshot: HealthCareEncounterSnapshot, at: Long, now: Long = System.currentTimeMillis()) = commit(snapshot) {
        val visit = snapshot.selected ?: throw HealthCareConflict()
        it.scheduleAppointment(snapshot.issue.id, snapshot.issue.revision, visit.id, visit.revision, snapshot.reminder?.token,
            snapshot.privacy, at, now)
    }
    fun cancelAppointment(snapshot: HealthCareEncounterSnapshot, now: Long = System.currentTimeMillis()) = commit(snapshot) {
        val visit = snapshot.selected ?: throw HealthCareConflict()
        val reminder = snapshot.reminder ?: throw HealthCareConflict()
        if (reminder.appointment?.encounter != visit.id || reminder.concernId != snapshot.issue.id) throw HealthCareConflict()
        it.cancelReminder(reminder.storageKey, reminder.token, now)
    }
    private fun allowed(permission: HealthPrivacyPolicy) {
        if (!permission.metrics || !permission.profile) throw HealthAccessBlocked()
    }
    private fun checkCurrent(snapshot: HealthCareEncounterSnapshot, store: HealthCareStore, currentPrivacy: HealthPrivacyPolicy) {
        allowed(snapshot.privacy)
        if (currentPrivacy != snapshot.privacy ||
            store.concern(snapshot.issue.id)?.revision != snapshot.issue.revision || store.settings().version != snapshot.settingsVersion ||
            HealthRecordStore(context, names.records).use { it.metricVersion(snapshot.issue.metric) } != snapshot.recordClock) throw HealthCareConflict()
    }
    internal fun <T> commit(snapshot: HealthCareEncounterSnapshot, operation: (HealthCareStore) -> T): T {
        allowed(snapshot.privacy)
        return HealthPrivacyStore(context, names.privacy).use { privacy -> privacy.withCurrentPolicy(snapshot.privacy) {
            HealthCareStore(context, names.care).use { care -> checkCurrent(snapshot, care, privacy.policy()); operation(care) }
        } }
    }
}
