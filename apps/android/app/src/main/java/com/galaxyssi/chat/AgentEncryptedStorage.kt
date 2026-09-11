package com.galaxyssi.chat

import android.content.Context
import android.content.SharedPreferences
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class AgentEncryptedPreferences(context: Context, private val preferencesName: String) {
    private val preferences: SharedPreferences = context.applicationContext
        .getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    @Synchronized
    fun readString(key: String, defaultValue: String): String {
        val raw = preferences.getString(key, null) ?: return defaultValue
        val cacheKey = cacheKey(key)
        AgentEncryptedPreferenceCache.get(cacheKey, raw)
            ?.let { cached -> return cached }
        return (AgentStorageCipher.decrypt(raw, associatedData(key)) ?: defaultValue).also { plaintext ->
            AgentEncryptedPreferenceCache.put(cacheKey, raw, plaintext)
        }
    }

    @Synchronized
    fun writeString(key: String, value: String) {
        val encrypted = AgentStorageCipher.encrypt(value, associatedData(key))
        check(preferences.edit().putString(key, encrypted).commit()) { "Agent encrypted storage write failed" }
        AgentEncryptedPreferenceCache.put(cacheKey(key), encrypted, value)
    }

    @Synchronized
    fun remove(key: String) {
        preferences.edit().remove(key).apply()
        AgentEncryptedPreferenceCache.remove(cacheKey(key))
    }

    @Synchronized
    fun removeDurably(key: String) {
        check(preferences.edit().remove(key).commit()) { "Agent encrypted storage removal failed" }
        AgentEncryptedPreferenceCache.remove(cacheKey(key))
    }

    @Synchronized
    fun encodedValueLength(key: String): Int = preferences.getString(key, null)?.length ?: 0

    @Synchronized
    fun contains(key: String): Boolean {
        val raw = preferences.getString(key, null) ?: return false
        return AgentStorageCipher.decrypt(raw, associatedData(key)) != null
    }

    @Synchronized
    fun keys(): Set<String> = preferences.all.keys.toSet()

    @Synchronized
    fun clear() {
        preferences.edit().clear().commit()
        AgentEncryptedPreferenceCache.clearNamespace(preferencesName)
    }

    private fun associatedData(key: String): ByteArray = "$preferencesName:$key".toByteArray(Charsets.UTF_8)

    private fun cacheKey(key: String): String = "$preferencesName\u0000$key"

}

internal object AgentEncryptedPreferenceCache {
    private data class CachedValue(
        val encryptedValue: String,
        val plaintext: CharArray,
        val expiresAtNanos: Long
    )

    private val values = linkedMapOf<String, CachedValue>()
    private var clockNanos: () -> Long = System::nanoTime

    @Synchronized
    fun get(cacheKey: String, encryptedValue: String): String? {
        val cached = values[cacheKey] ?: return null
        if (cached.encryptedValue != encryptedValue || cached.expiresAtNanos <= clockNanos()) {
            values.remove(cacheKey)?.wipe()
            return null
        }
        return String(cached.plaintext)
    }

    @Synchronized
    fun put(cacheKey: String, encryptedValue: String, plaintext: String) {
        val now = clockNanos()
        pruneExpired(now)
        values.put(
            cacheKey,
            CachedValue(
                encryptedValue = encryptedValue,
                plaintext = plaintext.toCharArray(),
                expiresAtNanos = now + CACHE_TTL_NANOS
            )
        )?.wipe()
        while (values.size > MAX_CACHE_ENTRIES) {
            val eldest = values.entries.firstOrNull() ?: break
            values.remove(eldest.key)?.wipe()
        }
    }

    @Synchronized
    fun remove(cacheKey: String) {
        values.remove(cacheKey)?.wipe()
    }

    @Synchronized
    fun clearNamespace(namespace: String) {
        val prefix = "$namespace\u0000"
        values.keys.filter { cacheKey -> cacheKey.startsWith(prefix) }
            .forEach { cacheKey -> values.remove(cacheKey)?.wipe() }
    }

    @Synchronized
    fun clearAll() {
        values.values.forEach { cached -> cached.wipe() }
        values.clear()
    }

    @Synchronized
    internal fun clearForTest() {
        clearAll()
        clockNanos = System::nanoTime
    }

    @Synchronized
    internal fun setClockForTest(clock: () -> Long) {
        clearAll()
        clockNanos = clock
    }

    @Synchronized
    internal fun sizeForTest(): Int = values.size

    private fun pruneExpired(now: Long) {
        values.entries
            .filter { (_, cached) -> cached.expiresAtNanos <= now }
            .map(Map.Entry<String, CachedValue>::key)
            .forEach { cacheKey -> values.remove(cacheKey)?.wipe() }
    }

    private fun CachedValue.wipe() {
        plaintext.fill('\u0000')
    }

    private const val MAX_CACHE_ENTRIES = 128
    internal const val CACHE_TTL_NANOS = 30L * 1_000_000_000L
}

internal fun ByteArray.wipeSensitive() {
    fill(0)
}

internal fun ShortArray.wipeSensitive() {
    fill(0)
}

internal fun CharArray.wipeSensitive() {
    fill('\u0000')
}

class AgentEncryptedDatabase(
    context: Context,
    private val databaseName: String
) {
    private val database = sharedDatabase(context.applicationContext, databaseName)
    internal val storageIdentity = context.applicationContext.getDatabasePath("$databaseName.db").absolutePath

    fun readString(key: String, defaultValue: String): String = withStorage {
        val encrypted = readEncryptedValue(database.readableDatabase, key) ?: return@withStorage defaultValue
        decodeValue(key, encrypted) ?: defaultValue
    }

    fun readStrings(keys: Collection<String>): Map<String, String> = withStorage {
        val requested = keys.distinct()
        if (requested.isEmpty()) return@withStorage emptyMap()
        buildMap {
            requested.forEach { key ->
                readEncryptedValue(database.readableDatabase, key)
                    ?.let { encrypted -> decodeValue(key, encrypted) }
                    ?.let { value -> put(key, value) }
            }
        }
    }

    fun writeString(key: String, value: String) = withStorage {
        val values = encodeValue(key, value)
        check(database.writableDatabase.insertWithOnConflict(
            TABLE_VALUES, null, values, SQLiteDatabase.CONFLICT_REPLACE
        ) != -1L) { "Agent encrypted database write failed" }
    }

    fun mutateStrings(
        upserts: Map<String, String>,
        removeKeys: Collection<String> = emptyList(),
        onMutation: ((SQLiteDatabase, String, String?) -> Unit)? = null,
        segmentPersonalRows: Boolean = false
    ): Unit = withStorage {
        if (upserts.isEmpty() && removeKeys.isEmpty()) return@withStorage
        val source = if (onMutation == null) upserts else upserts.toMap()
        val encryptedValues = source.mapValues { (key, value) ->
            encodeValue(key, value, segmentPersonalRows)
        }
        val writable = database.writableDatabase
        writable.beginTransaction()
        try {
            removeKeys.toSet().forEach { key ->
                writable.delete(TABLE_VALUES, "storage_key = ?", arrayOf(key))
                onMutation?.invoke(writable, key, null)
            }
            encryptedValues.forEach { (key, values) ->
                check(writable.insertWithOnConflict(
                    TABLE_VALUES,
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_REPLACE
                ) != -1L) { "Agent encrypted database transaction failed" }
                onMutation?.invoke(writable, key, source.getValue(key))
            }
            writable.setTransactionSuccessful()
        } finally {
            writable.endTransaction()
        }
    }

    fun remove(key: String): Unit = withStorage {
        database.writableDatabase.delete(TABLE_VALUES, "storage_key = ?", arrayOf(key))
        Unit
    }

    /** Encrypt one row at a time; iteration errors roll back the entire batch. */
    internal fun mutateStreaming(
        upserts: Sequence<Pair<String, String>>,
        onMutation: ((SQLiteDatabase, String, String?) -> Unit)? = null,
        segmentPersonalRows: Boolean = false,
        removals: () -> Sequence<String>
    ): Unit = withStorage {
        val writable = database.writableDatabase
        writable.beginTransaction()
        try {
            upserts.forEach { (key, value) ->
                val previous = readEncryptedValue(writable, key)
                if (previous == null || decodeValue(key, previous) != value) {
                    val values = encodeValue(key, value, segmentPersonalRows)
                    check(writable.insertWithOnConflict(TABLE_VALUES, null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L) {
                        "Agent encrypted streaming transaction failed"
                    }
                    onMutation?.invoke(writable, key, value)
                }
            }
            removals().forEach { key ->
                writable.delete(TABLE_VALUES, "storage_key = ?", arrayOf(key))
                onMutation?.invoke(writable, key, null)
            }
            writable.setTransactionSuccessful()
        } finally { writable.endTransaction() }
    }

    internal fun <T> indexedTransaction(block: (SQLiteDatabase) -> T): T = withStorage {
        val writable = database.writableDatabase
        writable.beginTransactionNonExclusive()
        try { block(writable).also { writable.setTransactionSuccessful() } }
        finally { writable.endTransaction() }
    }

    fun removeAll(keys: Collection<String>): Unit = withStorage {
        if (keys.isEmpty()) return@withStorage
        val writable = database.writableDatabase
        writable.beginTransaction()
        try {
            keys.forEach { key ->
                writable.delete(TABLE_VALUES, "storage_key = ?", arrayOf(key))
            }
            writable.setTransactionSuccessful()
        } finally {
            writable.endTransaction()
        }
    }

    fun clear(): Unit = withStorage {
        database.writableDatabase.delete(TABLE_VALUES, null, null)
        Unit
    }

    fun contains(key: String): Boolean = database.operations.withLock {
        database.readableDatabase.rawQuery(
            "SELECT 1 FROM $TABLE_VALUES WHERE storage_key = ? LIMIT 1", arrayOf(key)
        ).use { it.moveToFirst() }
    }

    fun countKeys(prefix: String): Int = database.operations.withLock {
        require(prefix.isNotEmpty())
        database.readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM $TABLE_VALUES WHERE storage_key >= ? AND storage_key < ?",
            arrayOf(prefix, "$prefix\uffff")
        ).use { cursor -> check(cursor.moveToFirst()); cursor.getInt(0) }
    }

    fun keys(prefix: String = ""): List<String> = database.operations.withLock {
        val selection = if (prefix.isBlank()) null else "storage_key >= ? AND storage_key < ?"
        val selectionArgs = if (prefix.isBlank()) null else arrayOf(prefix, "$prefix\uffff")
        database.readableDatabase.query(
            TABLE_VALUES,
            arrayOf("storage_key"),
            selection,
            selectionArgs,
            null,
            null,
            "storage_key ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }
    }

    fun recentKeys(prefix: String, limit: Int): List<String> = database.operations.withLock {
        val boundedLimit = limit.coerceAtLeast(0)
        if (boundedLimit == 0) return@withLock emptyList()
        val selection = if (prefix.isBlank()) null else "storage_key >= ? AND storage_key < ?"
        val selectionArgs = if (prefix.isBlank()) null else arrayOf(prefix, "$prefix\uffff")
        database.readableDatabase.query(
            TABLE_VALUES,
            arrayOf("storage_key"),
            selection,
            selectionArgs,
            null,
            null,
            "rowid DESC",
            boundedLimit.toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }
    }

    fun oldestKeys(prefix: String, limit: Int): List<String> = database.operations.withLock {
        val boundedLimit = limit.coerceAtLeast(0)
        if (boundedLimit == 0) return@withLock emptyList()
        val selection = if (prefix.isBlank()) null else "storage_key >= ? AND storage_key < ?"
        val selectionArgs = if (prefix.isBlank()) null else arrayOf(prefix, "$prefix\uffff")
        database.readableDatabase.query(
            TABLE_VALUES,
            arrayOf("storage_key"),
            selection,
            selectionArgs,
            null,
            null,
            "rowid ASC",
            boundedLimit.toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }
    }

    fun keysAfter(prefix: String, after: String, limit: Int): List<String> = database.operations.withLock {
        require(prefix.isNotEmpty() && limit in 1..256)
        require(after.isEmpty() || after.startsWith(prefix))
        database.readableDatabase.query(TABLE_VALUES, arrayOf("storage_key"),
            "storage_key >= ? AND storage_key < ? AND storage_key > ?",
            arrayOf(prefix, "$prefix\uffff", after), null, null, "storage_key ASC", limit.toString()).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }
    }

    fun entries(prefix: String = ""): List<Pair<String, String>> = withStorage {
        buildList {
            keys(prefix).forEach { key ->
                readEncryptedValue(database.readableDatabase, key)
                    ?.let { encrypted -> decodeValue(key, encrypted) }
                    ?.let { value -> add(key to value) }
            }
        }
    }

    /**
     * Connections are process-scoped and shared by database name. Individual
     * repository wrappers can be short-lived without creating leaked pools.
     */
    fun close() = Unit

    private fun associatedData(key: String): ByteArray =
        "database:$databaseName:$key".toByteArray(Charsets.UTF_8)

    private fun <T> withStorage(block: () -> T): T = database.operations.withLock {
        if (database.segmented) database.segmentAccess.readWrite(block) else block()
    }

    private fun encodeValue(key: String, value: String, largeStore: Boolean = false): ContentValues =
        ContentValues().apply {
            put("storage_key", key)
            if (database.segmented && AgentMemoryPayloadSegments.external(key, value, largeStore)) {
                val encoded = database.segments.encode(key, value, associatedData(key))
                put("encrypted_value", encoded.value)
                put("segment_id", encoded.segment)
                put("segment_bytes", encoded.bytes)
            } else {
                put("encrypted_value", AgentStorageCipher.encrypt(value, associatedData(key)))
                if (database.segmented) {
                    putNull("segment_id")
                    putNull("segment_bytes")
                }
            }
        }

    internal fun maintainMemorySegments(maxSegments: Int = 2, maxRows: Int = 8): AgentMemorySegmentMaintenance.Result = database.operations.withLock {
        check(database.segmented)
        database.segmentAccess.maintenance {
            AgentMemorySegmentMaintenance(database.writableDatabase, database.segments, ::associatedData)
                .run(maxSegments, maxRows)
        }
    }

    internal fun tryMaintainMemorySegments(checkActive: () -> Unit): AgentMemorySegmentMaintenance.Result? {
        check(database.segmented)
        if (!database.operations.tryLock()) return null
        try {
            return database.segmentAccess.tryMaintenance {
                checkActive()
                AgentMemorySegmentMaintenance(database.writableDatabase, database.segments, ::associatedData)
                    .run(1, 1, checkActive)
            }
        } finally { database.operations.unlock() }
    }

    private fun decodeValue(key: String, encrypted: String): String? =
        if (encrypted.startsWith(AgentMemoryPayloadSegments.PREFIX)) {
            database.segments.decode(key, encrypted, associatedData(key))
        } else AgentStorageCipher.decrypt(encrypted, associatedData(key)).also {
            check(it != null || !key.startsWith(AgentPersonalMemoryRows.PREFIX)) { "Personal memory ciphertext is corrupt" }
        }

    private fun readEncryptedValue(database: SQLiteDatabase, key: String): String? {
        val length = database.rawQuery(
            "SELECT length(encrypted_value) FROM $TABLE_VALUES WHERE storage_key = ? LIMIT 1",
            arrayOf(key)
        ).use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getInt(0) else return null
        }
        if (length <= CURSOR_TEXT_CHUNK_CHARS) {
            return database.rawQuery(
                "SELECT encrypted_value FROM $TABLE_VALUES WHERE storage_key = ? LIMIT 1",
                arrayOf(key)
            ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        }
        val value = StringBuilder(length)
        var offset = 1
        while (offset <= length) {
            val chunk = database.rawQuery(
                "SELECT substr(encrypted_value, ?, ?) FROM $TABLE_VALUES " +
                    "WHERE storage_key = ? LIMIT 1",
                arrayOf(offset.toString(), CURSOR_TEXT_CHUNK_CHARS.toString(), key)
            ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                ?: return null
            value.append(chunk)
            offset += chunk.length
            if (chunk.isEmpty()) return null
        }
        return value.toString()
    }

    private class SharedEncryptedDatabase(
        context: Context,
        databaseName: String
    ) : SQLiteOpenHelper(context, "$databaseName.db", null, if (databaseName == AgentMemoryStorage.DATABASE) 2 else 1) {
        val operations = ReentrantLock()
        val segmented = databaseName == AgentMemoryStorage.DATABASE
        val segmentAccess by lazy {
            MemorySegmentAccess(java.io.File(context.getDatabasePath("$databaseName.db").absolutePath + ".segments.lock"))
        }
        val segments by lazy {
            AgentMemoryPayloadSegments(java.io.File(context.getDatabasePath("$databaseName.db").absolutePath + ".segments"))
        }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                "CREATE TABLE $TABLE_VALUES (" +
                    "storage_key TEXT PRIMARY KEY NOT NULL, " +
                    "encrypted_value TEXT NOT NULL" +
                    (if (segmented) ", segment_id TEXT, segment_bytes INTEGER" else "") + ")"
            )
            if (segmented) createSegmentIndex(db)
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 2) {
                db.execSQL("ALTER TABLE $TABLE_VALUES ADD COLUMN segment_id TEXT")
                db.execSQL("ALTER TABLE $TABLE_VALUES ADD COLUMN segment_bytes INTEGER")
                createSegmentIndex(db)
            }
        }

        private fun createSegmentIndex(db: SQLiteDatabase) {
            db.execSQL("CREATE INDEX memory_payload_segment ON $TABLE_VALUES(segment_id,storage_key,segment_bytes) WHERE segment_id IS NOT NULL")
        }
    }

    private companion object {
        const val TABLE_VALUES = "encrypted_values"
        const val CURSOR_TEXT_CHUNK_CHARS = 256 * 1024
        val DATABASES = ConcurrentHashMap<String, SharedEncryptedDatabase>()

        fun sharedDatabase(context: Context, databaseName: String): SharedEncryptedDatabase =
            DATABASES.computeIfAbsent(context.getDatabasePath("$databaseName.db").absolutePath) {
                SharedEncryptedDatabase(context.applicationContext, databaseName)
            }
    }
}

object AgentStorageCipher {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "galaxyssi_agent_storage_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val PREFIX = "enc:v1:"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    @Volatile
    private var cachedKey: SecretKey? = null

    fun isEncrypted(value: String): Boolean = value.startsWith(PREFIX)

    /** Binary envelope for bounded sensitive records; no intermediate plaintext String. */
    fun encryptBinary(plaintext: ByteArray, associatedData: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(associatedData)
        val iv = cipher.iv
        require(iv.size == IV_BYTES)
        val encrypted = cipher.doFinal(plaintext)
        return try { byteArrayOf(1) + iv + encrypted } finally { encrypted.fill(0) }
    }

    fun decryptBinary(envelope: ByteArray, associatedData: ByteArray): ByteArray {
        require(envelope.size >= 1 + IV_BYTES + TAG_BITS / 8 && envelope[0] == 1.toByte()) {
            "Invalid binary storage envelope"
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_BITS, envelope, 1, IV_BYTES))
        cipher.updateAAD(associatedData)
        return cipher.doFinal(envelope, 1 + IV_BYTES, envelope.size - 1 - IV_BYTES)
    }

    fun encrypt(plaintext: String, associatedData: ByteArray): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(associatedData)
        val iv = cipher.iv
        require(iv.size == IV_BYTES) { "Unexpected Agent storage IV size" }
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return buildString {
            append(PREFIX)
            append(iv.toBase64())
            append(':')
            append(ciphertext.toBase64())
        }
    }

    fun decrypt(value: String, associatedData: ByteArray): String? {
        if (!isEncrypted(value)) return null
        return runCatching {
            val parts = value.removePrefix(PREFIX).split(':', limit = 2)
            require(parts.size == 2) { "Invalid Agent encrypted storage envelope" }
            val iv = parts[0].fromBase64()
            val ciphertext = parts[1].fromBase64()
            require(iv.size == IV_BYTES) { "Invalid Agent storage IV" }
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_BITS, iv))
            cipher.updateAAD(associatedData)
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        }.getOrNull()
    }

    @Synchronized
    fun deleteMasterKey() {
        cachedKey = null
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
    }

    @Synchronized
    private fun getOrCreateKey(): SecretKey {
        cachedKey?.let { return it }
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        runCatching { keyStore.getKey(KEY_ALIAS, null) as? SecretKey }
            .getOrNull()
            ?.let { return it.also { key -> cachedKey = key } }
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey().also { cachedKey = it }
    }

    private fun ByteArray.toBase64(): String = Base64.encodeToString(this, Base64.NO_WRAP)
    private fun String.fromBase64(): ByteArray = Base64.decode(this, Base64.NO_WRAP)
}
