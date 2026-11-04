package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import com.google.crypto.tink.StreamingAead
import com.google.crypto.tink.subtle.AesGcmHkdfStreaming
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.channels.SeekableByteChannel
import java.nio.file.Files
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import org.json.JSONObject

/** Originals are immutable objects; per-import mappings make worker restarts idempotent. */
internal class HealthOriginalStore(
    private val context: Context,
    private val databaseName: String = "health_originals_v1.db",
    private val root: File = File(context.filesDir, "health-originals-v1")
) : Closeable {
    private val helper = Database(context.applicationContext, databaseName)
    private fun aad(kind: String, id: String) = "$databaseName|health-$kind-v1|$id".toByteArray(Charsets.UTF_8)
    private fun pack(kind: String, id: String, json: JSONObject): ByteArray {
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(bytes, aad(kind, id)) } finally { bytes.fill(0) }
    }
    private fun unpack(kind: String, id: String, bytes: ByteArray): JSONObject {
        val plaintext = AgentStorageCipher.decryptBinary(bytes, aad(kind, id))
        return try { JSONObject(String(plaintext, Charsets.UTF_8)) } finally { plaintext.fill(0) }
    }
    private fun notifyChanged(kind: String = "jobs") { context.contentResolver.notifyChange(changesUri(context).buildUpon().appendPath(kind).build(), null) }
    private fun validId(id: String) = runCatching { UUID.fromString(id).toString() == id }.getOrDefault(false)
    private fun file(original: HealthOriginal): File {
        require(validId(original.id) && validId(original.streamId))
        val target = File(root, original.relativePath).canonicalFile
        require(target.toPath().startsWith(root.canonicalFile.toPath()) && target != root.canonicalFile)
        return target
    }
    fun present(original: HealthOriginal) = file(original).isFile
    private fun decodeOriginal(id: String, bytes: ByteArray) = HealthOriginal.from(unpack("original", id, bytes)).also {
        check(it.id == id && it.size > 0 && it.sha256.matches(Regex("[0-9a-f]{64}")))
        file(it)
    }
    fun original(id: String): HealthOriginal? {
        require(validId(id))
        return helper.readableDatabase.rawQuery("SELECT payload FROM originals WHERE id=?", arrayOf(id))
            .use { if (it.moveToFirst()) decodeOriginal(id, it.getBlob(0)) else null }
    }
    fun originalForJob(job: String): HealthOriginal? = helper.readableDatabase.rawQuery(
        "SELECT o.id,o.payload FROM imports i JOIN originals o ON o.id=i.original_id WHERE i.job_id=?", arrayOf(job)
    ).use { if (it.moveToFirst()) decodeOriginal(it.getString(0), it.getBlob(1)) else null }

    fun originals(before: Pair<Long, String>? = null): List<HealthOriginal> {
        val where = if (before == null) "" else " WHERE imported_at<? OR (imported_at=? AND id<?)"
        val args = before?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        return helper.readableDatabase.rawQuery("SELECT id,payload FROM originals$where ORDER BY imported_at DESC,id DESC LIMIT 30", args)
            .use { buildList { while (it.moveToNext()) add(decodeOriginal(it.getString(0), it.getBlob(1))) } }
    }
    fun createJob(job: HealthImportJob) {
        require(validId(job.id) && job.sourceUri.startsWith("content://") && job.mode in listOf("report", "device"))
        helper.writableDatabase.insertOrThrow("jobs", null, jobValues(job))
        notifyChanged()
    }
    private fun jobValues(job: HealthImportJob) = ContentValues().apply {
        put("id", job.id); put("created_at", job.createdAt); put("state", job.state.name); put("payload", pack("job", job.id, job.json()))
    }
    private fun decodeJob(id: String, state: String, bytes: ByteArray) = HealthImportJob.from(unpack("job", id, bytes)).also {
        check(it.id == id && it.state.name == state)
    }
    fun job(id: String): HealthImportJob? = helper.readableDatabase.rawQuery("SELECT state,payload FROM jobs WHERE id=?", arrayOf(id))
        .use { if (it.moveToFirst()) decodeJob(id, it.getString(0), it.getBlob(1)) else null }
    fun jobs(before: Pair<Long, String>? = null): List<HealthImportJob> {
        val where = if (before == null) "" else " WHERE created_at<? OR (created_at=? AND id<?)"
        val args = before?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        return helper.readableDatabase.rawQuery("SELECT id,state,payload FROM jobs$where ORDER BY created_at DESC,id DESC LIMIT 30", args)
            .use { buildList { while (it.moveToNext()) add(decodeJob(it.getString(0), it.getString(1), it.getBlob(2))) } }
    }
    fun pendingJobs(after: Pair<Long, String>? = null): List<HealthImportJob> {
        val cursor = if (after == null) "" else " AND (created_at<? OR (created_at=? AND id<?))"
        val args = after?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        return helper.readableDatabase.rawQuery("SELECT id,state,payload FROM jobs WHERE state IN ('QUEUED','COPYING','RECOGNIZING')$cursor ORDER BY created_at DESC,id DESC LIMIT 100", args)
            .use { buildList { while (it.moveToNext()) add(decodeJob(it.getString(0), it.getString(1), it.getBlob(2))) } }
    }

    @Synchronized fun updateJob(id: String, restartCancelled: Boolean = false, update: (HealthImportJob) -> HealthImportJob): HealthImportJob? {
        val db = helper.writableDatabase
        db.beginTransaction()
        return try {
            val current = job(id) ?: return null
            val next = update(current)
            require(next.id == current.id && next.createdAt == current.createdAt)
            if (current.state == HealthImportState.CANCELLED && !(restartCancelled && next.state == HealthImportState.QUEUED)) return current
            check(db.update("jobs", jobValues(next), "id=?", arrayOf(id)) == 1)
            db.setTransactionSuccessful()
            next
        } finally { db.endTransaction(); notifyChanged() }
    }
    fun page(job: String, page: Int): HealthOcrPage? = helper.readableDatabase.rawQuery(
        "SELECT payload FROM pages WHERE job_id=? AND page_number=?", arrayOf(job, page.toString())
    ).use { if (it.moveToFirst()) HealthOcrPage.from(unpack("page", "$job:$page", it.getBlob(0))) else null }
    @Synchronized fun savePage(id: String, page: HealthOcrPage) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val current = job(id) ?: error("Health import is missing")
            if (current.state == HealthImportState.CANCELLED) return
            require(page.page == current.nextPage + 1 && page.lines.size <= 10_000)
            db.insertOrThrow("pages", null, ContentValues().apply {
                put("job_id", id); put("page_number", page.page); put("payload", pack("page", "$id:${page.page}", page.json()))
            })
            db.update("jobs", jobValues(current.copy(nextPage = page.page)), "id=?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); notifyChanged() }
    }

    @Synchronized fun importOriginal(
        id: String, input: InputStream, name: String, mime: String, source: String,
        checkCancelled: () -> Unit = {}, progress: (Long) -> Unit = {}
    ): HealthOriginal {
        require(validId(id))
        originalForJob(id)?.takeIf(::present)?.let { return it }
        val streamId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val capturedAt = job(id)?.createdAt ?: now
        val folder = SimpleDateFormat("yyyy/MM", Locale.ROOT).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(Date(capturedAt))
        val relative = "$folder/$id-$streamId.ghealth"
        val destination = File(root, relative)
        check(destination.parentFile!!.isDirectory || destination.parentFile!!.mkdirs())
        val existing = originalForJob(id)
        destination.parentFile!!.listFiles().orEmpty().filter {
            it.name.startsWith("$id-") && it.extension in listOf("partial", "ghealth") && it != existing?.let(::file)
        }.forEach { check(it.delete()) { "Cannot clean interrupted health import" } }
        val staging = File(destination.parentFile, "$id-$streamId.partial")
        val key = ByteArray(32).also(SecureRandom()::nextBytes)
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        try {
            val primitive = primitive(key)
            FileOutputStream(staging).use { output ->
                val sink = object : OutputStream() {
                    override fun write(value: Int) = output.write(value)
                    override fun write(bytes: ByteArray, offset: Int, length: Int) = output.write(bytes, offset, length)
                    override fun close() = output.flush()
                }
                primitive.newEncryptingStream(sink, aad("stream", streamId)).use { encrypted ->
                    val buffer = ByteArray(64 * 1024)
                    var notified = 0L
                    try {
                        while (true) {
                            checkCancelled()
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count == 0) continue
                            digest.update(buffer, 0, count); encrypted.write(buffer, 0, count); total += count
                            if (total - notified >= 1024 * 1024) { progress(total); notified = total }
                        }
                    } finally { buffer.fill(0) }
                }
                output.fd.sync()
            }
            require(total > 0) { "Empty health original" }
            checkCancelled(); progress(total)
            val hash = digest.digest().joinToString("") { "%02x".format(it) }
            val token = AgentMemoryIndexKey.token("$databaseName|health-original-digest|$hash")
            val db = helper.writableDatabase
            db.beginTransaction()
            var committed = false
            try {
                val previous = db.rawQuery("SELECT id,payload FROM originals WHERE digest_token=?", arrayOf(token)).use {
                    if (it.moveToFirst()) decodeOriginal(it.getString(0), it.getBlob(1)) else null
                }
                if (previous != null) check(previous.sha256 == hash && previous.size == total) { "Health digest index mismatch" }
                if (previous != null && present(previous)) {
                    mapImport(db, id, previous.id); db.setTransactionSuccessful()
                    return previous
                }
                val original = HealthOriginal(previous?.id ?: id, streamId, previous?.name ?: name.take(240).ifBlank { "document" }, previous?.mime ?: mime.take(120), total,
                    hash, previous?.importedAt ?: now, relative, previous?.source ?: source)
                val values = ContentValues().apply {
                    put("id", original.id); put("imported_at", original.importedAt); put("digest_token", token)
                    put("payload", pack("original", original.id, original.json()))
                    put("key_payload", AgentStorageCipher.encryptBinary(key, aad("key", original.id)))
                }
                if (previous == null) db.insertOrThrow("originals", null, values)
                else check(db.update("originals", values, "id=?", arrayOf(previous.id)) == 1)
                Files.move(staging.toPath(), destination.toPath())
                mapImport(db, id, original.id)
                checkCancelled(); db.setTransactionSuccessful(); committed = true
                return original
            } finally {
                db.endTransaction()
                if (!committed) destination.delete()
                notifyChanged("originals")
            }
        } finally { staging.delete(); key.fill(0) }
    }
    private fun mapImport(db: SQLiteDatabase, job: String, original: String) {
        db.insertWithOnConflict("imports", null, ContentValues().apply { put("job_id", job); put("original_id", original) }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    private fun primitive(key: ByteArray): StreamingAead = AesGcmHkdfStreaming(key, "HmacSha256", 32, 64 * 1024, 0)
    private fun openChannel(original: HealthOriginal): SeekableByteChannel {
        val encoded = helper.readableDatabase.rawQuery("SELECT key_payload FROM originals WHERE id=?", arrayOf(original.id))
            .use { check(it.moveToFirst()); it.getBlob(0) }
        val key = AgentStorageCipher.decryptBinary(encoded, aad("key", original.id))
        val primitive = try { primitive(key) } finally { key.fill(0) }
        val channel = Files.newByteChannel(file(original).toPath())
        return try { primitive.newSeekableDecryptingChannel(channel, aad("stream", original.streamId)) }
        catch (failure: Throwable) { channel.close(); throw failure }
    }
    fun input(original: HealthOriginal): InputStream = java.nio.channels.Channels.newInputStream(openChannel(original))
    fun copyVerified(original: HealthOriginal, output: OutputStream, checkCancelled: () -> Unit = {}): Long {
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        input(original).use { input ->
            val buffer = ByteArray(64 * 1024)
            try { while (true) {
                checkCancelled(); val count = input.read(buffer); if (count < 0) break
                output.write(buffer, 0, count); digest.update(buffer, 0, count); total += count
            } } finally { buffer.fill(0) }
        }
        check(total == original.size && digest.digest().joinToString("") { "%02x".format(it) } == original.sha256) { "Health original integrity check failed" }
        return total
    }
    fun descriptor(original: HealthOriginal): ParcelFileDescriptor {
        val channel = openChannel(original)
        return try { context.getSystemService(StorageManager::class.java).openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY,
            object : ProxyFileDescriptorCallback() {
                override fun onGetSize() = original.size
                @Synchronized override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
                    try {
                        if (offset >= original.size) return 0
                        require(offset >= 0 && size >= 0 && size <= data.size)
                        channel.position(offset)
                        return channel.read(ByteBuffer.wrap(data, 0, minOf(size.toLong(), original.size - offset).toInt())).coerceAtLeast(0)
                    } catch (failure: Exception) {
                        data.fill(0)
                        throw android.system.ErrnoException("health-original-read", android.system.OsConstants.EIO, failure)
                    }
                }
                override fun onRelease() { runCatching { channel.close() } }
            }, reader) } catch (failure: Throwable) { channel.close(); throw failure }
    }
    fun removeOriginalBytes(original: HealthOriginal): Boolean {
        val value = file(original)
        return !value.exists() || value.delete().also { notifyChanged("originals") }
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE originals(id TEXT PRIMARY KEY,imported_at INTEGER NOT NULL,digest_token TEXT UNIQUE NOT NULL,payload BLOB NOT NULL,key_payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX original_page ON originals(imported_at DESC,id DESC)")
            db.execSQL("CREATE TABLE imports(job_id TEXT PRIMARY KEY,original_id TEXT NOT NULL REFERENCES originals(id))")
            db.execSQL("CREATE TABLE jobs(id TEXT PRIMARY KEY,created_at INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX job_page ON jobs(created_at DESC,id DESC)")
            db.execSQL("CREATE INDEX job_pending ON jobs(state,created_at DESC,id DESC)")
            db.execSQL("CREATE TABLE pages(job_id TEXT NOT NULL REFERENCES jobs(id),page_number INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(job_id,page_number))")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { error("Unsupported health original schema") }
    }
    companion object {
        fun changesUri(context: Context): Uri = Uri.parse("content://${context.packageName}.health-originals/changes")
        private val reader by lazy { Handler(HandlerThread("health-original-reader").apply { start() }.looper) }
    }
}
