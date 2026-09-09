package com.galaxyssi.chat

import android.content.ContentValues
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import java.io.Closeable

/** Small statement adapter; callers serialize the connection through AgentKnowledgeDatabase. */
internal class KnowledgeSqlite(path: String) : Closeable {
    private val connection: SQLiteConnection = BundledSQLiteDriver().open(path)
    private val transactions = mutableListOf<Boolean>()
    private var rollbackOnly = false

    fun execSQL(sql: String) { connection.prepare(sql).use { it.step() } }

    fun rawQuery(sql: String, args: Array<String>?): KnowledgeCursor {
        val statement = connection.prepare(sql)
        try {
            args?.forEachIndexed { index, value -> statement.bindText(index + 1, value) }
            return KnowledgeCursor(statement)
        } catch (error: Throwable) { statement.close(); throw error }
    }

    @Suppress("UNUSED_PARAMETER")
    fun insertOrThrow(table: String, nullColumnHack: String?, values: ContentValues) {
        val columns = values.keySet().toList()
        require(columns.isNotEmpty())
        val sql = "INSERT INTO ${identifier(table)} (${columns.joinToString(",", transform = ::identifier)}) " +
            "VALUES (${columns.joinToString(",") { "?" }})"
        connection.prepare(sql).use { statement ->
            columns.forEachIndexed { index, column ->
                bind(statement, index + 1, values[column])
            }
            statement.step()
        }
    }

    fun update(table: String, values: ContentValues, where: String, args: Array<String>) {
        val columns = values.keySet().toList()
        require(columns.isNotEmpty())
        connection.prepare("UPDATE ${identifier(table)} SET " + columns.joinToString(",") { "${identifier(it)}=?" } +
            " WHERE $where").use { statement ->
            columns.forEachIndexed { index, column -> bind(statement, index + 1, values[column]) }
            args.forEachIndexed { index, value -> statement.bindText(columns.size + index + 1, value) }
            statement.step()
        }
    }

    private fun bind(statement: SQLiteStatement, index: Int, value: Any?) = when (value) {
        null -> statement.bindNull(index)
        is String -> statement.bindText(index, value)
        is ByteArray -> statement.bindBlob(index, value)
        is Number -> statement.bindLong(index, value.toLong())
        else -> error("Unsupported knowledge SQL value")
    }

    fun delete(table: String, where: String?, args: Array<String>?) {
        rawQuery("DELETE FROM ${identifier(table)}" + (where?.let { " WHERE $it" } ?: ""), args).use { it.moveToNext() }
    }

    fun beginTransactionNonExclusive() = beginTransaction()
    fun beginTransaction() {
        if (transactions.isEmpty()) { execSQL("BEGIN IMMEDIATE"); rollbackOnly = false }
        transactions.add(false)
    }
    fun setTransactionSuccessful() { check(transactions.isNotEmpty()); transactions[transactions.lastIndex] = true }
    fun endTransaction() {
        check(transactions.isNotEmpty())
        if (!transactions.removeAt(transactions.lastIndex)) rollbackOnly = true
        if (transactions.isEmpty()) {
            try { execSQL(if (rollbackOnly) "ROLLBACK" else "COMMIT") }
            catch (error: Throwable) { runCatching { execSQL("ROLLBACK") }; throw error }
        }
    }
    override fun close() = connection.close()
    private fun identifier(value: String): String {
        require(value.matches(Regex("[a-zA-Z_][a-zA-Z0-9_]*")))
        return value
    }
}

internal class KnowledgeCursor(private val statement: SQLiteStatement) : Closeable {
    fun moveToFirst(): Boolean = statement.step()
    fun moveToNext(): Boolean = statement.step()
    fun getString(index: Int): String = statement.getText(index)
    fun getInt(index: Int): Int = statement.getLong(index).toInt()
    fun getLong(index: Int): Long = statement.getLong(index)
    fun getBlob(index: Int): ByteArray = statement.getBlob(index)
    override fun close() = statement.close()
}
