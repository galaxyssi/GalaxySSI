package com.galaxyssi.chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.Job
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.coroutineContext

class LocalModelDownloadService : Service() {
    private enum class StopRequest { NONE, PAUSE, CANCEL }

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "GalaxySSI-LocalModelDownload").apply { isDaemon = true }
    }
    private val queue = ConcurrentLinkedQueue<String>()
    private val stopRequest = AtomicReference(StopRequest.NONE)
    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()
    @Volatile private var activeProfileId = ""
    @Volatile private var activeCall: Call? = null
    @Volatile private var activeQairtJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val profileId = intent?.getStringExtra(EXTRA_PROFILE_ID).orEmpty()
        when (intent?.action) {
            ACTION_START -> enqueue(profileId)
            ACTION_PAUSE -> requestStop(profileId, StopRequest.PAUSE)
            ACTION_CANCEL -> requestStop(profileId, StopRequest.CANCEL)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        activeCall?.cancel()
        activeQairtJob?.cancel()
        executor.shutdownNow()
        activeIds.clear()
        super.onDestroy()
    }

    private fun enqueue(profileId: String) {
        if (profileId.isBlank() || profileId == activeProfileId || profileId in queue) return
        queue += profileId
        activeIds += profileId
        if (activeProfileId.isBlank()) runNext()
    }

    private fun runNext() {
        val next = queue.poll()
        if (next == null) {
            activeProfileId = ""
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        activeProfileId = next
        stopRequest.set(StopRequest.NONE)
        val profile = LocalModelManager.profile(this, next)
        startForeground(NOTIFICATION_ID, notification(profile, LocalModelManager.state(this, profile)))
        executor.execute {
            try {
                download(profile)
            } finally {
                activeCall = null
                activeQairtJob = null
                activeIds -= profile.id
                activeProfileId = ""
                runNext()
            }
        }
    }

    private fun requestStop(profileId: String, request: StopRequest) {
        if (profileId.isBlank()) return
        if (profileId == activeProfileId) {
            stopRequest.set(request)
            activeCall?.cancel()
            activeQairtJob?.cancel()
        } else {
            queue.remove(profileId)
            activeIds -= profileId
            val profile = LocalModelManager.profile(this, profileId)
            if (request == StopRequest.CANCEL) {
                if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
                    Lfm25QnnDeploymentStore(this).deletePartialDownload()
                } else {
                    LocalModelManager.storage(this).partialFile(profile).delete()
                }
                LocalModelManager.clearState(this, profile)
            } else {
                val current = LocalModelManager.state(this, profile)
                LocalModelManager.record(this, profile, current.copy(state = LocalModelInstallState.PAUSED))
            }
        }
    }

    private fun download(profile: LocalModelRuntimeProfile) {
        if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            downloadSignedLfmQnn(profile)
            return
        }
        if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            downloadQairt(profile)
            return
        }
        val storage = LocalModelManager.storage(this)
        val urls = profile.sourceUrls(LocalModelManager.preferChinaMirror(this))
        var sourceIndex = LocalModelManager.state(this, profile).sourceIndex.coerceIn(0, urls.lastIndex)
        var lastFailure: Throwable? = null
        while (sourceIndex < urls.size) {
            val sourceUrl = urls[sourceIndex]
            try {
                downloadFrom(profile, sourceUrl, sourceIndex)
                checkStop(profile)
                LocalModelManager.record(
                    this,
                    profile,
                    LocalModelDownloadState(
                        LocalModelInstallState.VERIFYING,
                        profile.expectedModelFileBytes,
                        profile.expectedModelFileBytes,
                        sourceIndex
                    )
                )
                updateNotification(profile)
                if (!storage.verifyPartial(profile)) {
                    storage.partialFile(profile).delete()
                    throw IOException("Downloaded model failed SHA-256 verification")
                }
                checkStop(profile)
                LocalModelManager.record(
                    this,
                    profile,
                    LocalModelDownloadState(
                        LocalModelInstallState.INSTALLING,
                        profile.expectedModelFileBytes,
                        profile.expectedModelFileBytes,
                        sourceIndex
                    )
                )
                updateNotification(profile)
                storage.commitVerifiedPartial(profile, sourceUrl)
                LocalModelRuntimeSettings.registerInstalledProfile(this, profile)
                LocalModelManager.record(
                    this,
                    profile,
                    LocalModelDownloadState(
                        LocalModelInstallState.READY,
                        profile.expectedModelFileBytes,
                        profile.expectedModelFileBytes,
                        sourceIndex
                    )
                )
                updateNotification(profile)
                return
            } catch (error: Throwable) {
                lastFailure = error
                when (stopRequest.get()) {
                    StopRequest.PAUSE -> {
                        val bytes = storage.partialFile(profile).length()
                        LocalModelManager.record(
                            this,
                            profile,
                            LocalModelDownloadState(
                                LocalModelInstallState.PAUSED,
                                bytes,
                                profile.expectedModelFileBytes,
                                sourceIndex
                            )
                        )
                        return
                    }
                    StopRequest.CANCEL -> {
                        storage.partialFile(profile).delete()
                        LocalModelManager.clearState(this, profile)
                        return
                    }
                    StopRequest.NONE -> {
                        sourceIndex += 1
                        if (sourceIndex < urls.size) {
                            LocalModelManager.record(
                                this,
                                profile,
                                LocalModelDownloadState(
                                    LocalModelInstallState.QUEUED,
                                    storage.partialFile(profile).length(),
                                    profile.expectedModelFileBytes,
                                    sourceIndex,
                                    "Retrying another verified source"
                                )
                            )
                        }
                    }
                }
            }
        }
        LocalModelManager.record(
            this,
            profile,
            LocalModelDownloadState(
                LocalModelInstallState.FAILED,
                storage.partialFile(profile).length(),
                profile.expectedModelFileBytes,
                sourceIndex.coerceAtLeast(0),
                lastFailure?.message.orEmpty().ifBlank { "Model download failed" }
            )
        )
        updateNotification(profile)
    }

    private fun downloadSignedLfmQnn(profile: LocalModelRuntimeProfile) {
        val store = Lfm25QnnDeploymentStore(this)
        val urls = Lfm25QnnDownloadCatalog.sourceUrls(LocalModelManager.preferChinaMirror(this))
        var sourceIndex = LocalModelManager.state(this, profile).sourceIndex.coerceIn(0, urls.lastIndex)
        var lastFailure: Throwable? = null
        while (sourceIndex < urls.size) {
            var downloadComplete = false
            try {
                val downloadedBytes = downloadLfmPackageFrom(profile, urls[sourceIndex], sourceIndex)
                downloadComplete = true
                checkStop(profile)
                LocalModelManager.record(
                    this,
                    profile,
                    LocalModelDownloadState(
                        LocalModelInstallState.VERIFYING,
                        downloadedBytes,
                        downloadedBytes,
                        sourceIndex
                    )
                )
                updateNotification(profile)
                LocalModelManager.record(
                    this,
                    profile,
                    LocalModelDownloadState(
                        LocalModelInstallState.INSTALLING,
                        downloadedBytes,
                        downloadedBytes,
                        sourceIndex
                    )
                )
                updateNotification(profile)
                val installed = FileInputStream(store.partialDownloadFile()).use { input ->
                    LocalModelManager.importSignedQnnDeployment(this, input)
                }
                store.deletePartialDownload()
                LocalModelManager.record(
                    this,
                    installed,
                    LocalModelDownloadState(
                        LocalModelInstallState.READY,
                        installed.expectedModelFileBytes,
                        installed.expectedModelFileBytes,
                        sourceIndex
                    )
                )
                updateNotification(installed)
                return
            } catch (error: Throwable) {
                lastFailure = error
                when (stopRequest.get()) {
                    StopRequest.PAUSE -> {
                        val bytes = store.partialDownloadBytes()
                        LocalModelManager.record(
                            this,
                            profile,
                            LocalModelDownloadState(
                                LocalModelInstallState.PAUSED,
                                bytes,
                                LocalModelManager.state(this, profile).totalBytes,
                                sourceIndex
                            )
                        )
                        return
                    }
                    StopRequest.CANCEL -> {
                        store.deletePartialDownload()
                        LocalModelManager.clearState(this, profile)
                        return
                    }
                    StopRequest.NONE -> {
                        if (downloadComplete) store.deletePartialDownload()
                        sourceIndex += 1
                        if (sourceIndex < urls.size) {
                            LocalModelManager.record(
                                this,
                                profile,
                                LocalModelDownloadState(
                                    LocalModelInstallState.QUEUED,
                                    store.partialDownloadBytes(),
                                    profile.expectedModelFileBytes,
                                    sourceIndex,
                                    "Retrying another signed QNN source"
                                )
                            )
                        }
                    }
                }
            }
        }
        LocalModelManager.record(
            this,
            profile,
            LocalModelDownloadState(
                LocalModelInstallState.FAILED,
                store.partialDownloadBytes(),
                profile.expectedModelFileBytes,
                sourceIndex.coerceAtLeast(0),
                lastFailure?.message.orEmpty().ifBlank { "Signed QNN model download failed" }
            )
        )
        updateNotification(profile)
    }

    private fun downloadLfmPackageFrom(
        profile: LocalModelRuntimeProfile,
        sourceUrl: String,
        sourceIndex: Int
    ): Long {
        val store = Lfm25QnnDeploymentStore(this)
        val partial = store.partialDownloadFile()
        var offset = partial.length().takeIf { it in 0..Lfm25QnnDownloadCatalog.MAX_ARCHIVE_BYTES } ?: 0L
        if (partial.length() != offset) {
            store.deletePartialDownload()
            offset = 0L
        }
        val request = Request.Builder()
            .url(sourceUrl)
            .header("Accept", "application/zip, application/octet-stream")
            .header("Accept-Encoding", "identity")
            .header("User-Agent", "GalaxySSI-Android")
            .apply { if (offset > 0L) header("Range", "bytes=$offset-") }
            .build()
        val call = client.newCall(request)
        activeCall = call
        call.execute().use { response ->
            checkStop(profile)
            if (response.code == 416 && offset > 0L) return partial.length()
            if (!response.isSuccessful) throw IOException("QNN model source returned HTTP ${response.code}")
            val append = LocalModelDownloadProtocol.shouldAppend(
                requestedOffset = offset,
                responseCode = response.code,
                contentRange = response.header("Content-Range")
            )
            if (!append) {
                store.deletePartialDownload()
                offset = 0L
            }
            val body = response.body ?: throw IOException("QNN model source returned no data")
            val total = Lfm25QnnDownloadCatalog.responseTotalBytes(
                requestedOffset = offset,
                responseContentLength = body.contentLength(),
                contentRange = response.header("Content-Range"),
                fallbackBytes = profile.expectedModelFileBytes
            )
            val requiredBytes = store.requiredDownloadBytes(total)
            val availableBytes = store.availableBytes()
            if (availableBytes in 0 until requiredBytes) {
                throw LocalModelInsufficientStorage(requiredBytes, availableBytes)
            }
            val exactTotal = response.header("Content-Range")?.substringAfterLast('/')?.toLongOrNull() != null ||
                body.contentLength() >= 0L
            LocalModelManager.record(
                this,
                profile,
                LocalModelDownloadState(
                    LocalModelInstallState.DOWNLOADING,
                    offset,
                    total,
                    sourceIndex
                )
            )
            updateNotification(profile)
            FileOutputStream(partial, append).use { output ->
                body.byteStream().use { input ->
                    val buffer = ByteArray(1024 * 1024)
                    var downloaded = offset
                    var lastPersistedAt = 0L
                    while (true) {
                        checkStop(profile)
                        val read = input.read(buffer)
                        if (read < 0) break
                        if (read == 0) continue
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (downloaded > Lfm25QnnDownloadCatalog.MAX_ARCHIVE_BYTES) {
                            throw IOException("QNN model package exceeded its size limit")
                        }
                        val now = System.currentTimeMillis()
                        if (now - lastPersistedAt >= 750L) {
                            LocalModelManager.record(
                                this,
                                profile,
                                LocalModelDownloadState(
                                    LocalModelInstallState.DOWNLOADING,
                                    downloaded,
                                    maxOf(total, downloaded),
                                    sourceIndex
                                )
                            )
                            updateNotification(profile)
                            lastPersistedAt = now
                        }
                    }
                }
                output.fd.sync()
            }
            if (exactTotal && partial.length() != total) {
                throw IOException("Downloaded ${partial.length()} of $total QNN package bytes")
            }
        }
        return partial.length()
    }

    private fun downloadQairt(profile: LocalModelRuntimeProfile) = runBlocking {
        activeQairtJob = coroutineContext.job
        try {
            LocalModelManager.record(
                this@LocalModelDownloadService,
                profile,
                LocalModelDownloadState(
                    LocalModelInstallState.DOWNLOADING,
                    LocalModelManager.state(this@LocalModelDownloadService, profile).bytesDownloaded,
                    profile.expectedModelFileBytes
                )
            )
            GenieXQairtModelManager.pull(this@LocalModelDownloadService, profile) { progress ->
                val total = progress.totalBytes.takeIf { it > 0L } ?: profile.expectedModelFileBytes
                LocalModelManager.record(
                    this@LocalModelDownloadService,
                    profile,
                    LocalModelDownloadState(
                        LocalModelInstallState.DOWNLOADING,
                        progress.downloadedBytes.coerceAtMost(total),
                        total
                    )
                )
                updateNotification(profile)
            }
            checkStop(profile)
            LocalModelManager.record(
                this@LocalModelDownloadService,
                profile,
                LocalModelDownloadState(
                    LocalModelInstallState.INSTALLING,
                    profile.expectedModelFileBytes,
                    profile.expectedModelFileBytes
                )
            )
            updateNotification(profile)
            LocalModelRuntimeSettings.registerInstalledProfile(this@LocalModelDownloadService, profile)
            LocalModelManager.record(
                this@LocalModelDownloadService,
                profile,
                LocalModelDownloadState(
                    LocalModelInstallState.READY,
                    profile.expectedModelFileBytes,
                    profile.expectedModelFileBytes
                )
            )
            updateNotification(profile)
        } catch (error: Throwable) {
            val current = LocalModelManager.state(this@LocalModelDownloadService, profile)
            when (stopRequest.get()) {
                StopRequest.PAUSE -> LocalModelManager.record(
                    this@LocalModelDownloadService,
                    profile,
                    current.copy(state = LocalModelInstallState.PAUSED)
                )
                StopRequest.CANCEL -> {
                    runCatching {
                        GenieXQairtModelManager.remove(this@LocalModelDownloadService, profile)
                    }
                    LocalModelManager.clearState(this@LocalModelDownloadService, profile)
                }
                StopRequest.NONE -> {
                    LocalModelManager.record(
                        this@LocalModelDownloadService,
                        profile,
                        current.copy(
                            state = LocalModelInstallState.FAILED,
                            detail = error.message.orEmpty().ifBlank { "Qualcomm model download failed" }
                        )
                    )
                    updateNotification(profile)
                }
            }
        } finally {
            activeQairtJob = null
        }
    }

    private fun downloadFrom(profile: LocalModelRuntimeProfile, sourceUrl: String, sourceIndex: Int) {
        val storage = LocalModelManager.storage(this)
        val partial = storage.partialFile(profile)
        partial.parentFile?.mkdirs()
        var offset = LocalModelDownloadProtocol.resumeOffset(
            partialLength = partial.length(),
            expectedLength = profile.expectedModelFileBytes
        )
        if (partial.length() != offset) {
            partial.delete()
            offset = 0L
        }
        val request = Request.Builder()
            .url(sourceUrl)
            .header("Accept", "application/octet-stream")
            .header("User-Agent", "GalaxySSI-Android")
            .apply { if (offset > 0L) header("Range", "bytes=$offset-") }
            .build()
        val call = client.newCall(request)
        activeCall = call
        call.execute().use { response ->
            checkStop(profile)
            if (response.code == 416 && offset == profile.expectedModelFileBytes) return
            if (!response.isSuccessful) throw IOException("Model source returned HTTP ${response.code}")
            val append = LocalModelDownloadProtocol.shouldAppend(
                requestedOffset = offset,
                responseCode = response.code,
                contentRange = response.header("Content-Range")
            )
            if (!append) {
                partial.delete()
                offset = 0L
            }
            val body = response.body ?: throw IOException("Model source returned no data")
            FileOutputStream(partial, append).use { output ->
                body.byteStream().use { input ->
                    val buffer = ByteArray(1024 * 1024)
                    var downloaded = offset
                    var lastPersistedAt = 0L
                    while (true) {
                        checkStop(profile)
                        val read = input.read(buffer)
                        if (read < 0) break
                        if (read == 0) continue
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (downloaded > profile.expectedModelFileBytes) {
                            throw IOException("Model source exceeded the pinned file size")
                        }
                        val now = System.currentTimeMillis()
                        if (now - lastPersistedAt >= 750L) {
                            LocalModelManager.record(
                                this,
                                profile,
                                LocalModelDownloadState(
                                    LocalModelInstallState.DOWNLOADING,
                                    downloaded,
                                    profile.expectedModelFileBytes,
                                    sourceIndex
                                )
                            )
                            updateNotification(profile)
                            lastPersistedAt = now
                        }
                    }
                }
                output.fd.sync()
            }
        }
        if (partial.length() != profile.expectedModelFileBytes) {
            throw IOException("Downloaded ${partial.length()} of ${profile.expectedModelFileBytes} bytes")
        }
    }

    private fun checkStop(profile: LocalModelRuntimeProfile) {
        if (stopRequest.get() != StopRequest.NONE) throw IOException("Download interrupted for ${profile.id}")
    }

    private fun updateNotification(profile: LocalModelRuntimeProfile) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification(profile, LocalModelManager.state(this, profile)))
    }

    private fun notification(profile: LocalModelRuntimeProfile, state: LocalModelDownloadState) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(getString(R.string.local_model_download_notification_title, profile.displayName))
            .setContentText(localModelStateLabel(state))
            .setOnlyAlertOnce(true)
            .setOngoing(state.state in setOf(
                LocalModelInstallState.QUEUED,
                LocalModelInstallState.DOWNLOADING,
                LocalModelInstallState.VERIFYING,
                LocalModelInstallState.INSTALLING
            ))
            .setProgress(100, state.progressPercent, state.totalBytes <= 0L)
            .setContentIntent(PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java).putExtra("galaxyssi_debug_open_local_model", true),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))
            .build()

    private fun localModelStateLabel(state: LocalModelDownloadState): String = when (state.state) {
        LocalModelInstallState.QUEUED -> getString(R.string.local_model_download_queued)
        LocalModelInstallState.DOWNLOADING -> getString(R.string.local_model_download_progress, state.progressPercent)
        LocalModelInstallState.PAUSED -> getString(R.string.local_model_download_paused)
        LocalModelInstallState.VERIFYING -> getString(R.string.local_model_download_verifying)
        LocalModelInstallState.INSTALLING -> getString(R.string.local_model_download_installing)
        LocalModelInstallState.READY -> getString(R.string.local_model_download_ready)
        LocalModelInstallState.FAILED -> state.detail.ifBlank { getString(R.string.local_model_download_failed) }
        LocalModelInstallState.NOT_INSTALLED -> getString(R.string.local_model_download_action)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.local_model_download_channel),
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    companion object {
        private const val ACTION_START = "com.galaxyssi.chat.localmodel.START"
        private const val ACTION_PAUSE = "com.galaxyssi.chat.localmodel.PAUSE"
        private const val ACTION_CANCEL = "com.galaxyssi.chat.localmodel.CANCEL"
        private const val EXTRA_PROFILE_ID = "profile_id"
        private const val CHANNEL_ID = "galaxyssi_local_models"
        private const val NOTIFICATION_ID = 9018
        private val activeIds = ConcurrentHashMap.newKeySet<String>()

        fun isActive(profileId: String): Boolean = profileId in activeIds

        fun start(context: Context, profileId: String) = send(context, ACTION_START, profileId, foreground = true)

        fun pause(context: Context, profileId: String) = send(context, ACTION_PAUSE, profileId)

        fun cancel(context: Context, profileId: String) = send(context, ACTION_CANCEL, profileId)

        private fun send(context: Context, action: String, profileId: String, foreground: Boolean = false) {
            val intent = Intent(context, LocalModelDownloadService::class.java)
                .setAction(action)
                .putExtra(EXTRA_PROFILE_ID, profileId)
            if (foreground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
