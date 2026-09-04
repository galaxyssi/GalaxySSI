package com.galaxyssi.chat

internal object ConnectorControlMessagePolicy {
    fun isSilentStatus(type: String): Boolean = type == "connector_status"
}
