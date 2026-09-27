package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.os.Looper
import android.os.SystemClock
import android.media.MediaMetadataRetriever
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

internal object PhoneScreenRecording {
    private class Pending {
        val done = CountDownLatch(1)
        @Volatile var file: File? = null
        @Volatile var error: String = ""
    }
    private val pending = ConcurrentHashMap<String, Pending>()
    private val active = AtomicReference<String?>(null)

    fun record(context: Context, seconds: Int, invocation: AgentNativeToolInvocation): File {
        check(Looper.myLooper() != Looper.getMainLooper())
        val id = UUID.randomUUID().toString()
        check(active.compareAndSet(null, id)) { "A screen recording is already in progress" }
        val result = Pending().also { pending[id] = it }
        val duration = seconds.coerceIn(1, 120)
        try {
            invocation.reportProgress("recording_consent", "Waiting for Android screen recording consent")
            context.startActivity(Intent(context, PhoneScreenRecordingActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("recording_id", id).putExtra("duration_seconds", duration))
            val deadline = SystemClock.elapsedRealtime() + (duration + 60L) * 1_000L
            while (!result.done.await(200L, TimeUnit.MILLISECONDS)) {
                invocation.checkpoint()
                PhoneAssistantTaskControl.checkpoint(invocation.context.turnId) { invocation.isCancellationRequested }
                check(SystemClock.elapsedRealtime() < deadline) { "Screen recording timed out" }
            }
            invocation.checkpoint()
            val file = requireNotNull(result.file?.takeIf { it.isFile && it.length() > 0 }) {
                result.error.ifBlank { "No video was recorded" }
            }
            val metadata = MediaMetadataRetriever()
            try {
                metadata.setDataSource(file.absolutePath)
                check((metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) > 0) {
                    "Recorded video is not playable"
                }
            } finally { metadata.release() }
            return file
        } finally {
            pending.remove(id)
            active.compareAndSet(id, null)
            PhoneScreenRecordingService.stopIfActive(id)
        }
    }

    fun isPending(id: String): Boolean = pending.containsKey(id)
    fun complete(id: String, file: File? = null, error: String = "") {
        pending[id]?.let { result ->
            synchronized(result) {
                if (result.done.count == 0L) return
                result.file = file
                result.error = error
                result.done.countDown()
            }
        }
    }
}
