package com.galaxyssi.chat

import java.io.IOException
import kotlinx.coroutines.CancellationException
import okhttp3.Call
import okhttp3.Response

internal fun <T> Call.executeCancellable(
    cancellationToken: AgentNativeToolCancellationToken,
    readResponse: (Response) -> T
): T {
    if (cancellationToken.isCancellationRequested) {
        throw CancellationException("Model tool request cancelled")
    }
    val registration = cancellationToken.invokeOnCancellation(::cancel)
    return try {
        if (cancellationToken.isCancellationRequested) {
            throw CancellationException("Model tool request cancelled")
        }
        execute().use(readResponse)
    } catch (error: IOException) {
        if (cancellationToken.isCancellationRequested) {
            throw CancellationException("Model tool request cancelled").also {
                it.initCause(error)
            }
        }
        throw error
    } finally {
        registration.dispose()
    }
}
