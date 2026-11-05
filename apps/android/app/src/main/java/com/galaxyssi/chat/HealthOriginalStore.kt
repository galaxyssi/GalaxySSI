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
    private val databaseName: String = LEGACY_DATABASE,
    private val root: File = File(context.filesDir, "health-originals-v1"),
    sharedRecords: HealthRecordStore? = null
) : Closeable {
    private val legacy = Database(context.applicationContext, databaseName) { id, bytes -> HealthOriginalKind.of(decodeOriginal(id, bytes)).name }
    private val ownedRecords = if (sharedRecords == null && databaseName == LEGACY_DATABASE) HealthRecordStore(context) else null
    private val records = sharedRecords ?: ownedRecords
    @Volatile private var migrated = false
    private val helper = object : Closeable {
        val readableDatabase: SQLiteDatabase get() = records?.tableDatabase?.also(::migrate) ?: legacy.readableDatabase
        val writableDatabase: SQLiteDatabase get() = records?.tableDatabase?.also(::migrate) ?: legacy.writableDatabase
        override fun close() { try { legacy.close() } finally { ownedRecords?.close() } }
    }

    @Synchronized private fun migrate(target: SQLiteDatabase) {
        if (migrated) return
        HealthOriginalMetadataMigration.migrate(target, databaseName) {
            if (!context.getDatabasePath(databaseName).exists()) null else legacy.readableDatabase
        }
        legacy.close()
        migrated = true
    }
    internal val libraryDatabase: SQLiteDatabase get() = helper.writableDatabase
    internal fun libraryPack(kind: String, id: String, value: JSONObject) = pack(kind, id, value)
    internal fun libraryUnpack(kind: String, id: String, value: ByteArray) = unpack(kind, id, value)
    internal fun libraryKeyAad(id: String) = aad("export-key", id)
    internal fun libraryChanged() { runCatching { notifyChanged("exports") } }
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

    internal fun restorationState(item: HealthBackupOriginal): HealthRestoreOriginalState {
        val token = AgentMemoryIndexKey.token("$databaseName|health-original-digest|${item.sha256}")
        val duplicate = helper.readableDatabase.rawQuery("SELECT id,payload FROM originals WHERE digest_token=?", arrayOf(token)).use {
            if (it.moveToFirst()) decodeOriginal(it.getString(0), it.getBlob(1)) else null
        }
        if (duplicate != null) check(duplicate.sha256 == item.sha256 && duplicate.size == item.bytes)
        return HealthRestoreOriginalState(duplicate, duplicate?.let(::present) == true, original(item.id))
    }

    internal fun prepareRestoredOriginal(batch: String, item: HealthBackupOriginal, id: String,
        previous: HealthOriginal?): Pair<HealthRestorePreparedOriginal, OutputStream?> {
        require(validId(batch) && validId(id))
        val streamId = UUID.randomUUID().toString()
        val original = HealthOriginal(id, streamId, previous?.name ?: item.name, previous?.mime ?: item.mime,
            item.bytes, item.sha256, previous?.importedAt ?: item.importedAt, "restore/$batch/$streamId.ghealth", previous?.source ?: item.source)
        val key = ByteArray(32).also(SecureRandom()::nextBytes)
        try {
            val staged = HealthRestorePreparedOriginal(original, AgentStorageCipher.encryptBinary(key, aad("key", id)), item.present)
            if (!item.present) return staged to null
            val target = file(original)
            val raw = FileOutputStream(target)
            val encrypted = try { primitive(key).newEncryptingStream(HealthPrivateExportFile.borrowed(raw), aad("stream", streamId)) }
                catch (failure: Throwable) { raw.close(); throw failure }
            val stream = object : java.io.FilterOutputStream(encrypted) {
                override fun write(bytes: ByteArray, offset: Int, length: Int) = out.write(bytes, offset, length)
                override fun close() {
                    raw.use {
                        out.close()
                        raw.fd.sync()
                    }
                }
            }
            return staged to stream
        } finally { key.fill(0) }
    }

    internal fun publishRestoredOriginal(value: HealthRestorePreparedOriginal, previous: HealthOriginal?) {
        val db = helper.writableDatabase
        val original = value.original
        check(db.inTransaction() && (previous == null || previous.id == original.id) && present(original) == value.present)
        val fields = ContentValues().apply {
            put("id", original.id); put("imported_at", original.importedAt); put("kind", HealthOriginalKind.of(original).name)
            put("digest_token", AgentMemoryIndexKey.token("$databaseName|health-original-digest|${original.sha256}"))
            put("payload", pack("original", original.id, original.json())); put("key_payload", value.wrappedKey)
        }
        if (previous == null) db.insertOrThrow("originals", null, fields)
        else check(db.update("originals", fields, "id=?", arrayOf(previous.id)) == 1)
    }

    internal fun notifyRestored() { runCatching { notifyChanged("originals") } }
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

    fun originalCount(): Long = helper.readableDatabase.rawQuery("SELECT COUNT(*) FROM originals WHERE $ARCHIVED", null)
        .use { it.moveToFirst(); it.getLong(0) }

    internal fun backupPage(after: String, signal: android.os.CancellationSignal? = null): List<HealthOriginal> =
        helper.readableDatabase.rawQuery("SELECT id,payload FROM originals WHERE id>? ORDER BY id LIMIT 30", arrayOf(after), signal)
            .use { rows -> buildList { while (rows.moveToNext()) add(decodeOriginal(rows.getString(0), rows.getBlob(1))) } }

    fun originals(before: Pair<Long, String>? = null, limit: Int = 30,
                  signal: android.os.CancellationSignal? = null): List<HealthOriginal> {
        require(limit in 1..30)
        val where = if (before == null) "" else " AND imported_at<=? AND (imported_at<? OR id<?)"
        val args = before?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        return helper.readableDatabase.rawQuery("SELECT id,payload,imported_at FROM originals WHERE $ARCHIVED$where ORDER BY imported_at DESC,id DESC LIMIT $limit", args, signal)
            .use { rows -> buildList {
                while (rows.moveToNext()) {
                    signal?.throwIfCanceled()
                    add(decodeOriginal(rows.getString(0), rows.getBlob(1)).also { check(it.importedAt == rows.getLong(2)) })
                }
            } }
    }
    fun library(filter: HealthLibraryFilter, before: Pair<Long, String>? = null, signal: android.os.CancellationSignal? = null): HealthLibraryPage {
        val terms = arrayListOf(ARCHIVED, "imported_at>=?", "imported_at<?")
        val args = arrayListOf(filter.from.toString(), filter.until.toString())
        filter.kind?.let { terms += "kind=?"; args += it.name }
        before?.let { terms += "(imported_at<? OR (imported_at=? AND id<?))"; args += listOf(it.first.toString(), it.first.toString(), it.second) }
        val rows = helper.readableDatabase.rawQuery("SELECT id,payload,imported_at,kind FROM originals WHERE ${terms.joinToString(" AND ")} ORDER BY imported_at DESC,id DESC LIMIT 31", args.toTypedArray(), signal)
            .use { cursor -> buildList { while (cursor.moveToNext()) add(decodeOriginal(cursor.getString(0), cursor.getBlob(1)).also {
                check(it.importedAt == cursor.getLong(2) && HealthOriginalKind.of(it).name == cursor.getString(3)) { "Health original index mismatch" }
            }) } }
        val visible = rows.take(30)
        return HealthLibraryPage(visible, if (rows.size > 30) visible.last().let { it.importedAt to it.id } else null)
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
    fun overviewReviewJobs(): List<HealthImportJob> {
        val limit = HealthOverviewPolicy.REVIEW_LIMIT
        val states = listOf(HealthImportState.REVIEW, HealthImportState.TABLE_REVIEW)
        val streams = states.joinToString(" UNION ALL ") {
            "SELECT id,created_at FROM (SELECT id,created_at FROM jobs WHERE state=? ORDER BY created_at DESC,id DESC LIMIT $limit)"
        }
        return helper.readableDatabase.rawQuery("SELECT id,state,payload FROM jobs WHERE id IN " +
            "(SELECT id FROM ($streams) ORDER BY created_at DESC,id DESC LIMIT $limit) ORDER BY created_at DESC,id DESC",
            states.map { it.name }.toTypedArray()).use {
            buildList { while (it.moveToNext()) add(decodeJob(it.getString(0), it.getString(1), it.getBlob(2))) }
        }
    }
    fun reviewJobs(before: HealthReportReviewCursor?): List<HealthImportJob> {
        val states = listOf(HealthImportState.REVIEW, HealthImportState.TABLE_REVIEW)
        val args = mutableListOf<String>()
        val streams = states.joinToString(" UNION ALL ") { state ->
            args += state.name
            val clause = if (before == null) "" else {
                args += listOf(before.createdAt.toString(), before.createdAt.toString(), before.id)
                " AND (created_at<? OR (created_at=? AND id<?))"
            }
            "SELECT id,created_at FROM (SELECT id,created_at FROM jobs WHERE state=?$clause ORDER BY created_at DESC,id DESC LIMIT 30)"
        }
        return helper.readableDatabase.rawQuery(
            "SELECT id,state,payload FROM jobs WHERE id IN (SELECT id FROM ($streams) ORDER BY created_at DESC,id DESC LIMIT 30) ORDER BY created_at DESC,id DESC",
            args.toTypedArray()
        ).use { rows -> buildList { while (rows.moveToNext()) add(decodeJob(rows.getString(0), rows.getString(1), rows.getBlob(2))) } }
    }
    fun pendingJobs(after: Pair<Long, String>? = null): List<HealthImportJob> {
        val cursor = if (after == null) "" else " AND (created_at<? OR (created_at=? AND id<?))"
        val args = after?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        return helper.readableDatabase.rawQuery("SELECT id,state,payload FROM jobs WHERE state IN ('QUEUED','COPYING','RECOGNIZING')$cursor ORDER BY created_at DESC,id DESC LIMIT 100", args)
            .use { buildList { while (it.moveToNext()) add(decodeJob(it.getString(0), it.getString(1), it.getBlob(2))) } }
    }

    @Synchronized fun updateJob(id: String, restartCancelled: Boolean = false, update: (HealthImportJob) -> HealthImportJob): HealthImportJob? {
        val db = helper.writableDatabase
        var reviewChanged = false
        db.beginTransaction()
        return try {
            val current = job(id) ?: return null
            val next = update(current)
            require(next.id == current.id && next.createdAt == current.createdAt)
            if (current.state == HealthImportState.CANCELLED && !(restartCancelled && next.state == HealthImportState.QUEUED)) return current
            check(db.update("jobs", jobValues(next), "id=?", arrayOf(id)) == 1)
            db.setTransactionSuccessful()
            reviewChanged = current.state != next.state && (current.state in REVIEW_STATES || next.state in REVIEW_STATES)
            next
        } finally {
            db.endTransaction()
            notifyChanged()
            if (reviewChanged) notifyReportReviews(context)
        }
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
    ): HealthOriginal = writeOriginal(id, input, name, mime, source, checkCancelled, progress)

    private fun writeOriginal(
        id: String, input: InputStream, name: String, mime: String, source: String,
        checkCancelled: () -> Unit, progress: (Long) -> Unit = {}, privateReview: Boolean? = null,
        cropFiles: HealthCropFiles? = null,
        inspect: ((() -> InputStream) -> Unit)? = null,
        publish: ((SQLiteDatabase, HealthOriginal) -> Unit)? = null
    ): HealthOriginal {
        require(validId(id))
        originalForJob(id)?.takeIf(::present)?.let { return it }
        val streamId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val job = job(id)
        val capturedAt = job?.createdAt ?: now
        val reviewOnly = privateReview ?: (job?.let { !it.keepOriginal && !it.originalOnly } == true)
        val folder = SimpleDateFormat("yyyy/MM", Locale.ROOT).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(Date(capturedAt))
        val relative = cropFiles?.relativePath ?: "$folder/$id-$streamId.ghealth"
        val destination = cropFiles?.destination ?: File(root, relative)
        check(destination.parentFile!!.isDirectory || destination.parentFile!!.mkdirs())
        val existing = originalForJob(id)
        if (cropFiles == null) destination.parentFile!!.listFiles().orEmpty().filter {
            it.name.startsWith("$id-") && it.extension in listOf("partial", "ghealth") && it != existing?.let(::file)
        }.forEach { check(it.delete()) { "Cannot clean interrupted health import" } }
        val staging = cropFiles?.staging ?: File(destination.parentFile, "$id-$streamId.partial")
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
            inspect?.invoke {
                val raw = staging.inputStream()
                try { primitive(key).newDecryptingStream(raw, aad("stream", streamId)) }
                catch (failure: Throwable) { raw.close(); throw failure }
            }
            checkCancelled()
            val hash = digest.digest().joinToString("") { "%02x".format(it) }
            val token = if (reviewOnly) "$REVIEW_PREFIX$id" else AgentMemoryIndexKey.token("$databaseName|health-original-digest|$hash")
            val db = helper.writableDatabase
            db.beginTransaction()
            var committed = false
            try {
                val previous = db.rawQuery("SELECT id,payload FROM originals WHERE digest_token=?", arrayOf(token)).use {
                    if (it.moveToFirst()) decodeOriginal(it.getString(0), it.getBlob(1)) else null
                } ?: existing?.takeIf { reviewOnly && it.reviewOnly && it.id == id }
                if (previous != null) check(previous.sha256 == hash && previous.size == total && previous.reviewOnly == reviewOnly) { "Health digest index mismatch" }
                if (previous != null && present(previous)) {
                    mapImport(db, id, previous.id)
                    publish?.invoke(db, previous)
                    checkCancelled(); db.setTransactionSuccessful()
                    return previous
                }
                val original = HealthOriginal(previous?.id ?: id, streamId, previous?.name ?: name.take(240).ifBlank { "document" }, previous?.mime ?: mime.take(120), total,
                    hash, previous?.importedAt ?: now, relative, previous?.source ?: source, reviewOnly)
                val values = ContentValues().apply {
                    put("id", original.id); put("imported_at", original.importedAt); put("digest_token", token); put("kind", HealthOriginalKind.of(original).name)
                    put("payload", pack("original", original.id, original.json()))
                    put("key_payload", AgentStorageCipher.encryptBinary(key, aad("key", original.id)))
                }
                if (previous == null) db.insertOrThrow("originals", null, values)
                else check(db.update("originals", values, "id=?", arrayOf(previous.id)) == 1)
                if (cropFiles == null) Files.move(staging.toPath(), destination.toPath()) else cropFiles.publish()
                mapImport(db, id, original.id)
                publish?.invoke(db, original)
                checkCancelled(); db.setTransactionSuccessful(); committed = true
                return original
            } finally {
                db.endTransaction()
                if (!committed) destination.delete()
                notifyChanged("originals")
            }
        } finally { staging.delete(); key.fill(0) }
    }

    @Synchronized internal fun saveCrop(id: String, input: InputStream, spec: HealthCropSpec,
        checkCancelled: () -> Unit = {}): HealthOriginal =
        HealthCropRecovery(root).write(id, ::cropReferenced) { files -> saveCrop(id, input, spec, files, checkCancelled) }

    @Synchronized internal fun recoverCropWrites() = HealthCropRecovery(root).recover(::cropReferenced)

    private fun cropReferenced(id: String, relativePath: String) = originalForJob(id)?.relativePath == relativePath

    private fun saveCrop(id: String, input: InputStream, spec: HealthCropSpec, files: HealthCropFiles,
        checkCancelled: () -> Unit): HealthOriginal {
        check(job(id) == null && originalForJob(id) == null)
        val parent = requireNotNull(original(spec.parentId)).also { check(present(it) && it.mime.startsWith("image/")) }
        val batch = spec.batchId?.let(::editableCapture)
        val mode = batch?.mode ?: spec.mode
        val keepOriginal = batch?.keepOriginal ?: spec.keepOriginal
        fun pageToReplace(): HealthPhotoPage? = spec.pageId?.let { id ->
            val page = requireNotNull(capturePage(id))
            val prior = requireNotNull(job(id))
            check(page.batchId == spec.batchId && prior.originalId == parent.id &&
                prior.state == HealthImportState.CAPTURE_READY && page.quality != null)
            page
        }
        pageToReplace()
        var quality: HealthPhotoQuality? = null
        val cropped = writeOriginal(id, input, spec.name, spec.mime, "crop:${parent.id}", checkCancelled,
            privateReview = !keepOriginal, cropFiles = files,
            inspect = { open -> quality = HealthPhotoInspector.inspect(open, report = batch != null && mode == "report") },
            publish = { db, derivative ->
                check(original(parent.id) == parent && present(parent))
                if (batch != null) check(editableCapture(batch.id) == batch)
                val page = pageToReplace()
                val next = HealthImportJob(id, HealthOriginalContentProvider.uri(context, derivative.id, spec.fixture).toString(),
                    System.currentTimeMillis(), mode = mode, name = derivative.name, mime = derivative.mime,
                    totalBytes = derivative.size, copiedBytes = derivative.size, originalId = derivative.id,
                    state = if (page == null) HealthImportState.QUEUED else HealthImportState.CAPTURE_READY,
                    captureBatch = batch?.id.orEmpty(), keepOriginal = keepOriginal)
                db.insertOrThrow("jobs", null, jobValues(next))
                if (page != null) {
                    check(db.delete("capture_pages", "job_id=?", arrayOf(page.jobId)) == 1)
                    check(db.delete("jobs", "id=?", arrayOf(page.jobId)) == 1)
                    db.insertOrThrow("capture_pages", null, pageValues(page.copy(jobId = id, quality = requireNotNull(quality))))
                }
            })
        if (batch != null && parent.reviewOnly) runCatching { releaseReviewOriginal(parent.id) }
        notifyChanged("capture"); notifyChanged()
        return cropped
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
    internal fun readChannel(original: HealthOriginal): SeekableByteChannel = openChannel(original)
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
    fun removeReviewedOriginal(expected: HealthOriginal, verifyScope: () -> Unit) {
        val db = helper.writableDatabase
        db.beginTransactionNonExclusive()
        try {
            val path = file(expected)
            if (original(expected.id) != expected || !path.isFile) throw HealthOriginalRemovalChanged()
            verifyScope()
            if (expected.reviewOnly) check(db.update("originals",
                ContentValues().apply { put("digest_token", "$RELEASED_PREFIX${expected.id}") },
                "id=? AND digest_token=?", arrayOf(expected.id, "$REVIEW_PREFIX${expected.id}")) == 1)
            check(path.delete()) { "Health original file could not be removed" }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        notifyChanged("originals")
    }
    fun releaseReviewOriginal(jobId: String): Boolean {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val original = original(jobId) ?: return true
            if (!original.reviewOnly) return true
            val path = file(original)
            if (path.exists() && !path.delete()) return false
            db.update("originals", ContentValues().apply { put("digest_token", "$RELEASED_PREFIX$jobId") },
                "id=? AND digest_token=?", arrayOf(jobId, "$REVIEW_PREFIX$jobId"))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        notifyChanged("originals")
        return true
    }

    fun reviewOriginalIds(after: String): List<String> = helper.readableDatabase.rawQuery(
        "SELECT id FROM originals WHERE digest_token>? AND digest_token<'review;' ORDER BY digest_token LIMIT 30",
        arrayOf("$REVIEW_PREFIX$after")).use { rows -> buildList { while (rows.moveToNext()) add(rows.getString(0)) } }
    fun createCaptureBatch(batch: HealthPhotoBatch) {
        require(validId(batch.id) && batch.mode in listOf("report", "device") && !batch.submitted)
        helper.writableDatabase.insertOrThrow("capture_batches", null, ContentValues().apply {
            put("id", batch.id); put("payload", pack("capture-batch", batch.id, batch.json()))
        }); notifyChanged("capture")
    }
    fun captureBatch(id: String): HealthPhotoBatch? = helper.readableDatabase.rawQuery("SELECT payload FROM capture_batches WHERE id=?", arrayOf(id)).use {
        if (it.moveToFirst()) HealthPhotoBatch.from(unpack("capture-batch", id, it.getBlob(0))).also { batch -> check(batch.id == id) } else null
    }
    private fun editableCapture(id: String) = requireNotNull(captureBatch(id)).also { check(!it.submitted) { "Capture has already been submitted" } }
    private fun pageValues(page: HealthPhotoPage) = ContentValues().apply {
        put("job_id", page.jobId); put("batch_id", page.batchId); put("position", page.position)
        put("payload", pack("capture-page", page.jobId, page.json()))
    }
    fun capturePage(id: String): HealthPhotoPage? = helper.readableDatabase.rawQuery("SELECT batch_id,position,payload FROM capture_pages WHERE job_id=?", arrayOf(id)).use {
        if (it.moveToFirst()) HealthPhotoPage.from(unpack("capture-page", id, it.getBlob(2))).also { page ->
            check(page.jobId == id && page.batchId == it.getString(0) && page.position == it.getInt(1))
        } else null
    }
    fun capturePages(batch: String, after: Int = -1): List<HealthPhotoPage> = helper.readableDatabase.rawQuery(
        "SELECT job_id FROM capture_pages WHERE batch_id=? AND position>? ORDER BY position LIMIT 20", arrayOf(batch, after.toString())
    ).use { buildList { while (it.moveToNext()) add(requireNotNull(capturePage(it.getString(0)))) } }
    fun capturePageCount(batch: String): Int = helper.readableDatabase.rawQuery("SELECT COUNT(*) FROM capture_pages WHERE batch_id=?", arrayOf(batch))
        .use { it.moveToFirst(); it.getInt(0) }
    fun capturePageNumber(id: String): Int? = capturePage(id)?.let { page ->
        helper.readableDatabase.rawQuery("SELECT COUNT(*) FROM capture_pages WHERE batch_id=? AND position<=?", arrayOf(page.batchId, page.position.toString()))
            .use { it.moveToFirst(); it.getInt(0) }
    }
    @Synchronized fun addCaptureJob(batch: String, job: HealthImportJob, replace: String? = null) {
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            val owner = editableCapture(batch)
            require(job.captureBatch == batch && !job.captureSubmitted && job.mode == owner.mode && validId(job.id) && job.sourceUri.startsWith("content://"))
            val previous = replace?.let { requireNotNull(capturePage(it)).also { old -> require(old.batchId == batch) } }
            val position = previous?.position ?: db.rawQuery("SELECT COALESCE(MAX(position),-1)+1 FROM capture_pages WHERE batch_id=?", arrayOf(batch)).use { it.moveToFirst(); it.getInt(0) }
            db.insertOrThrow("jobs", null, jobValues(job.copy(keepOriginal = owner.keepOriginal)))
            if (previous != null) {
                updateJob(previous.jobId) { it.copy(state = HealthImportState.CANCELLED) }
                db.delete("capture_pages", "job_id=?", arrayOf(previous.jobId))
                db.delete("jobs", "id=?", arrayOf(previous.jobId))
            }
            db.insertOrThrow("capture_pages", null, pageValues(HealthPhotoPage(job.id, batch, position)))
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); notifyChanged("capture") }
        replace?.let { runCatching { releaseReviewOriginal(it) } }
    }
    @Synchronized fun inspectCapture(id: String, quality: HealthPhotoQuality) {
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            val page = requireNotNull(capturePage(id)); editableCapture(page.batchId)
            val job = requireNotNull(job(id))
            if (job.state == HealthImportState.CANCELLED) return
            check(!job.captureSubmitted && job.originalId.isNotBlank())
            db.update("capture_pages", pageValues(page.copy(quality = quality)), "job_id=?", arrayOf(id))
            db.update("jobs", jobValues(job.copy(state = HealthImportState.CAPTURE_READY)), "id=?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); notifyChanged("capture"); notifyChanged() }
    }
    @Synchronized fun moveCapturePage(id: String, direction: Int) {
        require(direction in listOf(-1, 1))
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            val page = requireNotNull(capturePage(id)); editableCapture(page.batchId)
            val neighbour = db.rawQuery("SELECT job_id FROM capture_pages WHERE batch_id=? AND position${if (direction < 0) "<" else ">"}? ORDER BY position ${if (direction < 0) "DESC" else "ASC"} LIMIT 1",
                arrayOf(page.batchId, page.position.toString())).use { if (it.moveToFirst()) capturePage(it.getString(0)) else null } ?: return
            db.update("capture_pages", pageValues(page.copy(position = neighbour.position)), "job_id=?", arrayOf(page.jobId))
            db.update("capture_pages", pageValues(neighbour.copy(position = page.position)), "job_id=?", arrayOf(neighbour.jobId))
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); notifyChanged("capture") }
    }
    @Synchronized fun removeCapturePage(id: String) {
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            val page = capturePage(id) ?: return; editableCapture(page.batchId)
            updateJob(id) { it.copy(state = HealthImportState.CANCELLED) }
            db.delete("capture_pages", "job_id=?", arrayOf(id)); db.delete("jobs", "id=?", arrayOf(id)); db.setTransactionSuccessful()
        } finally { db.endTransaction(); notifyChanged("capture") }
        runCatching { releaseReviewOriginal(id) }
    }
    @Synchronized fun captureMode(id: String, mode: String) {
        require(mode in listOf("report", "device"))
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            val batch = editableCapture(id)
            db.update("capture_batches", ContentValues().apply { put("payload", pack("capture-batch", id, batch.copy(mode = mode).json())) }, "id=?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); notifyChanged("capture") }
    }
    @Synchronized fun submitCaptureBatch(id: String): List<String> {
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            val batch = editableCapture(id)
            val ids = db.rawQuery("SELECT job_id FROM capture_pages WHERE batch_id=? ORDER BY position", arrayOf(id))
                .use { buildList { while (it.moveToNext()) add(it.getString(0)) } }
            require(ids.isNotEmpty())
            ids.forEachIndexed { index, jobId ->
                val page = requireNotNull(capturePage(jobId)); val job = requireNotNull(job(jobId))
                check(page.quality != null && job.state == HealthImportState.CAPTURE_READY && original(job.originalId)?.let(::present) == true) { "Capture pages are not ready" }
                db.update("jobs", jobValues(job.copy(mode = batch.mode, captureSubmitted = true, documentPage = index + 1, state = HealthImportState.QUEUED, error = "")), "id=?", arrayOf(jobId))
            }
            db.update("capture_batches", ContentValues().apply { put("payload", pack("capture-batch", id, batch.copy(submitted = true).json())) }, "id=?", arrayOf(id))
            db.setTransactionSuccessful(); return ids
        } finally { db.endTransaction(); notifyChanged("capture"); notifyChanged() }
    }
    @Synchronized fun discardEmptyCapture(id: String) {
        val db = helper.writableDatabase; db.beginTransaction()
        try {
            if (captureBatch(id)?.submitted == false && capturePageCount(id) == 0) db.delete("capture_batches", "id=?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String, private val classify: (String, ByteArray) -> String) : SQLiteOpenHelper(context, name, null, 4) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) = createOriginalTables(db)
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1..3 && newVersion == 4)
            if (oldVersion == 3) {
                HealthOriginalLibraryStore.createHistoryIndex(db)
                return
            }
            if (oldVersion < 2) captureSchema(db)
            db.execSQL("ALTER TABLE originals ADD COLUMN kind TEXT NOT NULL DEFAULT 'OTHER'")
            db.rawQuery("SELECT id,payload FROM originals", null).use { rows -> while (rows.moveToNext()) {
                val id = rows.getString(0); val kind = classify(id, rows.getBlob(1))
                check(db.update("originals", ContentValues().apply { put("kind", kind) }, "id=?", arrayOf(id)) == 1)
            } }
            db.execSQL("CREATE INDEX original_kind_page ON originals(kind,imported_at DESC,id DESC)")
            HealthOriginalLibraryStore.createSchema(db)
        }
    }
    companion object {
        const val LEGACY_DATABASE = "health_originals_v1.db"
        private const val REVIEW_PREFIX = "review:"
        private const val RELEASED_PREFIX = "released:"
        private const val ARCHIVED = "digest_token NOT LIKE 'review:%' AND digest_token NOT LIKE 'released:%'"
        private val REVIEW_STATES = setOf(HealthImportState.REVIEW, HealthImportState.TABLE_REVIEW)

        fun createSharedSchema(db: SQLiteDatabase) {
            createOriginalTables(db)
            db.execSQL("CREATE TABLE health_original_metadata_migration(id INTEGER PRIMARY KEY CHECK(id=1),source TEXT NOT NULL)")
        }

        private fun createOriginalTables(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE originals(id TEXT PRIMARY KEY,imported_at INTEGER NOT NULL,digest_token TEXT UNIQUE NOT NULL,payload BLOB NOT NULL,key_payload BLOB NOT NULL,kind TEXT NOT NULL)")
            db.execSQL("CREATE INDEX original_page ON originals(imported_at DESC,id DESC)")
            db.execSQL("CREATE INDEX original_kind_page ON originals(kind,imported_at DESC,id DESC)")
            db.execSQL("CREATE TABLE imports(job_id TEXT PRIMARY KEY,original_id TEXT NOT NULL REFERENCES originals(id))")
            db.execSQL("CREATE TABLE jobs(id TEXT PRIMARY KEY,created_at INTEGER NOT NULL,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX job_page ON jobs(created_at DESC,id DESC)")
            db.execSQL("CREATE INDEX job_pending ON jobs(state,created_at DESC,id DESC)")
            db.execSQL("CREATE TABLE pages(job_id TEXT NOT NULL REFERENCES jobs(id),page_number INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(job_id,page_number))")
            captureSchema(db); HealthOriginalLibraryStore.createSchema(db)
        }
        private fun captureSchema(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE capture_batches(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE capture_pages(job_id TEXT PRIMARY KEY REFERENCES jobs(id),batch_id TEXT NOT NULL REFERENCES capture_batches(id),position INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX capture_page_order ON capture_pages(batch_id,position)")
        }
        fun changesUri(context: Context): Uri = Uri.parse("content://${context.packageName}.health-originals/changes")
        fun reportChanges(context: Context): Uri = changesUri(context).buildUpon().appendPath("report-reviews").build()
        fun notifyReportReviews(context: Context) = context.contentResolver.notifyChange(reportChanges(context), null)
        private val reader by lazy { Handler(HandlerThread("health-original-reader").apply { start() }.looper) }
    }
}
