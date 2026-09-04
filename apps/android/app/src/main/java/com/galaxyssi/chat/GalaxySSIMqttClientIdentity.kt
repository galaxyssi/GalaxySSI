package com.galaxyssi.chat

internal object GalaxySSIMqttClientIdentity {
    fun newClientId(): String = GalaxySSILinkProtocol.newRouteId()
}
