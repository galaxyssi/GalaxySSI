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

    fun beginCopy(key: String, value: String, aad: ByteArray, expectedSegment: java.util.UUID, expectedBytes: Long) {
        val source = checkedReference(key, value, aad, expectedSegment, expectedBytes)
        val state = files.beginCopy(source)
        catalog.beginCopy(AgentMemorySegmentCatalog.CopyJob(key, value, source.segment.toString(),
            state.destination.toString(), encodeCopy(state, aad)))
    }

    fun copyState(job: AgentMemorySegmentCatalog.CopyJob, aad: ByteArray): MemorySegmentCopy.State {
        require(job.checkpoint.length <= 512) { "Invalid memory copy checkpoint envelope" }
        val encrypted = Base64.decode(job.checkpoint, Base64.NO_WRAP)
        val bytes = try { AgentStorageCipher.decryptBinary(encrypted, copyAad(aad)) } finally { encrypted.fill(0) }
        val state = try { MemorySegmentCopy.State.parse(bytes) } finally { bytes.fill(0) }
        check(state.source == checkedReference(job.key, job.value, aad, java.util.UUID.fromString(job.source), state.source.length))
        check(state.destination.toString() == job.destination) { "Memory copy destination mismatch" }
        return state
    }

    fun copyStep(state: MemorySegmentCopy.State, aad: ByteArray, checkActive: () -> Unit) =
        files.copyStep(state, aad, 1024 * 1024, checkActive)

    fun checkpointCopy(job: AgentMemorySegmentCatalog.CopyJob, state: MemorySegmentCopy.State, aad: ByteArray): AgentMemorySegmentCatalog.CopyJob {
        val next = job.copy(checkpoint = encodeCopy(state, aad))
        catalog.checkpointCopy(job, next)
        return next
    }

    fun copiedReference(state: MemorySegmentCopy.State, aad: ByteArray): Encoded {
        state.validate()
        check(state.complete) { "Memory copy has not been fully verified" }
        return encodeReference(state.target, aad)
    }

    fun isCopiedReference(value: String, state: MemorySegmentCopy.State, aad: ByteArray): Boolean =
        reference(value, aad) == state.target

    private fun encodeCopy(state: MemorySegmentCopy.State, aad: ByteArray): String {
        val bytes = state.bytes()
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, copyAad(aad)) } finally { bytes.fill(0) }
        return try { Base64.encodeToString(encrypted, Base64.NO_WRAP) } finally { encrypted.fill(0) }
    }

    fun relocate(key: String, value: String, aad: ByteArray, expectedSegment: java.util.UUID, expectedBytes: Long,
        checkActive: () -> Unit = {}): Encoded {
        val reference = checkedReference(key, value, aad, expectedSegment, expectedBytes)
        return encodeReference(files.relocate(reference, aad, checkActive), aad)
    }

    private fun checkedReference(key: String, value: String, aad: ByteArray, expectedSegment: java.util.UUID,
        expectedBytes: Long): MemorySegmentFile.Reference {
        require(key.startsWith(AgentPersonalMemoryRows.PREFIX))
        return reference(value, aad).also {
            check(it.segment == expectedSegment) { "Memory segment catalog does not match authenticated reference" }
            check(it.length == expectedBytes) { "Memory segment catalog length mismatch" }
        }
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
        private fun copyAad(aad: ByteArray) = "memory-segment-copy:v1\u0000".toByteArray() + aad
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
