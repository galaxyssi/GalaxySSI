package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Public inspection copy; the private attachment remains the source used for delivery. */
internal object ScreenAssistantPdfDownloads {
    @Synchronized
    fun save(context: Context, captureId: String, pdf: File): String {
        require(captureId.matches(Regex("[a-f0-9-]{36}")))
        require(pdf.isFile && pdf.length() > 0)
        val name = "article-$captureId.pdf"
        val path = "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI/$name"
        if (Build.VERSION.SDK_INT < 29) {
            val target = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "GalaxySSI/$name")
            if (target.isFile && target.length() == pdf.length()) return path
            check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
            val temp = File(target.parentFile, "$name.pending")
            try {
                pdf.inputStream().use { input -> temp.outputStream().use { input.copyTo(it) } }
                check(temp.renameTo(target))
            } finally { temp.delete() }
            return path
        }
        val resolver = context.contentResolver
        val preferences = context.getSharedPreferences("screen_content_downloads", Context.MODE_PRIVATE)
        val previous = preferences.getString(captureId, null)?.let(Uri::parse)
        if (previous != null && runCatching {
            resolver.openAssetFileDescriptor(previous, "r")?.use { it.length == pdf.length() } == true
        }.getOrDefault(false)) return path
        val uri = checkNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }))
        try {
            pdf.inputStream().use { input ->
                checkNotNull(resolver.openOutputStream(uri, "w")).use { output ->
                    check(input.copyTo(output) == pdf.length())
                }
            }
            check(resolver.update(uri, ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null) == 1)
            check(preferences.edit().putString(captureId, uri.toString()).commit())
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
        return path
    }
}
