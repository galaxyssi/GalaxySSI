package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.File
import java.util.UUID

internal object AgentVoiceScreenFrameCapture {
    /** Copies one newly acquired frame; no background polling or durable plaintext bitmap. */
    suspend fun capture(context: Context, startCapture: () -> Unit): File {
        val ready = CompletableDeferred<Unit>()
        val lock = Any()
        val requestedAt = SystemClock.elapsedRealtimeNanos()
        var accepting = true
        var bitmap: Bitmap? = null
        val listener = AgentScreenFrameListener { frame, acquiredAt ->
            synchronized(lock) {
                if (accepting && acquiredAt >= requestedAt && bitmap == null) {
                    runCatching { checkNotNull(frame.copy(Bitmap.Config.ARGB_8888, false)) }
                        .onSuccess { bitmap = it; ready.complete(Unit) }
                        .onFailure { ready.completeExceptionally(it) }
                }
            }
        }
        val file = File(context.cacheDir, "voice-screen-capture/${UUID.randomUUID()}.jpg")
        try {
            AgentScreenCaptureService.addFrameListener(listener)
            startCapture()
            withTimeout(8_000) { ready.await() }
            val captured = synchronized(lock) { checkNotNull(bitmap) }
            withContext(Dispatchers.IO) {
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
                file.outputStream().use { check(captured.compress(Bitmap.CompressFormat.JPEG, 92, it)) }
            }
            currentCoroutineContext().ensureActive()
            return file
        } catch (error: Throwable) {
            file.delete()
            throw error
        } finally {
            AgentScreenCaptureService.removeFrameListener(listener)
            synchronized(lock) { accepting = false; bitmap?.recycle(); bitmap = null }
        }
    }
}
