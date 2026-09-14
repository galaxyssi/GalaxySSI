package com.galaxyssi.watch

import okhttp3.Call
import java.io.IOException

/** Owns all stages of one turn so Stop also cancels search and prevents the next request. */
class WatchApiOperation {
    private val webCancellation = com.galaxyssi.chat.AgentNativeToolCancellationSource()
    val webToken get() = webCancellation.token
    private var cancelled = false
    private var current: Call? = null
    @Synchronized fun attach(call: Call): Call {
        if (cancelled) { call.cancel(); throw IOException("Cancelled") }
        current = call
        return call
    }
    @Synchronized fun cancel() { cancelled = true; current?.cancel(); webCancellation.cancel() }
    @Synchronized fun checkActive() { if (cancelled) throw IOException("Cancelled") }
}
