package com.galaxyssi.chat

import android.system.Os
import android.system.OsConstants
import android.util.Base64
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.nio.charset.CodingErrorAction

/** Value separation for personal-memory rows; SQLite keeps the authenticated commit reference. */
internal class AgentMemoryPayloadSegments(root: File) {
    private val files = MemorySegmentFile(root, AgentStorageCipher::encryptBinary, AgentStorageCipher::decryptBinary,
        syncDirectory = { directory ->
            val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
            try {
                check(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)) { "Memory segment sync target is not a directory" }
                Os.fsync(fd)
            } finally { Os.close(fd) }
        })

    fun encode(key: String, value: String, aad: ByteArray): String {
        require(key.startsWith(AgentPersonalMemoryRows.PREFIX))
        val reference = files.append(aad) { output ->
            val records = BackupRecordStream.Writer(output)
            records.record("personal-memory", key) { payload ->
                val encoder = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                OutputStreamWriter(payload, encoder).use { it.write(value) }
            }
            records.finish()
        }
        val bytes = reference.bytes()
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, referenceAad(aad)) } finally { bytes.fill(0) }
        return try { PREFIX + Base64.encodeToString(encrypted, Base64.NO_WRAP) } finally { encrypted.fill(0) }
    }

    fun decode(key: String, value: String, aad: ByteArray): String {
        require(key.startsWith(AgentPersonalMemoryRows.PREFIX) && value.startsWith(PREFIX))
        require(value.length <= 256) { "Invalid memory segment pointer size" }
        val encrypted = Base64.decode(value.removePrefix(PREFIX), Base64.NO_WRAP)
        val bytes = try { AgentStorageCipher.decryptBinary(encrypted, referenceAad(aad)) } finally { encrypted.fill(0) }
        val reference = try { MemorySegmentFile.Reference.parse(bytes) } finally { bytes.fill(0) }
        return files.read(reference, aad) { input ->
            var result: String? = null
            val count = BackupRecordStream.read(input) { section, recordKey, payload ->
                check(section == "personal-memory" && recordKey == key && result == null) { "Memory segment identity mismatch" }
                val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                result = InputStreamReader(payload, decoder).use { it.readText() }
            }
            check(count == 1L) { "Memory segment record count mismatch" }
            checkNotNull(result)
        }
    }

    companion object {
        const val PREFIX = "memory-segment:v1:"
        const val ROW_THRESHOLD = 16_384L
        const val INLINE_CHAR_LIMIT = 8_192
        private fun referenceAad(aad: ByteArray) = "memory-segment-reference:v1\u0000".toByteArray() + aad
        fun external(key: String, value: String, largeStore: Boolean): Boolean =
            key.startsWith(AgentPersonalMemoryRows.PREFIX) && (largeStore || value.length >= INLINE_CHAR_LIMIT)
    }
}
