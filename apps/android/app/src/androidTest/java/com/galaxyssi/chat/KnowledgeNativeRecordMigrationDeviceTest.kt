package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeNativeRecordMigrationDeviceTest {
    private val key = ByteArray(32) { 7 }
    private val identity = ByteArray(32) { 8 }
    private val epoch = ByteArray(16) { 9 }
    private val root = floatArrayOf(1f, 0f, 0f, 0f)
    private fun open(path: File, create: Boolean) = KnowledgeNativeBridge.openIndex(path.absolutePath,
        key, identity, epoch, 4, 4, 1024 * 1024, if (create) root else null)

    internal fun downgrade(path: File, key: ByteArray = this.key, identity: ByteArray = this.identity) {
        SQLiteDatabase.openDatabase(File(path, "catalog.sqlite").absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            for (shard in 0..3) db.execSQL("ATTACH DATABASE ? AS s$shard", arrayOf(File(path, "nodes-0$shard.sqlite").absolutePath))
            db.beginTransaction()
            try {
                for (shard in 0..3) {
                    db.execSQL("INSERT INTO main.index_records SELECT * FROM s$shard.index_records")
                    db.execSQL("DROP TABLE s$shard.index_records")
                }
                val envelope = db.rawQuery("SELECT sealed FROM index_state WHERE id=1", null).use { it.moveToFirst(); it.getBlob(0) }
                val aad = "galaxyssi:disk-memory:v1\u0000".toByteArray() + identity + "metadata".toByteArray()
                val decrypt = Cipher.getInstance("AES/GCM/NoPadding").apply {
                    init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, envelope.copyOfRange(0, 12)))
                    updateAAD(aad)
                }
                val current = decrypt.doFinal(envelope, 12, envelope.size - 12)
                val old = current.copyOf(48).also { "GSAN0001".toByteArray().copyInto(it) }
                val encrypt = Cipher.getInstance("AES/GCM/NoPadding").apply {
                    init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES")); updateAAD(aad)
                }
                val sealed = encrypt.iv + encrypt.doFinal(old)
                current.fill(0); old.fill(0)
                db.execSQL("UPDATE index_state SET sealed=? WHERE id=1", arrayOf(sealed))
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
        }
    }

    @Test fun realJniMigratesOldCatalogInBoundedPagesWithoutChangingGraphOrReplay() {
        KnowledgeNativeBridge.requireAvailable()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val parent = File(context.noBackupFilesDir, "test-native-record-migration-${UUID.randomUUID()}").apply { mkdirs() }
        val path = File(parent, "index")
        var handle = 0L
        try {
            handle = open(path, true)
            for (n in 1L..80L) {
                val event = KnowledgeNativeEvent(n, n - 1, n.toString(16).padStart(64, '0'), "02".repeat(32), 0, true)
                KnowledgeNativeBridge.beginEvent(handle, KnowledgeNativeWire.event(event), false).fill(0)
            }
            val expected = KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle))
            KnowledgeNativeBridge.closeIndex(handle); handle = 0
            downgrade(path)
            handle = open(path, false)
            assertFalse(KnowledgeNativeBridge.recordsPartitioned(handle))
            assertFalse(KnowledgeNativeBridge.migrateRecords(handle))
            assertEquals(expected, KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle)))
            KnowledgeNativeBridge.closeIndex(handle); handle = open(path, false)
            assertFalse(KnowledgeNativeBridge.recordsPartitioned(handle))
            assertTrue(KnowledgeNativeBridge.migrateRecords(handle))
            assertTrue(KnowledgeNativeBridge.recordsPartitioned(handle))
            assertEquals(expected, KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle)))
            assertEquals(1L, KnowledgeNativeBridge.nodeCount(handle))
            KnowledgeNativeBridge.closeIndex(handle); handle = open(path, false)
            assertTrue(KnowledgeNativeBridge.recordsPartitioned(handle))
        } finally {
            if (handle != 0L) KnowledgeNativeBridge.closeIndex(handle)
            parent.deleteRecursively()
        }
    }
}
