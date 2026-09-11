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
    val catalog = AgentMemorySegmentCatalog(File(root.absolutePath + ".catalog.db"))
    private val files = MemorySegmentFile(root, AgentStorageCipher::encryptBinary, AgentStorageCipher::decryptBinary,
        syncDirectory = ::syncDirectory, register = { id ->
            catalog.register(id)
            syncDirectory(requireNotNull(root.parentFile))
        })

    data class Encoded(val value: String, val segment: String, val bytes: Long)

    fun encode(key: String, value: String, aad: ByteArray): Encoded {
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
        return encodeReference(reference, aad)
    }

    private fun encodeReference(reference: MemorySegmentFile.Reference, aad: ByteArray): Encoded {
        val bytes = reference.bytes()
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, referenceAad(aad)) } finally { bytes.fill(0) }
        return try { Encoded(PREFIX + Base64.encodeToString(encrypted, Base64.NO_WRAP), reference.segment.toString(), reference.length) }
        finally { encrypted.fill(0) }
    }

    fun seal(id: java.util.UUID) = files.seal(id)
    fun size(id: java.util.UUID) = files.size(id)
    fun remove(id: java.util.UUID) = files.remove(id)

    fun relocate(key: String, value: String, aad: ByteArray, expectedSegment: java.util.UUID, expectedBytes: Long,
        checkActive: () -> Unit = {}): Encoded {
        require(key.startsWith(AgentPersonalMemoryRows.PREFIX))
        val reference = reference(value, aad)
        check(reference.segment == expectedSegment) { "Memory segment catalog does not match authenticated reference" }
        check(reference.length == expectedBytes) { "Memory segment catalog length mismatch" }
        return encodeReference(files.relocate(reference, aad, checkActive), aad)
    }

    fun decode(key: String, value: String, aad: ByteArray): String {
        require(key.startsWith(AgentPersonalMemoryRows.PREFIX) && value.startsWith(PREFIX))
        return files.read(reference(value, aad), aad) { input ->
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

    private fun reference(value: String, aad: ByteArray): MemorySegmentFile.Reference {
        require(value.startsWith(PREFIX))
        require(value.length <= 256) { "Invalid memory segment pointer size" }
        val encrypted = Base64.decode(value.removePrefix(PREFIX), Base64.NO_WRAP)
        val bytes = try { AgentStorageCipher.decryptBinary(encrypted, referenceAad(aad)) } finally { encrypted.fill(0) }
        return try { MemorySegmentFile.Reference.parse(bytes) } finally { bytes.fill(0) }
    }

    companion object {
        const val PREFIX = "memory-segment:v1:"
        const val ROW_THRESHOLD = 16_384L
        const val INLINE_CHAR_LIMIT = 8_192
        private fun referenceAad(aad: ByteArray) = "memory-segment-reference:v1\u0000".toByteArray() + aad
        private fun syncDirectory(directory: File) {
            val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
            try {
                check(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)) { "Memory segment sync target is not a directory" }
                Os.fsync(fd)
            } finally { Os.close(fd) }
        }
        fun external(key: String, value: String, largeStore: Boolean): Boolean =
            key.startsWith(AgentPersonalMemoryRows.PREFIX) && (largeStore || value.length >= INLINE_CHAR_LIMIT)
    }
}
