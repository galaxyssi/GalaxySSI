package com.galaxyssi.chat

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.io.File
import java.util.Locale

internal enum class PeerAttachmentOpenResult {
    OPENED, NO_READER, UNREADABLE, FAILED
}

internal object PeerAttachmentOpen {
    const val PDF_MIME = "application/pdf"
    private const val GENERIC_MIME = "application/octet-stream"
    private const val SAMSUNG_FILES = "com.sec.android.app.myfiles"

    fun mimeType(name: String, declared: String): String {
        val value = declared.substringBefore(';').trim().lowercase(Locale.ROOT)
        val generic = value.isBlank() || value in setOf(GENERIC_MIME, "binary/octet-stream", "*/*")
        if (value == "application/x-pdf" || generic && name.endsWith(".pdf", ignoreCase = true)) return PDF_MIME
        return if (generic) GENERIC_MIME else value
    }

    fun open(context: Context, source: Uri, name: String, mime: String, startActivity: (Intent) -> Unit): PeerAttachmentOpenResult {
        val readable = when (source.scheme) {
            "content" -> source
            "file" -> source.path?.let { path ->
                runCatching { LocalAttachmentUris.forFile(context, File(path), name, mime) }.getOrNull()
            }
            else -> null
        } ?: return PeerAttachmentOpenResult.UNREADABLE
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(readable, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri(name, readable)
        }
        // Let Android select the user's default without a package-visibility preflight.
        return launch(intent, startActivity)
    }

    fun openDownloads(startActivity: (Intent) -> Unit): Boolean {
        val downloads = Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
        return launch(Intent(downloads).setPackage(SAMSUNG_FILES), startActivity) == PeerAttachmentOpenResult.OPENED ||
            launch(downloads, startActivity) == PeerAttachmentOpenResult.OPENED
    }

    private fun launch(intent: Intent, startActivity: (Intent) -> Unit): PeerAttachmentOpenResult =
        try {
            startActivity(intent)
            PeerAttachmentOpenResult.OPENED
        } catch (_: ActivityNotFoundException) {
            PeerAttachmentOpenResult.NO_READER
        } catch (_: SecurityException) {
            PeerAttachmentOpenResult.UNREADABLE
        } catch (_: RuntimeException) {
            PeerAttachmentOpenResult.FAILED
        }
}
