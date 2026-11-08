package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId

internal enum class HealthCareAgendaFilter { TODAY, LATER, REVIEW, RECORDED }

internal data class HealthCareAgendaCursor(val generation: String, val filter: HealthCareAgendaFilter,
    val dayEnd: Long, val due: Long, val concernId: String, val actionId: String)

internal data class HealthCareAgendaItem(val concern: HealthCareConcern, val action: HealthCareAction,
    val reminder: HealthCareReminder?, val bucket: Int, val due: Long) {
    val plannedAt: Long? get() = due.takeUnless { it == Long.MAX_VALUE }
}

internal data class HealthCareAgendaPage(val items: List<HealthCareAgendaItem>, val next: HealthCareAgendaCursor?)

internal object HealthCareAgenda {
    fun dayEnd(now: Long, zone: ZoneId): Long = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        .plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()

    fun item(issue: HealthCareConcern, action: HealthCareAction, reminder: HealthCareReminder?): HealthCareAgendaItem {
        val bucket = when {
            action.state in setOf(HealthCareActionState.DONE, HealthCareActionState.DECLINED) -> 2
            action.state != HealthCareActionState.CONFIRMED ||
                issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) ||
                action.basis != HealthCareFollowUpPolicy.basis(issue) -> 1
            else -> 0
        }
        val current = reminder?.takeIf { it.concernId == issue.id && it.actionId == action.id &&
            it.state != HealthCareReminderState.CANCELLED && it.anchor == HealthCareFollowUpPolicy.anchor(issue, action) }
        return HealthCareAgendaItem(issue, action, current, bucket, current?.dueAt ?: action.dueFrom ?: Long.MAX_VALUE)
    }
}
