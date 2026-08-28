package com.signalasi.chat

import android.app.AlertDialog
import android.widget.Toast
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

internal enum class PeerMessageAction {
    COPY,
    TRANSCRIBE,
    DELETE
}

internal object PeerMessageActionPolicy {
    fun voiceAttachment(message: ChatMessage): PeerChatAttachment? =
        message.attachments.firstOrNull { it.mimeType.startsWith("audio/", ignoreCase = true) }

    fun actions(message: ChatMessage): List<PeerMessageAction> =
        if (voiceAttachment(message) != null) {
            listOf(PeerMessageAction.TRANSCRIBE, PeerMessageAction.DELETE)
        } else {
            listOf(PeerMessageAction.COPY, PeerMessageAction.DELETE)
        }
}

internal object PeerVoiceTranscriptionPolicy {
    fun returnsTextWithoutCommandExecution(purpose: String): Boolean =
        purpose == PEER_VOICE_TRANSCRIPTION_PURPOSE
}

internal fun MainActivity.showPeerVoiceActions(contact: Contact, message: ChatMessage) {
    val attachment = PeerMessageActionPolicy.voiceAttachment(message) ?: return
    AlertDialog.Builder(this)
        .setItems(
            arrayOf(
                getString(R.string.peer_voice_transcribe),
                getString(R.string.message_delete_title)
            )
        ) { dialog, which ->
            when (which) {
                0 -> transcribePeerVoiceMessage(contact.id, message.id, attachment)
                1 -> messages[contact.id]
                    ?.indexOfFirst { it.id == message.id }
                    ?.takeIf { it >= 0 }
                    ?.let { position ->
                        deleteMessageAt(contact.id, position)
                        Toast.makeText(this, getString(R.string.toast_deleted), Toast.LENGTH_SHORT).show()
                    }
            }
            dialog.dismiss()
        }
        .show()
}

internal fun MainActivity.transcribePeerVoiceMessage(
    contactId: String,
    messageId: Long,
    attachment: PeerChatAttachment
) {
    val message = messages[contactId]?.firstOrNull { it.id == messageId } ?: return
    if (message.voiceTranscriptionPending) return
    updatePeerVoiceTranscription(contactId, messageId, pending = true)

    voiceAssistantScope.launch(Dispatchers.IO) {
        val decoded = runCatching {
            val source = attachment.resolvedUri(this@transcribePeerVoiceMessage)
                ?: error(getString(R.string.voice_file_missing))
            val encoded = contentResolver.openInputStream(source)?.use { it.readBytes() }
                ?: error(getString(R.string.voice_file_missing))
            LocalWhisperAsr.decodeAudioBytesToPcm16(
                encoded,
                attachment.name.substringAfterLast('.', missingDelimiterValue = "")
            )
        }
        val pcm = decoded.getOrElse { error ->
            runOnUiThread {
                updatePeerVoiceTranscription(contactId, messageId, pending = false)
                Toast.makeText(
                    this@transcribePeerVoiceMessage,
                    error.message ?: getString(R.string.peer_voice_transcription_failed),
                    Toast.LENGTH_LONG
                ).show()
            }
            return@launch
        }
        runOnUiThread {
            if (isDestroyed) {
                pcm.wipeSensitive()
                return@runOnUiThread
            }
            val scratch = File(cacheDir, "peer-voice-transcription-$messageId.scratch").apply { delete() }
            runCatching {
                transcribeLocally(
                    sourceFile = scratch,
                    traceId = "peer-voice-${messageId}-${UUID.randomUUID()}",
                    pcmSamples = pcm,
                    sampleRateHz = 16_000,
                    purpose = PEER_VOICE_TRANSCRIPTION_PURPOSE,
                    onSuccess = { transcript ->
                        pcm.wipeSensitive()
                        updatePeerVoiceTranscription(
                            contactId,
                            messageId,
                            pending = false,
                            transcript = transcript.trim()
                        )
                    },
                    onFailure = {
                        pcm.wipeSensitive()
                        updatePeerVoiceTranscription(contactId, messageId, pending = false)
                    }
                )
            }.onFailure { error ->
                pcm.wipeSensitive()
                updatePeerVoiceTranscription(contactId, messageId, pending = false)
                Toast.makeText(
                    this@transcribePeerVoiceMessage,
                    error.message ?: getString(R.string.peer_voice_transcription_failed),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }
}

private fun MainActivity.updatePeerVoiceTranscription(
    contactId: String,
    messageId: Long,
    pending: Boolean,
    transcript: String? = null
) {
    val contactMessages = messages[contactId] ?: return
    val message = contactMessages.firstOrNull { it.id == messageId } ?: return
    message.voiceTranscriptionPending = pending
    if (transcript != null) {
        message.voiceTranscript = transcript
        saveChatHistory(message)
    }
    if (chatPage.visibility == android.view.View.VISIBLE && selectedContact?.id == contactId) {
        val position = currentMessages.indexOfFirst { it.id == messageId }
        if (position >= 0) messageAdapter?.syncMessages()
    }
}
