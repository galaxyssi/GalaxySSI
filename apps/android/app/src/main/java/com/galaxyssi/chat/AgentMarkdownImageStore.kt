package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.InetAddress
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request

internal object AgentMarkdownImageStore {
    private const val MAX_BYTES = 12 * 1024 * 1024
    private const val CACHE_BYTES = 64L * 1024 * 1024
    private val locks = Array(8) { Any() }
    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false)
        .dns(object : Dns {
            override fun lookup(hostname: String): List<InetAddress> = Dns.SYSTEM.lookup(hostname).also { addresses ->
                if (addresses.isEmpty() || addresses.any { !isPublic(it) }) {
                    throw UnknownHostException("Non-public image destination")
                }
            }
        }).build()

    fun load(context: Context, source: String): File {
        require(AgentMarkdownImages.isWebSource(source) && source.startsWith("https://", true))
        val key = MessageDigest.getInstance("SHA-256").digest(source.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return synchronized(locks[(key.hashCode() and Int.MAX_VALUE) % locks.size]) {
            val file = cacheFile(context, source)
            if (file.isFile && file.length() in 1..MAX_BYTES.toLong()) return@synchronized file
            var url = source
            repeat(6) {
                val request = Request.Builder().url(url)
                    .header("User-Agent", "GalaxySSI/Android (+https://github.com/galaxyssi/GalaxySSI)")
                    .get().build()
                require(request.url.isHttps && request.url.username.isEmpty() && request.url.password.isEmpty())
                http.newCall(request).execute().use { response ->
                    if (response.code in setOf(301, 302, 303, 307, 308)) {
                        url = request.url.resolve(response.header("Location").orEmpty())?.toString()
                            ?: error("Invalid image redirect")
                    } else {
                        check(response.isSuccessful) { "Image HTTP ${response.code}" }
                        val body = response.body ?: error("Image body missing")
                        check(body.contentLength() <= MAX_BYTES) { "Image too large" }
                        val bytes = body.byteStream().use { input ->
                            val output = ByteArrayOutputStream()
                            val buffer = ByteArray(16 * 1024)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                check(output.size() + count <= MAX_BYTES) { "Image too large" }
                                output.write(buffer, 0, count)
                            }
                            output.toByteArray()
                        }
                        cache(context, source, bytes)
                        return@synchronized file
                    }
                }
            }
            error("Too many image redirects")
        }
    }

    internal fun cacheFile(context: Context, source: String): File {
        val key = MessageDigest.getInstance("SHA-256").digest(source.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(File(context.cacheDir, "markdown-images"), key)
    }

    @Synchronized internal fun cache(context: Context, source: String, bytes: ByteArray): File {
        require(bytes.size in 1..MAX_BYTES)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Unsupported image data" }
        val file = cacheFile(context, source)
        file.parentFile?.mkdirs()
        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try { output.write(bytes); atomic.finishWrite(output) }
        catch (error: Throwable) { atomic.failWrite(output); throw error }
        var total = file.parentFile?.listFiles()?.sumOf(File::length) ?: 0L
        file.parentFile?.listFiles()?.filter { it != file }?.sortedBy(File::lastModified)?.forEach {
            if (total > CACHE_BYTES) { val size = it.length(); if (it.delete()) total -= size }
        }
        return file
    }

    fun save(context: Context, block: AgentRichBlock): Result<String> = runCatching {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        val file = load(context, block.uri)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        val mime = bounds.outMimeType ?: error("Image format missing")
        val extension = when (mime) {
            "image/jpeg" -> "jpg"; "image/gif" -> "gif"; "image/webp" -> "webp"
            "image/avif" -> "avif"; else -> "png"
        }
        val safeTitle = block.title.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").take(80)
            .ifBlank { "image" }
        val name = safeTitle.substringBeforeLast('.', safeTitle).ifBlank { "image" } + ".$extension"
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/GalaxySSI")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("Download destination unavailable")
        try {
            resolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output) } }
                ?: error("Download stream unavailable")
            resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
        } catch (error: Throwable) { resolver.delete(uri, null, null); throw error }
        "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI/$name"
    }

    private fun isPublic(address: InetAddress): Boolean =
        !address.isAnyLocalAddress && !address.isLoopbackAddress && !address.isLinkLocalAddress &&
            !address.isSiteLocalAddress && !address.isMulticastAddress &&
            !(address.address.size == 16 && (address.address[0].toInt() and 0xfe) == 0xfc)
}
