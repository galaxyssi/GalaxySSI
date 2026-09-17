package com.galaxyssi.watch

import okhttp3.Call
import java.io.IOException

/** Owns all stages of one turn so Stop also cancels search and prevents the next request. */
class WatchApiOperation {
    private val webCancellation = com.galaxyssi.chat.AgentNativeToolCancellationSource()
    val webToken get() = webCancellation.token
    private var cancelled = false
    private var expired = false
    private var current: Call? = null
    @Synchronized fun attach(call: Call): Call {
        if (cancelled) { call.cancel(); throw IOException("Cancelled") }
        current = call
        return call
    }
    @Synchronized fun cancel() { cancelled = true; expired = false; current?.cancel(); webCancellation.cancel() }
    @Synchronized fun expire() {
        if (cancelled) return // A late deadline must never undo the user's Stop.
        cancelled = true; expired = true; current?.cancel(); webCancellation.cancel()
    }
    @Synchronized fun permitsEvidenceFallback() = !cancelled || expired
    @Synchronized fun checkActive() {
        if (expired) throw ApiFailure(R.string.web_budget_exhausted)
        if (cancelled) throw IOException("Cancelled")
    }
}
