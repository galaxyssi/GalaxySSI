package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID

internal class MemoryDeletionDeviceFixture(id: String = UUID.randomUUID().toString()) {
    init { require(id.matches(Regex("[A-Za-z0-9_-]{1,80}"))) }
    private val base = InstrumentationRegistry.getInstrumentation().targetContext
    private val prefix = "test-memory-ledger-$id-"
    private val root = File(base.filesDir, "memory-ledger-fixtures/$id").apply { mkdirs() }
    val context: Context = object : ContextWrapper(base) {
        override fun getApplicationContext(): Context = this
        override fun getFilesDir(): File = File(root, "files").apply { mkdirs() }
        override fun getCacheDir(): File = File(root, "cache").apply { mkdirs() }
        override fun getNoBackupFilesDir(): File = File(root, "no-backup").apply { mkdirs() }
        override fun getDatabasePath(name: String): File =
            if (File(name).isAbsolute) File(name) else base.getDatabasePath(prefix + name)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            base.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
            errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
            base.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
        override fun getSharedPreferences(name: String, mode: Int) = base.getSharedPreferences(prefix + name, mode)
    }
    val store = EncryptedAgentMemoryStore(context).apply { suppressObservations = true }
    val ledger get() = store.deletionIndex
    val legacy = AgentEncryptedDatabase(context, EncryptedAgentMemoryDeletionIndex.DATABASE_NAME)
    fun reopen() = EncryptedAgentMemoryStore(context).apply { suppressObservations = true }
    fun sql(): SQLiteDatabase = SQLiteDatabase.openDatabase(
        context.getDatabasePath("${AgentMemoryStorage.DATABASE}.db").absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
    fun clear() { store.database.clear(); legacy.clear() }
}

internal fun deletionMemory(index: Int, value: String = "\u8bb0\u5fc6-$index") =
    AgentMemoryItem(AgentMemoryKind.PREFERENCE, value, id = "memory-$index", key = "key-$index", timestampMillis = 1)
