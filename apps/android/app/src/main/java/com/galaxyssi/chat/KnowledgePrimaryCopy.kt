package com.galaxyssi.chat

import android.content.ContentValues
import java.util.UUID

/** Destination frames precede the catalog checkpoint; replay removes only its unpublished tail. */
internal class KnowledgePrimaryCopy(private val primary: KnowledgePrimaryPartitions) {
    data class Job(val key: String, val source: String, val destination: String, val original: String, val checkpoint: String)

    fun begin(db: KnowledgeSqlite, key: String, source: KnowledgePrimaryPartitions.Reference) {
        val destination = primary.createCopyDestination(db, key)
        val state = KnowledgePrimaryCopyState(UUID.randomUUID().toString().replace("-", "")).validate(source)
        val job = Job(key, source.partition, destination, source.sealed, "")
        db.insertOrThrow("knowledge_primary_copy", null, ContentValues().apply {
            put("id", 1); put("item_key", key); put("source_partition", source.partition)
            put("destination_partition", destination); put("original", source.sealed)
            put("checkpoint", primary.sealCopy(job, state.encode()))
        })
    }

    fun load(db: KnowledgeSqlite): Job? = db.rawQuery("SELECT item_key,source_partition,destination_partition," +
        "substr(original,1,2049),substr(checkpoint,1,8193) FROM knowledge_primary_copy WHERE id=1", null).use {
        if (!it.moveToFirst()) return null
        Job(it.getString(0), it.getString(1), it.getString(2), it.getString(3), it.getString(4)).also { job ->
            require(job.key.matches(Regex("[a-f0-9]{64}")))
            require(job.source.matches(Regex("[a-f0-9]{32}")) && job.destination.matches(Regex("[a-f0-9]{32}")))
            require(job.source != job.destination && job.original.length <= 2048 && job.checkpoint.length <= 8192)
        }
    }

    fun state(job: Job) = KnowledgePrimaryCopyState.decode(primary.openCopy(job))
        .validate(primary.decodeReference(job.key, job.source, job.original))

    fun advance(db: KnowledgeSqlite, checkActive: () -> Unit): Int {
        val job = requireNotNull(load(db))
        val old = primary.decodeReference(job.key, job.source, job.original)
        val state = state(job)
        val current = primary.reference(db, job.key)
        if (current?.sealed != job.original) {
            // A user mutation wins, including a deletion. Never revive the old item from its copy job.
            check(!db.rawQuery("SELECT 1 FROM knowledge_primary_refs WHERE partition_key=? LIMIT 1", arrayOf(job.destination)).use { it.moveToFirst() })
            remove(db, job)
            KnowledgePrimaryCompaction.retire(db, job.destination)
            return 0
        }
        val target = KnowledgePrimaryPartitions.Reference(job.destination, state.entry, old.chunks, old.chars)
        val next = if (state.copied < old.chunks) {
            primary.trimCopy(target, state.copied)
            var bytes = state.copiedBytes
            var hash = state.copiedHash
            val page = primary.framePage(job.key, old, state.copied, FRAME_PAGE, checkActive) { compressed, ordinal ->
                bytes = Math.addExact(bytes, primary.writeCopyFrame(job.key, target, ordinal, compressed))
                hash = KnowledgePrimaryCopyState.chain(hash, ordinal, compressed)
            }
            state.copy(copied = state.copied + page.frames, copiedChars = state.copiedChars + page.chars,
                copiedBytes = bytes, copiedHash = hash).validate(old)
        } else if (state.verified < old.chunks) {
            var hash = state.verifiedHash
            val page = primary.framePage(job.key, target, state.verified, FRAME_PAGE, checkActive) { compressed, ordinal ->
                hash = KnowledgePrimaryCopyState.chain(hash, ordinal, compressed)
            }
            state.copy(verified = state.verified + page.frames, verifiedChars = state.verifiedChars + page.chars,
                verifiedHash = hash).validate(old)
        } else state
        if (next.verified == old.chunks) {
            check(next.copiedHash == next.verifiedHash) { "Primary copy verification digest mismatch" }
            primary.publishReference(db, job.key, old, target)
            remove(db, job)
            return 1
        }
        db.update("knowledge_primary_partitions", ContentValues().apply { put("bytes", next.copiedBytes) },
            "partition_key=?", arrayOf(job.destination))
        changedOne(db)
        db.update("knowledge_primary_copy", ContentValues().apply { put("checkpoint", primary.sealCopy(job, next.encode())) },
            "id=1 AND checkpoint=?", arrayOf(job.checkpoint))
        changedOne(db)
        return 0
    }

    private fun remove(db: KnowledgeSqlite, job: Job) {
        db.delete("knowledge_primary_copy", "id=1 AND checkpoint=?", arrayOf(job.checkpoint))
        changedOne(db)
    }

    companion object {
        const val FRAME_PAGE = 16
        fun pending(db: KnowledgeSqlite) = db.rawQuery("SELECT 1 FROM knowledge_primary_copy LIMIT 1", null).use { it.moveToFirst() }
        fun changedOne(db: KnowledgeSqlite) = db.rawQuery("SELECT changes()", null).use {
            check(it.moveToFirst() && it.getLong(0) == 1L) { "Primary copy publication changed an unexpected number of rows" }
        }
    }
}
