package com.galaxyssi.glasses

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import org.json.JSONObject

/** The QR is an intentional, short-range transfer from the phone screen to the glasses camera. */
internal data class WifiQrProvisioning(val ssid: String, val passphrase: String) {
    companion object {
        fun parse(raw: String): WifiQrProvisioning {
            require(raw.length <= 1024)
            val source = JSONObject(raw)
            require(source.optString("type") == "galaxyssi_wifi_v1")
            val ssid = source.getString("ssid")
            val passphrase = source.getString("passphrase")
            require(ssid.isNotBlank() && ssid.toByteArray(Charsets.UTF_8).size <= 32)
            require(passphrase.length in 8..63 && passphrase.all { it.code in 32..126 })
            return WifiQrProvisioning(ssid, passphrase)
        }
    }

    fun suggest(context: Context): Boolean {
        val wifi = context.getSystemService(WifiManager::class.java)
        val suggestion = WifiNetworkSuggestion.Builder().setSsid(ssid).setWpa2Passphrase(passphrase).build()
        return wifi.addNetworkSuggestions(listOf(suggestion)) == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS
    }
}
