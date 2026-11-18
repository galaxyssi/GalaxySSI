package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId

internal fun healthActivityStepDay(ledger: HealthPhoneStepLedger?, today: LocalDate): HealthActivityDay? =
    ledger?.takeIf { it.day == today && (it.counter != null || it.total > 0) }?.let {
        HealthActivityDay(HealthActivityKind.STEPS, today, it.total)
    }

internal fun healthActivityCyclingDay(state: HealthCyclingState?, wall: Long, zone: ZoneId): HealthActivityDay? {
    if (state == null) return null
    val today = HealthCyclingLedger.localDate(wall, zone)
    val total = state.ledger.today(wall, zone)
    if (!state.enabled && today !in state.ledger.days && total == 0L) return null
    // The active contribution is display-only: departure evidence may still revise its end.
    return HealthActivityDay(HealthActivityKind.CYCLING, today, total)
}
