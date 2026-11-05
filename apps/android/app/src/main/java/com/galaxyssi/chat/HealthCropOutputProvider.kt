package com.galaxyssi.chat

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Binder
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import java.io.FileNotFoundException
import java.io.FilterInputStream
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal const val HEALTH_CROP_BATCH = "health_crop_batch"
internal const val HEALTH_CROP_PAGE = "health_crop_page"
internal const val HEALTH_CROP_MODE = "health_crop_mode"
internal const val HEALTH_CROP_RESULT = "health_crop_result"

internal data class HealthCropSpec(val parentId: String, val name: String, val mime: String,
    val batchId: String? = null, val pageId: String? = null, val mode: String = "report", val keepOriginal: Boolean = true,
    val fixture: String? = null) {
    init {
        require(HealthProfilePolicy.uuid(parentId) && (batchId == null) == (pageId == null))
        require(batchId == null || HealthProfilePolicy.uuid(batchId) && HealthProfilePolicy.uuid(requireNotNull(pageId)))
        require(mode in setOf("report", "device") && mime in setOf("image/jpeg", "image/png"))
        require(fixture == null || BuildConfig.DEBUG && HealthProfilePolicy.uuid(fixture))
    }
}

/** One writer, same UID, no grants. The crop library writes image bytes into a bounded OS pipe. */
class HealthCropOutputProvider : ContentProvider() {
    override fun onCreate() = true
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (Binder.getCallingUid() != Process.myUid() || mode !in setOf("w", "wt") || uri.query != null)
            throw FileNotFoundException("Crop output is private")
        val token = uri.pathSegments.singleOrNull() ?: throw FileNotFoundException("Invalid crop output")
        if (!TOKEN.matches(token)) throw FileNotFoundException("Invalid crop output")
        return HealthCropOutput.writer(token, discardStale = mode == "wt")
    }
    override fun getType(uri: Uri): String? = null
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    private companion object {
        val TOKEN = Regex("[0-9a-f-]{36}\\.(png|jpg)")
    }
}

internal class HealthCropOutput private constructor(context: Context, private val spec: HealthCropSpec,
    private val complete: (String, Result<HealthOriginal>) -> Unit) {
    private val app = context.applicationContext
    private val id = UUID.randomUUID().toString()
    private val token = "$id.${if (spec.mime == "image/png") "png" else "jpg"}"
    val uri: Uri = Uri.parse("content://${app.packageName}.health-crop-output/$token")
    private val encoded = CompletableFuture<Boolean>()
    private val completed = AtomicBoolean()
    private val cancelled = AtomicBoolean()
    private var opened = false

    @Synchronized private fun openWriter(): ParcelFileDescriptor {
        if (opened || completed.get() || cancelled.get()) throw FileNotFoundException("Crop output is no longer available")
        val pipe = ParcelFileDescriptor.createReliablePipe()
        opened = true
        workers.execute { save(pipe[0]) }
        return pipe[1]
    }

    @Synchronized fun finishEncoding(success: Boolean) {
        encoded.complete(success)
        if (!opened) finish(Result.failure(IOException("Crop encoder did not open the output")))
    }

    fun cancel() {
        cancelled.set(true)
        finishEncoding(false)
    }

    private fun checkActive() {
        if (cancelled.get() || encoded.getNow(true) == false) throw IOException("Crop encoding was cancelled or failed")
    }

    private fun save(descriptor: ParcelFileDescriptor) {
        val result = runCatching { ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { raw ->
            val input = CropEncodedInput(raw, spec.mime) {
                // The pipe can close before the encoder callback; both must succeed.
                descriptor.checkError()
                val successful = try { encoded.get(60, TimeUnit.SECONDS) }
                catch (failure: java.util.concurrent.TimeoutException) { encoded.complete(false); throw failure }
                if (!successful) throw IOException("Crop encoder failed")
                checkActive()
            }
            try {
                runCatching {
                    val names = HealthOverviewDatabases(spec.fixture)
                    HealthOriginalStore(app, names.originals, names.originalRoot(app)).use { originals ->
                        originals.saveCrop(id, input, spec, ::checkActive)
                    }
                }.also {
                    // The library's encoder does not catch output exceptions. Drain cancelled output without saving it.
                    if (it.isFailure && !input.ended) {
                        val discard = ByteArray(64 * 1024)
                        try { runCatching { while (raw.read(discard) >= 0) Unit } } finally { discard.fill(0) }
                    }
                }.getOrThrow()
            } finally { input.wipe() }
        } }
        encoded.whenComplete { _, _ -> finish(result) }
    }

    private fun finish(result: Result<HealthOriginal>) {
        if (!completed.compareAndSet(false, true)) return
        active.remove(token, this)
        main.post { complete(id, result) }
    }

    companion object {
        private val workers = Executors.newFixedThreadPool(2) { task -> Thread(task, "health-crop-encryption").apply { isDaemon = true } }
        private val main = Handler(Looper.getMainLooper())
        private val active = ConcurrentHashMap<String, HealthCropOutput>()

        fun start(context: Context, spec: HealthCropSpec, complete: (String, Result<HealthOriginal>) -> Unit): HealthCropOutput =
            HealthCropOutput(context, spec, complete).also { active[it.token] = it }

        fun writer(token: String, discardStale: Boolean): ParcelFileDescriptor = try {
            active[token]?.openWriter() ?: throw FileNotFoundException("Unknown crop output")
        } catch (failure: FileNotFoundException) {
            if (!discardStale) throw failure
            ParcelFileDescriptor.open(File("/dev/null"), ParcelFileDescriptor.MODE_WRITE_ONLY)
        }
    }
}

private class CropEncodedInput(input: java.io.InputStream, mime: String, private val finished: () -> Unit) : FilterInputStream(input) {
    private val end = if (mime == "image/png") byteArrayOf(0, 0, 0, 0, 73, 69, 78, 68, -82, 66, 96, -126)
        else byteArrayOf(-1, -39)
    private val tail = ByteArray(end.size)
    private var cursor = 0
    var ended = false
        private set

    private fun append(value: Byte) {
        tail[cursor] = value
        cursor = (cursor + 1) % tail.size
    }

    private fun eof() {
        ended = true
        finished()
        if (!end.indices.all { end[it] == tail[(cursor + it) % tail.size] }) throw IOException("Incomplete crop image")
    }

    override fun read(): Int = super.read().also { if (it < 0) eof() else append(it.toByte()) }

    override fun read(bytes: ByteArray, offset: Int, length: Int): Int = super.read(bytes, offset, length).also { count ->
        if (count < 0) eof() else for (index in maxOf(0, count - tail.size) until count) append(bytes[offset + index])
    }

    fun wipe() = tail.fill(0)
}
