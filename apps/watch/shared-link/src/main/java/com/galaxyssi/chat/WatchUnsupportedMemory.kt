@file:Suppress("UNUSED_PARAMETER")

package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * Compile-time boundary for the phone storage engine's optional personal-memory
 * extension. Watch databases use inline encrypted records only. Any attempt to
 * open the phone memory store or decode its segmented records fails explicitly;
 * no phone memory indexing, backups, maintenance, or runtime enters this module.
 */
private fun unsupportedMemory(): Nothing =
    throw UnsupportedOperationException("Personal-memory segments are unavailable on the watch")

internal object AgentMemoryStorage {
    const val DATABASE = "galaxyssi_agent_memory_v2"
}

internal object AgentPersonalMemoryRows {
    const val PREFIX = "personal-memory:v3:row:"
}

internal class MemorySegmentAccess(path: File) {
    fun <T> readWrite(block: () -> T): T = unsupportedMemory()
    fun <T> maintenance(block: () -> T): T = unsupportedMemory()
    fun <T : Any> tryMaintenance(block: () -> T): T? = unsupportedMemory()
}

internal class AgentMemoryPayloadSegments(root: File) {
    data class Encoded(val value: String, val segment: String, val bytes: Long)
    fun encode(key: String, value: String, aad: ByteArray): Encoded = unsupportedMemory()
    fun decode(key: String, value: String, aad: ByteArray): String = unsupportedMemory()

    companion object {
        const val PREFIX = "memory-segment:v1:"
        fun external(key: String, value: String, largeStore: Boolean): Boolean = unsupportedMemory()
    }
}

internal class AgentMemorySegmentMaintenance(sql: SQLiteDatabase,
    segments: AgentMemoryPayloadSegments, aad: (String) -> ByteArray) {
    data class Result(val visited: Int, val moved: Int, val removed: Int,
        val reclaimedBytes: Long, val cycleComplete: Boolean)
    fun run(maxSegments: Int, maxRows: Int, checkActive: () -> Unit = {}): Result = unsupportedMemory()
}
