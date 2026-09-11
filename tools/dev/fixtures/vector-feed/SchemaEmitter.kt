package com.galaxyssi.chat

/** Compiles the production schema verbatim without Android, emitting a structured SQL stream. */
internal class KnowledgeSqlite {
    fun execSQL(sql: String) { println(java.util.Base64.getEncoder().encodeToString(sql.toByteArray(Charsets.UTF_8))) }
}
fun main() { KnowledgeVectorChangeSchema.create(KnowledgeSqlite()) }
