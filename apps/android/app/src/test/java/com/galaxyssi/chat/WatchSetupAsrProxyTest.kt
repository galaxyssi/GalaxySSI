package com.galaxyssi.chat

import org.junit.Assert.assertThrows
import org.junit.Test

class WatchSetupAsrProxyTest {
    private val token = "0123456789abcdef0123456789abcdef"

    @Test fun acceptsOnlyHttpsTranscribeEndpointAndStrongToken() {
        WatchSetupAsrProxy.validate("https://speech.example/transcribe", token)
        assertThrows(IllegalArgumentException::class.java) {
            WatchSetupAsrProxy.validate("http://speech.example/transcribe", token)
        }
        assertThrows(IllegalArgumentException::class.java) {
            WatchSetupAsrProxy.validate("https://speech.example/transcribe?token=secret", token)
        }
        assertThrows(IllegalArgumentException::class.java) {
            WatchSetupAsrProxy.validate("https://speech.example/transcribe", "short")
        }
    }
}
