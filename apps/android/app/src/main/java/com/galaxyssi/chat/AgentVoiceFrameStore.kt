package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

internal data class StoredVoiceVisualFrame(val file: File, val attachment: AgentInputAttachment)

internal enum class AgentVoiceFrameSource { CAMERA, SCREEN }

internal object AgentVoiceFrameStore {
    /** Consumes the temporary JPEG; only the durable local attachment survives success. */
    suspend fun persist(context: Context, source: File, kind: AgentVoiceFrameSource = AgentVoiceFrameSource.CAMERA): StoredVoiceVisualFrame {
        val id = UUID.randomUUID().toString()
        val directory = if (kind == AgentVoiceFrameSource.SCREEN) "voice-screen" else "voice-camera"
        val target = File(context.filesDir, "agent-rich-output-v2/$directory/$id.sasie")
        try {
            val length = withContext(Dispatchers.IO) {
                check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
                val bytes = source.length()
                check(bytes > 0)
                AttachmentLocalStore.storeFile(source, target)
                bytes
            }
            currentCoroutineContext().ensureActive()
            val name = context.getString(if (kind == AgentVoiceFrameSource.SCREEN)
                R.string.voice_call_screen_frame_name else R.string.voice_call_camera_frame_name)
            return StoredVoiceVisualFrame(target, AgentInputAttachment(
                id = id,
                uri = LocalAttachmentUris.forFile(context, target, name, "image/jpeg"),
                displayName = name, mimeType = "image/jpeg", sizeBytes = length
            ))
        } catch (error: Throwable) {
            target.delete()
            throw error
        } finally { source.delete() }
    }
}
