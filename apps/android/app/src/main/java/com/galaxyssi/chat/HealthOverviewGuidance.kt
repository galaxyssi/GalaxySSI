package com.galaxyssi.chat

import java.time.LocalDate
import java.time.Period

internal object HealthOverviewGuidance {
    enum class SleepBand { ADULT_UNSPECIFIED, MONTHS_0_3, MONTHS_4_12, YEARS_1_2, YEARS_3_5, YEARS_6_12,
        YEARS_13_17, YEARS_18_60, YEARS_61_64, YEARS_65_PLUS }

    fun ageOn(birthDate: LocalDate?, day: LocalDate): Period? =
        birthDate?.takeUnless { it > day }?.let { Period.between(it, day) }

    fun adultReference(age: Period?) = age == null || age.years >= 18

    fun sleep(age: Period?): SleepBand = when {
        age == null -> SleepBand.ADULT_UNSPECIFIED
        age.years == 0 && age.months <= 3 -> SleepBand.MONTHS_0_3
        age.years == 0 -> SleepBand.MONTHS_4_12
        age.years <= 2 -> SleepBand.YEARS_1_2
        age.years <= 5 -> SleepBand.YEARS_3_5
        age.years <= 12 -> SleepBand.YEARS_6_12
        age.years <= 17 -> SleepBand.YEARS_13_17
        age.years <= 60 -> SleepBand.YEARS_18_60
        age.years <= 64 -> SleepBand.YEARS_61_64
        else -> SleepBand.YEARS_65_PLUS
    }

    const val MAX_STEP_GOAL = 1_000_000

    fun stepProgress(goal: Int?, steps: Long?, freshness: HealthOverviewFreshness, permitted: Boolean): Double? {
        if (!permitted || freshness != HealthOverviewFreshness.RECENT ||
            goal == null || goal !in 1..MAX_STEP_GOAL || steps == null || steps < 0) return null
        return steps.toDouble() / goal
    }
}
