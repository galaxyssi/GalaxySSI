package com.galaxyssi.chat

import java.net.URI

/** The phone validates proxy settings before sending them over the verified setup channel. */
internal object WatchSetupAsrProxy {
    fun validate(endpoint: String, token: String): Pair<String, String> {
        val uri = URI(endpoint)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null && uri.path == "/transcribe")
        require(token.length in 32..256 && token.all { it.code in 33..126 })
        return endpoint to token
    }
}
