package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import java.io.Closeable
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import org.json.JSONArray
import org.json.JSONObject

/** Bounded encrypted rows; plaintext text and titles never enter SQLite indexes. */
internal class AgentKnowledgeDatabase private constructor(
    private val context: Context, private val name: String, private val legacyName: String
) : Closeable {
    private var retired = false
    private var connection: KnowledgeSqlite? = null
    private var indexing = false
    internal var decryptedItemReads = 0L
        private set
    internal var indexFailure: String? = null
        private set

    private fun open(): KnowledgeSqlite {
        connection?.let { return it }
        val path = context.getDatabasePath(name)
        path.parentFile?.mkdirs()
        val db = KnowledgeSqlite(path.absolutePath)
        try {
            db.execSQL("PRAGMA foreign_keys=ON")
            db.execSQL("PRAGMA busy_timeout=5000")
            db.execSQL("PRAGMA journal_mode=WAL")
            db.execSQL("PRAGMA synchronous=FULL")
            db.beginTransaction()
            try {
                val version = db.rawQuery("PRAGMA user_version", null).use { check(it.moveToFirst()); it.getInt(0) }
                require(version in 0..3) { "Unsupported knowledge schema $version" }
                if (version == 0) createTables(db)
                if (version < 2) {
                    AgentKnowledgeFtsIndex.create(db)
                    db.execSQL("INSERT INTO knowledge_fts_pending(item_key) SELECT item_key FROM knowledge_items")
                    db.execSQL("PRAGMA user_version=2")
                }
                if (version < 3) {
                    KnowledgeVectorLedger.create(db)
                    db.execSQL("PRAGMA user_version=3")
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
            return db.also { connection = it }
        } catch (error: Throwable) { db.close(); throw error }
    }

    private fun createTables(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_items (item_key TEXT PRIMARY KEY, title_key TEXT NOT NULL, " +
            "source_key TEXT NOT NULL, updated INTEGER NOT NULL, header TEXT NOT NULL)")
        db.execSQL("CREATE INDEX knowledge_title ON knowledge_items(title_key)")
        db.execSQL("CREATE INDEX knowledge_source ON knowledge_items(source_key)")
        db.execSQL("CREATE INDEX knowledge_updated ON knowledge_items(updated DESC,item_key)")
        db.execSQL("CREATE TABLE knowledge_chunks (item_key TEXT NOT NULL REFERENCES knowledge_items(item_key) " +
            "ON DELETE CASCADE, ordinal INTEGER NOT NULL, ciphertext TEXT NOT NULL, PRIMARY KEY(item_key,ordinal))")
        db.execSQL("CREATE TABLE knowledge_meta (name TEXT PRIMARY KEY)")
    }
    fun <T> access(block: (KnowledgeSqlite) -> T): T = synchronized(this) {
        check(!retired) { "Knowledge store was closed; reopen the store" }
        val db = open()
        migrate(db)
        // Header and chunks must be observed from one SQLite snapshot.
        db.beginTransactionNonExclusive()
        try { block(db).also { db.setTransactionSuccessful() } } finally {
            db.endTransaction()
            scheduleIndexing(db)
        }
    }

    fun <T> transaction(block: (KnowledgeSqlite) -> T): T = access(block)
    fun vectors(spec: KnowledgeVectorSpec) = KnowledgeVectorLedger(this, name, spec)
    @Synchronized override fun close() { retired = true; connection?.close(); connection = null }

    private fun migrate(db: KnowledgeSqlite) {
        val legacy = context.getSharedPreferences(legacyName, Context.MODE_PRIVATE)
        val migrated = db.rawQuery("SELECT 1 FROM knowledge_meta WHERE name='legacy-array-v1'", null)
            .use { it.moveToFirst() }
        if (!migrated) {
            db.beginTransaction()
            try {
                val raw = legacy.getString("items", null)
                if (raw != null) {
                    val plaintext = requireNotNull(AgentStorageCipher.decrypt(raw, "$legacyName:items".toByteArray())) {
                        "Cannot decrypt legacy knowledge; migration was not committed"
                    }
                    val items = JSONArray(plaintext)
                    val seen = hashSetOf<String>()
                    for (i in 0 until items.length()) {
                        val json = items.getJSONObject(i)
                        require(json.optString("id").isNotBlank()) { "Legacy knowledge has no stable ID" }
                        val item = requireNotNull(AgentKnowledgeCodec.decodeItem(json)) { "Invalid legacy knowledge item" }
                        require(seen.add(item.id)) { "Duplicate legacy knowledge ID" }
                        write(db, item)
                        check(read(db, key("id", item.id)) == item) { "Legacy knowledge verification failed" }
                    }
                }
                db.execSQL("INSERT INTO knowledge_meta(name) VALUES ('legacy-array-v1')")
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
        }
        // Only remove the legacy copy after the complete migration transaction committed.
        if (legacy.contains("items")) AgentEncryptedPreferences(context, legacyName).removeDurably("items")
    }

    fun key(kind: String, value: String): String = Mac.getInstance("HmacSHA256").run {
        init(indexKey())
        doFinal("$name:$kind:$value".toByteArray()).joinToString("") { "%02x".format(it) }
    }

    fun write(db: KnowledgeSqlite, item: AgentKnowledgeItem) {
        val id = key("id", item.id)
        val encoded = AgentKnowledgeCodec.encodeItem(item).toString()
        val chunks = mutableListOf<String>()
        var start = 0
        while (start < encoded.length) {
            var end = minOf(start + 16 * 1024, encoded.length)
            if (end < encoded.length && encoded[end - 1].isHighSurrogate() && encoded[end].isLowSurrogate()) end--
            chunks += encoded.substring(start, end)
            start = end
        }
        val titleKey = key("title", "${item.kind}:${item.title.lowercase(java.util.Locale.US)}")
        val sourceKey = if (item.source.isBlank()) "" else key("source", item.source)
        val header = JSONObject().put("chunks", chunks.size).put("sha256", AgentNativeJsonCodec.sha256(encoded))
            .put("title_key", titleKey).put("source_key", sourceKey).put("updated", item.updatedAtMillis).toString()
        db.delete("knowledge_items", "item_key=?", arrayOf(id))
        db.insertOrThrow("knowledge_items", null, ContentValues().apply {
            put("item_key", id)
            put("title_key", titleKey)
            put("source_key", sourceKey)
            put("updated", item.updatedAtMillis)
            put("header", AgentStorageCipher.encrypt(header, aad(id, "header")))
        })
        chunks.forEachIndexed { index, chunk ->
            db.insertOrThrow("knowledge_chunks", null, ContentValues().apply {
                put("item_key", id); put("ordinal", index)
                put("ciphertext", AgentStorageCipher.encrypt(chunk, aad(id, index.toString())))
            })
        }
        indexItem(db, id, item)
    }

    fun read(db: KnowledgeSqlite, id: String): AgentKnowledgeItem? {
        val header = db.rawQuery("SELECT header,title_key,source_key,updated FROM knowledge_items WHERE item_key=?", arrayOf(id)).use {
            if (!it.moveToFirst()) return null
            JSONObject(requireNotNull(AgentStorageCipher.decrypt(it.getString(0), aad(id, "header")))).apply {
                check(getString("title_key") == it.getString(1) && getString("source_key") == it.getString(2) &&
                    getLong("updated") == it.getLong(3)) { "Knowledge index metadata mismatch" }
            }
        }
        decryptedItemReads++
        val count = header.getInt("chunks")
        require(count > 0)
        val body = StringBuilder()
        var next = 0
        while (next < count) {
            val previous = next
            db.rawQuery("SELECT ordinal,ciphertext FROM knowledge_chunks WHERE item_key=? AND ordinal>=? " +
                "ORDER BY ordinal LIMIT 32", arrayOf(id, next.toString())).use { cursor ->
                while (cursor.moveToNext()) {
                    check(cursor.getInt(0) == next && next < count) { "Knowledge chunks are not contiguous" }
                    body.append(requireNotNull(AgentStorageCipher.decrypt(cursor.getString(1), aad(id, next.toString()))) {
                        "Knowledge chunk cannot be decrypted"
                    })
                    next++
                }
            }
            check(next > previous) { "Knowledge chunks are missing" }
        }
        val encoded = body.toString()
        check(AgentNativeJsonCodec.sha256(encoded) == header.getString("sha256")) { "Knowledge checksum mismatch" }
        return requireNotNull(AgentKnowledgeCodec.decodeItem(JSONObject(encoded))).also {
            check(key("id", it.id) == id) { "Knowledge identity mismatch" }
        }
    }

    fun keys(db: KnowledgeSqlite, where: String = "", args: Array<String> = emptyArray(), limit: Int? = null): List<String> =
        db.rawQuery("SELECT item_key FROM knowledge_items" + (if (where.isBlank()) "" else " WHERE $where") +
            " ORDER BY updated DESC,item_key" + (limit?.let { " LIMIT ${it.coerceAtLeast(0)}" } ?: ""), args).use {
            buildList { while (it.moveToNext()) add(it.getString(0)) }
        }

    fun scan(db: KnowledgeSqlite): Sequence<AgentKnowledgeItem> = sequence {
        var after = ""
        while (true) {
            val page = db.rawQuery("SELECT item_key FROM knowledge_items WHERE item_key>? ORDER BY item_key LIMIT 64",
                arrayOf(after)).use { buildList { while (it.moveToNext()) add(it.getString(0)) } }
            if (page.isEmpty()) break
            page.forEach { yield(requireNotNull(read(db, it))) }
            after = page.last()
        }
    }

    fun stats(db: KnowledgeSqlite): AgentKnowledgeStats = db.rawQuery("SELECT count(*)," +
        "count(DISTINCT NULLIF(source_key,'')),COALESCE(max(updated),0) FROM knowledge_items", null).use {
        check(it.moveToFirst()); AgentKnowledgeStats(it.getInt(0), it.getInt(1), it.getLong(2))
    }
    private fun aad(id: String, part: String) = "$name:$id:$part".toByteArray()

    private fun searchTokens() = AgentKnowledgeSearchTokens(Mac.getInstance("HmacSHA256").run {
        init(indexKey()); doFinal("$name:fts5-token-key:v1".toByteArray())
    })

    private fun indexItem(db: KnowledgeSqlite, id: String, item: AgentKnowledgeItem) {
        searchTokens().use { AgentKnowledgeFtsIndex.put(db, id, item, it) }
    }

    fun candidates(db: KnowledgeSqlite, query: String, limit: Int): Sequence<AgentKnowledgeItem> {
        val ids = searchTokens().use { AgentKnowledgeFtsIndex.search(db, query, limit, it) }
        return sequence {
            ids.forEach { yield(requireNotNull(read(db, it))) }
            // Until backfill completes, only pending rows need lexical scanning.
            var after = ""
            while (true) {
                val page = AgentKnowledgeFtsIndex.pending(db, 32, after)
                if (page.isEmpty()) break
                page.forEach { if (it !in ids) yield(requireNotNull(read(db, it))) }
                after = page.last()
            }
        }
    }

    private fun scheduleIndexing(db: KnowledgeSqlite) {
        if (retired || indexing || AgentKnowledgeFtsIndex.pending(db, 1).isEmpty()) return
        indexing = true
        indexExecutor.schedule({
            synchronized(this) {
                try {
                    if (!retired) access { current ->
                        AgentKnowledgeFtsIndex.pending(current, 8).forEach { id ->
                            indexItem(current, id, requireNotNull(read(current, id)))
                        }
                        indexFailure = null
                    }
                } catch (error: Exception) {
                    indexFailure = error.javaClass.simpleName
                } finally {
                    indexing = false
                    if (!retired && indexFailure == null) connection?.let(::scheduleIndexing)
                }
            }
        }, 10, TimeUnit.MILLISECONDS)
    }

    companion object {
        private val helpers = ConcurrentHashMap<String, AgentKnowledgeDatabase>()
        private val indexExecutor = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "knowledge-fts-backfill").apply { isDaemon = true }
        }
        @Volatile private var cachedIndexKey: SecretKey? = null
        fun shared(context: Context, name: String, legacy: String): AgentKnowledgeDatabase =
            helpers.computeIfAbsent(context.getDatabasePath(name).absolutePath) {
                AgentKnowledgeDatabase(context.applicationContext, name, legacy)
            }
        fun release(context: Context, name: String) {
            KnowledgeSemanticRuntime.invalidateDatabase(name)
            helpers.remove(context.getDatabasePath(name).absolutePath)?.close()
        }
        fun closeForPrivateDataReset() {
            KnowledgeSemanticRuntime.closeForPrivateDataReset()
            helpers.values.forEach { it.close() }
            helpers.clear()
        }
        @Synchronized fun deleteIndexKey() {
            cachedIndexKey = null
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry("galaxyssi.knowledge.index.v1")
        }
        @Synchronized private fun indexKey(): SecretKey {
            cachedIndexKey?.let { return it }
            val alias = "galaxyssi.knowledge.index.v1"
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (store.getKey(alias, null) as? SecretKey)?.let { cachedIndexKey = it; return it }
            return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").run {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY).build())
                generateKey().also { cachedIndexKey = it }
            }
        }
    }
}
