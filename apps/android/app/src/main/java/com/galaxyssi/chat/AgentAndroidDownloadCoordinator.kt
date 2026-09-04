package com.galaxyssi.chat

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

internal data class AgentAndroidDownloadRecord(
    val downloadId: Long,
    val conversationId: String,
    val turnId: String,
    val displayName: String,
    val relativePath: String,
    val languageTag: String
)

internal object AgentAndroidDownloadPolicy {
    private val extensionPattern = Regex("\\.[A-Za-z0-9]{1,10}$")
    private val genericTitles = setOf("galaxyssi download", "download")

    fun destinationFileName(
        url: String,
        title: String = "",
        timestampMillis: Long = System.currentTimeMillis()
    ): String {
        val decodedPathName = runCatching {
            URLDecoder.decode(URI(url).path.substringAfterLast('/'), Charsets.UTF_8.name())
        }.getOrDefault("")
        val suppliedTitle = title.trim().takeUnless { it.lowercase(Locale.ROOT) in genericTitles }.orEmpty()
        val pathExtension = extensionPattern.find(decodedPathName)?.value.orEmpty().lowercase(Locale.ROOT)
        val article = isArticleUrl(url)
        val extension = when {
            extensionPattern.containsMatchIn(suppliedTitle) -> ""
            pathExtension.isNotBlank() -> pathExtension
            article -> ".html"
            else -> ".bin"
        }
        val base = when {
            suppliedTitle.isNotBlank() -> suppliedTitle
            decodedPathName.isNotBlank() && pathExtension.isNotBlank() -> decodedPathName.removeSuffix(pathExtension)
            article -> "article"
            else -> "download"
        }
        val safeBase = base
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]+"), "-")
            .trim(' ', '.', '-')
            .take(96)
            .ifBlank { if (article) "article" else "download" }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss-SSS", Locale.US).format(Date(timestampMillis))
        return "$safeBase-$stamp$extension"
    }

    fun relativePath(fileName: String): String = "Download/GalaxySSI/$fileName"

    fun startedMessage(chinese: Boolean): String = if (chinese) {
        "\u5df2\u5f00\u59cb\u4e0b\u8f7d\u3002\u5b8c\u6210\u540e\u6587\u4ef6\u5c06\u4fdd\u5b58\u5230 Download/GalaxySSI\uff0c\u5e76\u663e\u793a\u5728\u5f53\u524d\u4f1a\u8bdd\u4e2d\u3002"
    } else {
        "Download started. When it finishes, the file will be saved in Download/GalaxySSI and shown in this conversation."
    }

    fun completedMessage(chinese: Boolean, displayName: String): String = if (chinese) {
        "\u4e0b\u8f7d\u5b8c\u6210\uff1a$displayName\n\u5df2\u4fdd\u5b58\u5230 Download/GalaxySSI\u3002"
    } else {
        "Download complete: $displayName\nSaved in Download/GalaxySSI."
    }

    fun failedMessage(chinese: Boolean, displayName: String): String = if (chinese) {
        "\u4e0b\u8f7d\u5931\u8d25\uff1a$displayName\u3002\u8bf7\u68c0\u67e5\u7f51\u7edc\u6216\u91cd\u65b0\u4e0b\u8f7d\u3002"
    } else {
        "Download failed: $displayName. Check the connection or try again."
    }

    private fun isArticleUrl(url: String): Boolean {
        val host = runCatching { URI(url).host.orEmpty().lowercase(Locale.ROOT) }.getOrDefault("")
        return host == "mp.weixin.qq.com" || host.endsWith(".mp.weixin.qq.com") ||
            host == "weixin.qq.com" || host.endsWith(".weixin.qq.com")
    }
}

internal class AgentAndroidDownloadStore(context: Context) {
    private val database = AgentEncryptedDatabase(context, DATABASE_NAME)

    fun write(record: AgentAndroidDownloadRecord) {
        database.writeString(key(record.downloadId), JSONObject()
            .put("download_id", record.downloadId)
            .put("conversation_id", record.conversationId)
            .put("turn_id", record.turnId)
            .put("display_name", record.displayName)
            .put("relative_path", record.relativePath)
            .put("language_tag", record.languageTag)
            .toString())
    }

    fun read(downloadId: Long): AgentAndroidDownloadRecord? = runCatching {
        val raw = database.readString(key(downloadId), "")
        if (raw.isBlank()) return@runCatching null
        val json = JSONObject(raw)
        AgentAndroidDownloadRecord(
            downloadId = json.optLong("download_id", downloadId),
            conversationId = json.optString("conversation_id").trim(),
            turnId = json.optString("turn_id").trim(),
            displayName = json.optString("display_name").trim(),
            relativePath = json.optString("relative_path").trim(),
            languageTag = json.optString("language_tag").trim()
        )
    }.getOrNull()

    fun remove(downloadId: Long) = database.remove(key(downloadId))

    private fun key(downloadId: Long) = "download:$downloadId"

    private companion object {
        const val DATABASE_NAME = "galaxyssi_android_downloads_v1"
    }
}

internal object AgentAndroidDownloadCoordinator {
    fun track(
        context: Context,
        downloadId: Long,
        invocation: AgentNativeToolInvocation,
        displayName: String,
        relativePath: String
    ) {
        val app = context.applicationContext
        AgentAndroidDownloadStore(app).write(AgentAndroidDownloadRecord(
            downloadId = downloadId,
            conversationId = invocation.context.conversationId,
            turnId = invocation.context.turnId,
            displayName = displayName,
            relativePath = relativePath,
            languageTag = LanguagePolicySettings.resolvedResponseLanguage(app)
        ))
        thread(name = "galaxyssi-download-race-$downloadId", isDaemon = true) {
            Thread.sleep(750L)
            handleCompletion(app, downloadId)
        }
    }

    @Synchronized
    fun handleCompletion(context: Context, downloadId: Long): Boolean {
        val app = context.applicationContext
        val store = AgentAndroidDownloadStore(app)
        val record = store.read(downloadId) ?: return false
        val manager = app.getSystemService(DownloadManager::class.java)
        val snapshot = manager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
            if (!cursor.moveToFirst()) null else DownloadSnapshot(
                status = cursor.longColumn(DownloadManager.COLUMN_STATUS).toInt(),
                reason = cursor.longColumn(DownloadManager.COLUMN_REASON),
                title = cursor.stringColumn(DownloadManager.COLUMN_TITLE),
                localUri = cursor.stringColumn(DownloadManager.COLUMN_LOCAL_URI),
                mimeType = cursor.stringColumn(DownloadManager.COLUMN_MEDIA_TYPE),
                sizeBytes = cursor.longColumn(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            )
        } ?: return false
        if (snapshot.status !in TERMINAL_STATUSES) return false

        val chinese = record.languageTag.startsWith("zh", ignoreCase = true)
        val transcript = AgentTranscriptStore(app)
        val conversationId = record.conversationId
            .takeIf { it.isNotBlank() && transcript.conversation(it) != null }
            ?: transcript.activeConversation().id
        if (snapshot.status == DownloadManager.STATUS_SUCCESSFUL) {
            val uri = manager.getUriForDownloadedFile(downloadId)
                ?: snapshot.localUri.takeIf(String::isNotBlank)?.let(Uri::parse)
            if (uri == null) {
                appendFailure(transcript, record, conversationId, chinese)
            } else {
                val metadata = queryMetadata(app, uri)
                val displayName = metadata.displayName.ifBlank { snapshot.title.ifBlank { record.displayName } }
                val mimeType = manager.getMimeTypeForDownloadedFile(downloadId)
                    .orEmpty().ifBlank { snapshot.mimeType }.ifBlank { "application/octet-stream" }
                val sizeBytes = metadata.sizeBytes.takeIf { it >= 0L } ?: snapshot.sizeBytes
                val richOutput = AgentRichContentCodec.encode(listOf(AgentRichBlock(
                    id = "android-download:$downloadId",
                    type = AgentRichBlockType.FILE,
                    title = displayName,
                    text = record.relativePath,
                    uri = uri.toString(),
                    mimeType = mimeType,
                    fallbackText = displayName,
                    metadata = buildMap {
                        put("saved_to_downloads", "true")
                        put("local_download", "true")
                        put("relative_path", record.relativePath)
                        if (sizeBytes >= 0L) {
                            put("size_bytes", sizeBytes.toString())
                            put("size", humanReadableSize(sizeBytes))
                        }
                    }
                )))
                transcript.append(
                    role = AgentTranscriptRole.ASSISTANT,
                    text = AgentAndroidDownloadPolicy.completedMessage(chinese, displayName),
                    dedupeKey = "android-download-complete:$downloadId",
                    conversationId = conversationId,
                    turnId = record.turnId,
                    taskId = record.turnId,
                    richOutputJson = richOutput
                )
            }
        } else {
            appendFailure(transcript, record, conversationId, chinese, snapshot.reason)
        }
        store.remove(downloadId)
        return true
    }

    private fun appendFailure(
        transcript: AgentTranscriptStore,
        record: AgentAndroidDownloadRecord,
        conversationId: String,
        chinese: Boolean,
        reason: Long = 0L
    ) {
        transcript.append(
            role = AgentTranscriptRole.ASSISTANT,
            text = AgentAndroidDownloadPolicy.failedMessage(chinese, record.displayName),
            dedupeKey = "android-download-failed:${record.downloadId}:$reason",
            conversationId = conversationId,
            turnId = record.turnId,
            taskId = record.turnId
        )
    }

    private fun queryMetadata(context: Context, uri: Uri): DownloadMetadata = runCatching {
        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            DownloadMetadata(
                displayName = nameIndex.takeIf { it >= 0 && !cursor.isNull(it) }?.let(cursor::getString).orEmpty(),
                sizeBytes = sizeIndex.takeIf { it >= 0 && !cursor.isNull(it) }?.let(cursor::getLong) ?: -1L
            )
        }
    }.getOrNull() ?: DownloadMetadata()

    private fun humanReadableSize(bytes: Long): String = when {
        bytes < 1_024L -> "$bytes B"
        bytes < 1_048_576L -> String.format(Locale.US, "%.1f KB", bytes / 1_024.0)
        else -> String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)
    }

    private fun android.database.Cursor.stringColumn(name: String): String {
        val index = getColumnIndex(name)
        return index.takeIf { it >= 0 && !isNull(it) }?.let(::getString).orEmpty()
    }

    private fun android.database.Cursor.longColumn(name: String): Long {
        val index = getColumnIndex(name)
        return index.takeIf { it >= 0 && !isNull(it) }?.let(::getLong) ?: 0L
    }

    private data class DownloadSnapshot(
        val status: Int,
        val reason: Long,
        val title: String,
        val localUri: String,
        val mimeType: String,
        val sizeBytes: Long
    )

    private data class DownloadMetadata(
        val displayName: String = "",
        val sizeBytes: Long = -1L
    )

    private val TERMINAL_STATUSES = setOf(
        DownloadManager.STATUS_SUCCESSFUL,
        DownloadManager.STATUS_FAILED
    )
}

class AgentAndroidDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (downloadId < 0L) return
        val pending = goAsync()
        thread(name = "galaxyssi-download-complete-$downloadId", isDaemon = true) {
            try {
                AgentAndroidDownloadCoordinator.handleCompletion(context, downloadId)
            } finally {
                pending.finish()
            }
        }
    }
}
