package com.galaxyssi.chat

import android.content.Context
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException

/** Per-operation chunked records share the encrypted Run Kernel ledger, not a growing JSON row. */
class EncryptedAgentModelLoopJournal internal constructor(context: Context, private val store: AgentRunEventStore) :
    AgentModelLoopJournal {
    constructor(context: Context) : this(context.applicationContext, AgentRunEventStore(context))
    private val directory = File(context.noBackupFilesDir, "model-loop-leases")
    private fun run(scope: AgentModelLoopScope, operation: String) =
        "model-loop:" + scope.digest + ":" + AgentNativeJsonCodec.sha256(operation)
    private fun exists(runId: String) = store.containsIdempotencyKey(runId, "$runId:committed") ||
        store.containsIdempotencyKey(runId, "$runId:chunk:0")
    override fun hasRecords(scope: AgentModelLoopScope) = checked { exists(run(scope, "initial")) }

    override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T {
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create model loop lease directory" }
        RandomAccessFile(File(directory, scope.digest + ".lock"), "rw").use { file ->
            val lock = try { file.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
                ?: throw AgentModelLoopRecoveryException("model_loop_busy")
            try { return block(Records(scope)) } finally { lock.release() }
        }
    }

    private inner class Records(private val scope: AgentModelLoopScope) : AgentModelLoopRecords {
        private fun run(operation: String) = run(scope, operation)

        override fun read(operation: String): String? = checked {
            val last = store.latestEvent(run(operation)) ?: run {
                check(!exists(run(operation))) { "model_loop_record_unreadable" }
                return@checked null
            }
            check(last.type == AgentRunControlEventType.RUN_COMPLETED && last.payload["scope"] == scope.value() &&
                last.payload["operation"] == operation) { "model_loop_record_binding_invalid" }
            val count = (last.payload["chunks"] as? Number)?.toInt() ?: error("model_loop_chunks_missing")
            var sequence = 0L
            var index = 0
            val json = buildString {
                while (sequence < last.sequence) {
                    val page = store.eventsPage(last.runId, sequence, 64)
                    check(page.isNotEmpty()) { "model_loop_record_incomplete" }
                    page.filter { it.type == AgentRunControlEventType.CHECKPOINT_SAVED }.forEach {
                        check((it.payload["index"] as? Number)?.toInt() == index++) { "model_loop_chunk_order" }
                        append(it.payload["chunk"] as? String ?: error("model_loop_chunk_missing"))
                    }
                    sequence = page.last().sequence
                }
            }
            check(index == count && count > 0 && AgentNativeJsonCodec.sha256(json) == last.payload["sha256"]) {
                "model_loop_record_integrity_invalid"
            }
            json
        }

        override fun write(operation: String, json: String) = checked {
            read(operation)?.let {
                check(it == json) { "model_loop_record_changed" }
                return@checked
            }
            val chunks = buildList {
                var offset = 0
                while (offset < json.length) {
                    var end = minOf(offset + 24 * 1024, json.length)
                    if (end < json.length && json[end - 1].isHighSurrogate() && json[end].isLowSurrogate()) end--
                    add(json.substring(offset, end)); offset = end
                }
            }
            check(chunks.isNotEmpty()) { "model_loop_empty_record" }
            store.appendNextAll(chunks.mapIndexed { index, chunk ->
                event(operation, "chunk:$index", AgentRunControlEventType.CHECKPOINT_SAVED,
                    mapOf("index" to index, "chunk" to chunk))
            } + event(operation, "committed", AgentRunControlEventType.RUN_COMPLETED,
                mapOf("chunks" to chunks.size, "sha256" to AgentNativeJsonCodec.sha256(json))))
            check(read(operation) == json) { "model_loop_record_not_committed" }
        }

        private fun event(operation: String, suffix: String, type: AgentRunControlEventType,
            payload: Map<String, Any>) = AgentRunControlEvent(
            eventId = "${run(operation)}:$suffix", idempotencyKey = "${run(operation)}:$suffix", runId = run(operation),
            clientRouteId = "local", conversationId = scope.conversation, goalId = scope.task,
            taskId = scope.task, turnId = scope.turn, actionId = scope.loop, messageId = "",
            agentId = "model-loop", deviceId = "local", sequence = 0, type = type,
            payload = payload + mapOf("scope" to scope.value(), "operation" to operation,
                "snapshot_kind" to "model_loop_record", "recovery_mode" to "observation_only"))
    }

    private inline fun <T> checked(block: () -> T): T = try { block() }
    catch (error: AgentModelLoopRecoveryException) { throw error }
    catch (error: Exception) { throw AgentModelLoopRecoveryException("model_loop_journal_unavailable", error) }
}
