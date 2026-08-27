package com.signalasi.chat

internal object ConnectorControlMessagePolicy {
    fun isSilentStatus(type: String): Boolean = type == "connector_status"
}
