package com.galaxyssi.chat

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import java.io.Closeable

/** Connection-confined compiled SQL only; results and bindings are cleared before reuse. */
internal class KnowledgeStatementPool(private val connection: SQLiteConnection, private val capacity: Int = 32,
    private val maxSqlChars: Int = 64 * 1024) : Closeable {
    data class Stats(val prepared: Long, val reused: Long, val evicted: Long, val idle: Int, val sqlChars: Int)
    private val idle = linkedMapOf<String, SQLiteStatement>()
    private val active = linkedSetOf<KnowledgeStatementLease>()
    private var closed = false
    private var prepared = 0L
    private var reused = 0L
    private var evicted = 0L
    private var sqlChars = 0

    init { require(capacity >= 0 && maxSqlChars >= 0) }
    fun stats() = Stats(prepared, reused, evicted, idle.size, sqlChars)

    fun acquire(sql: String): KnowledgeStatementLease {
        check(!closed) { "Knowledge connection was closed" }
        val statement = idle.remove(sql)?.also { sqlChars -= sql.length; reused++ }
            ?: connection.prepare(sql).also { prepared++ }
        return KnowledgeStatementLease(sql, statement, ::release).also { active.add(it) }
    }

    private fun release(lease: KnowledgeStatementLease, statement: SQLiteStatement, failed: Boolean) {
        check(active.remove(lease))
        if (closed || failed || capacity == 0 || lease.sql.length > maxSqlChars) { statement.close(); return }
        try {
            // reset releases read locks/results; clearBindings releases all bound values.
            statement.reset()
            statement.clearBindings()
        } catch (failure: Throwable) {
            try { statement.close() } catch (cleanup: Throwable) { failure.addSuppressed(cleanup) }
            throw failure
        }
        try {
            idle.remove(lease.sql)?.let { sqlChars -= lease.sql.length; evicted++; it.close() }
            while (idle.size >= capacity || sqlChars + lease.sql.length > maxSqlChars) {
                val first = idle.entries.first()
                idle.remove(first.key); sqlChars -= first.key.length; evicted++; first.value.close()
            }
            idle[lease.sql] = statement
            sqlChars += lease.sql.length
        } catch (failure: Throwable) {
            try { statement.close() } catch (cleanup: Throwable) { failure.addSuppressed(cleanup) }
            throw failure
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        var failure: Throwable? = null
        fun attempt(block: () -> Unit) {
            try { block() } catch (error: Throwable) { if (failure == null) failure = error else failure!!.addSuppressed(error) }
        }
        active.toList().forEach { lease -> attempt { lease.close() } }
        idle.values.forEach { statement -> attempt { statement.close() } }
        idle.clear(); sqlChars = 0
        failure?.let { throw it }
    }
}

internal class KnowledgeStatementLease(val sql: String, private val statement: SQLiteStatement,
    private val release: (KnowledgeStatementLease, SQLiteStatement, Boolean) -> Unit) : Closeable {
    private var closed = false
    private var failed = false
    fun <T> access(block: (SQLiteStatement) -> T): T {
        check(!closed) { "Knowledge statement was closed" }
        return try { block(statement) } catch (failure: Throwable) { failed = true; throw failure }
    }
    override fun close() {
        if (closed) return
        closed = true
        release(this, statement, failed)
    }
}
