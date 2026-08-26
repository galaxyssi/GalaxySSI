package com.signalasi.chat

internal object SignalASIMqttClientIdentity {
    fun newClientId(): String = SignalASILinkProtocol.newRouteId()
}
