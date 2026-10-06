package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID

internal object AgentWebOriginalArchive {
    @Synchronized
    fun enqueue(context: Context, prepared: AgentPhonePublicHtmlPreparation, source: AgentWebIntelligenceFetched) {
        if (!source.contentType.contains("html", true)) return
        val hash = MessageDigest.getInstance("SHA-256").apply {
            update(source.url.toByteArray(Charsets.UTF_8)); update(source.body)
        }.digest()
        val id = UUID.nameUUIDFromBytes(hash).toString()
        val directory = directory(context, id).apply { check(mkdirs() || isDirectory) }
        if (!File(directory, "source.html").isFile && !File(directory, "$id-original.html").isFile) {
            val temp = File(directory, "source.tmp")
            temp.outputStream().use { it.write(source.body) }
            check(temp.renameTo(File(directory, "source.html")))
        }
        if (!File(directory, "metadata.json").isFile) {
            val metadata = JSONObject().put("url", source.url).put("name",
                context.getString(R.string.agent_web_original_archive_filename,
                    prepared.attachment.displayName.removeSuffix(".html")))
            AgentPhonePublicHtmlAttachment.writePlaintextHtml(File(directory, "metadata.json"), metadata.toString())
        }
        WorkManager.getInstance(context).enqueueUniqueWork("original-page-$id", ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<AgentWebOriginalArchiveWorker>().setInputData(workDataOf("id" to id)).build())
    }

    fun directory(context: Context, id: String): File {
        require(id.matches(Regex("[a-f0-9-]{36}")))
        return File(context.filesDir, "agent-public-html-original/$id")
    }
}

class AgentWebOriginalArchiveWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        val id = inputData.getString("id").orEmpty()
        val directory = AgentWebOriginalArchive.directory(applicationContext, id)
        val meta = JSONObject(File(directory, "metadata.json").readText())
        val archive = File(directory, "$id-original.html")
        if (!archive.isFile) {
            val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
                policy = AgentWebPolicy(maxDownloadBytes = 8L * 1024 * 1024, maxTimeoutMillis = 15_000))
            val deadline = android.os.SystemClock.elapsedRealtime() + 120_000
            var remaining = 24L * 1024 * 1024
            val built = AgentWebOriginalDocument.build(meta.getString("url"), File(directory, "source.html").readBytes(),
                notice = { missing, address -> applicationContext.getString(R.string.agent_web_original_archive_notice, missing, address) }) { url ->
                check(!isStopped)
                val time = deadline - android.os.SystemClock.elapsedRealtime()
                if (time <= 0 || remaining <= 0) null else {
                    val item = web.download(url, maxBytes = minOf(8L * 1024 * 1024, remaining),
                        timeoutMillis = minOf(15_000, time), checkpoint = { check(!isStopped) })
                    remaining -= item.body.size
                    OriginalPageAsset(item.contentType, item.body)
                }
            }
            check(!isStopped)
            AgentPhonePublicHtmlAttachment.writePlaintextHtml(archive, built.html)
        }
        check(!isStopped)
        if (AgentPhonePublicHtmlAttachment.saveToDownloads(applicationContext, archive, meta.getString("name"))) {
            File(directory, "source.html").delete()
            archive.delete()
            Log.i("GalaxySSIPhoneWeb", "Original page archive saved to Download/GalaxySSI")
            Result.success()
        } else if (runAttemptCount < 2) Result.retry() else Result.failure()
    } catch (error: Exception) {
        Log.w("GalaxySSIPhoneWeb", "Original page archive did not finish", error)
        if (runAttemptCount < 2) Result.retry() else Result.failure()
    }
}
