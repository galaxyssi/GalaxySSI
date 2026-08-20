package com.signalasi.chat

internal object SignalASIMqttClientIdentity {
    fun stableClientId(transportEpoch: String): String {
        val identity = runCatching {
            SignalASICrypto.localIdentitySha256().take(16)
        }.getOrDefault("unknown")
        return "signalasi-android-$transportEpoch-$identity"
    }
}
