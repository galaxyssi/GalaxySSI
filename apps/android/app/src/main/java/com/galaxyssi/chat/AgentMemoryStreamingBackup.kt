package com.galaxyssi.chat

import android.content.Context
import java.io.File

internal object AgentMemoryStreamingBackup {
    fun export(context: Context, file: File, password: CharArray): Long =
        StreamingBackupArchive.write(file, password) { EncryptedAgentMemoryDeletionIndex(context).exportRecords(it) }

    fun restore(context: Context, file: File, password: CharArray) {
        MemoryBackupStaging(context).use { stage ->
            StreamingBackupArchive.read(file, password, stage::accept)
            stage.validateArchive()
            EncryptedAgentMemoryDeletionIndex(context).restoreRecords(stage)
        }
    }
}
