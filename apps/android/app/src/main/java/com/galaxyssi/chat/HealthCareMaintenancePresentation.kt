package com.galaxyssi.chat

internal fun HealthCareMaintenanceGap.titleResource(): Int = when (this) {
    HealthCareMaintenanceGap.TARGET -> R.string.health_maintenance_gap_target
    HealthCareMaintenanceGap.HISTORY -> R.string.health_maintenance_gap_history
    HealthCareMaintenanceGap.COMPARABILITY -> R.string.health_maintenance_gap_comparison
    HealthCareMaintenanceGap.APPLICABILITY -> R.string.health_maintenance_gap_applicability
    HealthCareMaintenanceGap.OPEN_ACTIONS -> R.string.health_maintenance_gap_actions
    HealthCareMaintenanceGap.RECHECK -> R.string.health_maintenance_gap_recheck
    HealthCareMaintenanceGap.PRIORITY -> R.string.health_maintenance_gap_priority
}
