package com.galaxyssi.glasses

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WifiQrProvisioningTest {
    @Test fun acceptsPhoneQrWithoutChangingCredentials() {
        val qr = JSONObject().put("type", "galaxyssi_wifi_v1")
            .put("ssid", "家庭网络").put("passphrase", "correct horse battery staple")
        val parsed = WifiQrProvisioning.parse(qr.toString())
        assertEquals("家庭网络", parsed.ssid)
        assertEquals("correct horse battery staple", parsed.passphrase)
    }

    @Test fun rejectsOtherQrAndInvalidNetworkCredentials() {
        assertThrows(IllegalArgumentException::class.java) {
            WifiQrProvisioning.parse(JSONObject().put("type", "other")
                .put("ssid", "Home").put("passphrase", "12345678").toString())
        }
        assertThrows(IllegalArgumentException::class.java) {
            WifiQrProvisioning.parse(JSONObject().put("type", "galaxyssi_wifi_v1")
                .put("ssid", "x".repeat(33)).put("passphrase", "12345678").toString())
        }
        assertThrows(IllegalArgumentException::class.java) {
            WifiQrProvisioning.parse(JSONObject().put("type", "galaxyssi_wifi_v1")
                .put("ssid", "Home").put("passphrase", "short").toString())
        }
    }
}
