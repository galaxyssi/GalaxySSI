package com.galaxyssi.chat

internal object ConnectorControlMessagePolicy {
    private val SILENT_CONTROL_TYPES = setOf(
        "connector_status",
        "desktop_control_authorizations",
        "desktop_control_authorization_changed",
        "desktop_executor_event",
        "desktop_action_receipt"
    )

    fun isSilentStatus(type: String): Boolean = type in SILENT_CONTROL_TYPES
}
