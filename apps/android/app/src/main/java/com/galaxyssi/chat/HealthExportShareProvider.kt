package com.galaxyssi.chat

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import java.io.FileNotFoundException
import java.nio.ByteBuffer
import java.nio.channels.SeekableByteChannel

/** Exact URI grants provide read-only, authenticated access to one completed artifact. */
class HealthExportShareProvider : ContentProvider() {
    private data class Request(val kind: HealthExportShareKind, val id: String, val attempt: String, val fixture: String?)
    private val app get() = requireNotNull(context)
    override fun onCreate() = true

    private fun request(uri: Uri): Request {
        val all = uri.pathSegments
        val fixture = all.getOrNull(1)?.takeIf {
            BuildConfig.DEBUG && all.size == 5 && all[0] == "fixture" && HealthProfilePolicy.uuid(it)
        }
        val path = if (fixture == null) all else all.drop(2)
        val kind = HealthExportShareKind.entries.firstOrNull { it.path == path.firstOrNull() }
        if (uri.scheme != "content" || uri.authority != HealthExportShare.authority(app) || uri.query != null || uri.fragment != null ||
            kind == null || path.size != 3 || !HealthProfilePolicy.uuid(path[1]) || !HealthProfilePolicy.uuid(path[2]))
            throw unavailable()
        if (uri.encodedPath != "/" + all.joinToString("/")) throw unavailable()
        return Request(kind, path[1], path[2], fixture)
    }

    private fun <T> artifact(uri: Uri, read: (HealthExportShareItem, () -> SeekableByteChannel) -> T): T {
        val request = request(uri)
        return when (request.kind) {
            HealthExportShareKind.RECORDS -> HealthExportShare.openRecords(app, request.fixture).use { store ->
                val session = store.session(request.id)?.takeIf { it.attempt == request.attempt && it.artifactBytes > 0 &&
                    it.state in setOf(HealthRecordExportState.GENERATED, HealthRecordExportState.SAVED) } ?: throw unavailable()
                read(HealthExportShareItem.records(session)) { store.readChannel(session) }
            }
            HealthExportShareKind.ORIGINALS -> HealthExportShare.openOriginals(app, request.fixture).use { originals ->
                val store = HealthExportShare.originalLibrary(app, originals, request.fixture)
                val session = store.session(request.id)?.takeIf { it.attempt == request.attempt && it.archiveBytes > 0 &&
                    it.state in setOf(HealthOriginalExportState.GENERATED, HealthOriginalExportState.SAVED) } ?: throw unavailable()
                read(HealthExportShareItem.originals(session)) { store.readChannel(session) }
            }
        }
    }

    override fun getType(uri: Uri): String? {
        val uid = Binder.getCallingUid()
        if (uid != Process.myUid() && app.checkUriPermission(uri, Binder.getCallingPid(), uid,
                Intent.FLAG_GRANT_READ_URI_PERMISSION) != PackageManager.PERMISSION_GRANTED) return "application/octet-stream"
        return try { artifact(uri) { item, _ -> item.mime } } catch (_: Exception) { null }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?,
                       sortOrder: String?): Cursor {
        val supported = listOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val columns = projection?.filter { it in supported } ?: supported
        return artifact(uri) { item, _ -> MatrixCursor(columns.toTypedArray()).apply {
            addRow(columns.map { if (it == OpenableColumns.DISPLAY_NAME) item.name else item.size })
        } }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Health exports are read-only")
        return try { artifact(uri) { item, channel -> descriptor(app, item.size, channel()) } }
        catch (_: Exception) { throw unavailable() }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()

    private fun unavailable() = FileNotFoundException("Health export unavailable")

    companion object {
        private val reader by lazy { Handler(HandlerThread("health-export-share").apply { start() }.looper) }

        private fun descriptor(context: Context, length: Long, channel: SeekableByteChannel): ParcelFileDescriptor = try {
            check(channel.size() == length)
            context.getSystemService(StorageManager::class.java).openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY,
                object : ProxyFileDescriptorCallback() {
                    override fun onGetSize() = length
                    @Synchronized override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
                        try {
                            require(offset >= 0 && size in 0..data.size)
                            if (offset >= length) return 0
                            val count = minOf(size.toLong(), length - offset).toInt()
                            val target = ByteBuffer.wrap(data, 0, count)
                            channel.position(offset)
                            while (target.hasRemaining()) check(channel.read(target) > 0)
                            return count
                        } catch (failure: Exception) {
                            data.fill(0)
                            throw ErrnoException("health-export-read", OsConstants.EIO, failure)
                        }
                    }
                    @Synchronized override fun onRelease() { runCatching { channel.close() } }
                }, reader)
        } catch (failure: Throwable) {
            runCatching { channel.close() }
            throw failure
        }
    }
}
