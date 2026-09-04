package com.galaxyssi.chat

import android.app.DownloadManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Environment
import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperDownloadDecision
import com.galaxyssi.chat.voice.model.WhisperLegacyMigration
import com.galaxyssi.chat.voice.model.WhisperLegacyMigrationState
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import com.galaxyssi.chat.voice.model.WhisperModelDownloadPolicy
import com.galaxyssi.chat.voice.model.WhisperModelInstallException
import com.galaxyssi.chat.voice.model.WhisperModelInstallFailure
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import com.galaxyssi.chat.voice.model.WhisperModelStorage
import com.galaxyssi.chat.voice.model.WhisperModelStorageState
import com.galaxyssi.chat.voice.model.WhisperModelVerifier
import com.galaxyssi.chat.voice.model.WhisperNetworkClass
import com.galaxyssi.chat.voice.model.WhisperStorageCapacity
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

typealias WhisperModel = WhisperModelProfile

data class WhisperModelDownloadState(
    val status: Int,
    val progress: Int = 0,
    val storageState: WhisperModelStorageState = WhisperModelStorageState.NOT_INSTALLED,
    val bytesDownloaded: Long = 0L,
    val totalBytes: Long = 0L,
    val certification: WhisperCertificationLevel? = null,
    val failure: WhisperModelInstallFailure? = null,
    val detail: String = ""
)

class WhisperMeteredDownloadConfirmationRequired(
    val model: WhisperModelProfile
) : IllegalStateException("Metered network confirmation is required")

class WhisperDownloadUnavailableException(
    val decision: WhisperDownloadDecision,
    val requiredBytes: Long,
    val availableBytes: Long
) : IllegalStateException("Whisper model download is unavailable: $decision")

object WhisperModelManager {
    private const val PREFS = "galaxyssi_whisper_models_v2"
    private const val KEY_DOWNLOAD_PREFIX = "download_id_"
    private const val KEY_SOURCE_URL_PREFIX = "source_url_"
    private const val KEY_ATTEMPTED_SOURCES_PREFIX = "attempted_sources_"
    private const val KEY_METERED_PREFIX = "metered_confirmed_"
    private const val KEY_STATE_PREFIX = "install_state_"
    private const val KEY_ERROR_PREFIX = "install_error_"
    private const val PARTIAL_ROOT = "galaxyssi-asr-partials"
    private const val STALE_PARTIAL_AGE_MS = 24L * 60L * 60L * 1_000L

    val models: List<WhisperModelProfile> = WhisperModelCatalog.profiles

    private val initialized = AtomicBoolean(false)
    private val background = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "GalaxySSI-WhisperModels").apply { isDaemon = true }
    }
    private val inFlight = ConcurrentHashMap.newKeySet<String>()
    private val nativeVerified = ConcurrentHashMap<String, String>()
    private val loadedModels = ConcurrentHashMap.newKeySet<String>()
    private val benchmarkingModels = ConcurrentHashMap.newKeySet<String>()
    private val modelLocks = ConcurrentHashMap<String, Any>()
    private val cancelledInstalls = ConcurrentHashMap.newKeySet<String>()

    fun model(id: String): WhisperModelProfile = WhisperModelCatalog.find(id) ?: WhisperModelCatalog.require("tiny")

    fun downloadedFile(context: Context, model: WhisperModelProfile): File = storage(context).finalFile(model)

    fun isAvailable(context: Context, model: WhisperModelProfile): Boolean {
        initialize(context)
        return storage(context).inspect(model).installed
    }

    fun isLoaded(model: WhisperModelProfile): Boolean =
        loadedModels.contains(WhisperModelCatalog.canonicalId(model.id))

    fun ensureVerifiedFile(context: Context, model: WhisperModelProfile): File {
        initialize(context)
        val appContext = context.applicationContext
        var snapshot = storage(appContext).inspect(model)
        if (!snapshot.installed) {
            migrateSynchronously(appContext, model)
            snapshot = storage(appContext).inspect(model)
        }
        val file = snapshot.file ?: throw WhisperModelInstallException(
            WhisperModelInstallFailure.SOURCE_MISSING,
            "ASR model ${model.displayName} is not installed"
        )
        val fingerprint = listOf(file.canonicalPath, file.length(), file.lastModified(), model.sha256).joinToString(":")
        if (nativeVerified[model.id] != fingerprint) {
            val verification = storage(appContext).verifyForNativeLoad(model)
            if (!verification.valid) {
                nativeVerified.remove(model.id)
                storage(appContext).invalidate(model)
                throw WhisperModelInstallException(
                    when (verification.failure) {
                        com.galaxyssi.chat.voice.model.WhisperVerificationFailure.SIZE_MISMATCH ->
                            WhisperModelInstallFailure.SIZE_MISMATCH
                        com.galaxyssi.chat.voice.model.WhisperVerificationFailure.SHA256_MISMATCH ->
                            WhisperModelInstallFailure.SHA256_MISMATCH
                        else -> WhisperModelInstallFailure.SOURCE_MISSING
                    },
                    verification.detail.ifBlank { "ASR model verification failed" }
                )
            }
            nativeVerified[model.id] = fingerprint
        }
        return file
    }

    @Synchronized
    fun enqueue(context: Context, model: WhisperModelProfile, allowMetered: Boolean = false): Long {
        require(!model.bundled) { "Bundled models do not need downloading" }
        initialize(context)
        if (isAvailable(context, model)) return -1L
        if (inFlight.contains(model.id)) return downloadId(context, model)
        val current = rawDownloadState(context, model)
        if (current.status in activeDownloadStatuses) return downloadId(context, model)

        val appContext = context.applicationContext
        val policy = WhisperModelDownloadPolicy.evaluate(
            profile = model,
            network = networkClass(appContext),
            availableFreeBytes = WhisperStorageCapacity.availableBytes(
                File(appContext.filesDir, "voice/whisper")
            ),
            meteredConfirmed = true
        )
        when (policy.decision) {
            WhisperDownloadDecision.ALLOW -> Unit
            else -> throw WhisperDownloadUnavailableException(
                policy.decision,
                policy.requiredFreeBytes,
                policy.availableFreeBytes
            )
        }
        val partialRoot = downloadPartialFile(appContext, model).parentFile
        val partialFree = partialRoot?.let(WhisperStorageCapacity::availableBytes) ?: -1L
        if (partialFree in 0 until model.expectedSizeBytes) {
            throw WhisperDownloadUnavailableException(
                WhisperDownloadDecision.INSUFFICIENT_SPACE,
                model.expectedSizeBytes,
                partialFree
            )
        }
        cancel(appContext, model, deleteInstalled = false)
        cancelledInstalls.remove(model.id)
        preferences(appContext).edit()
            .putBoolean(KEY_METERED_PREFIX + model.id, true)
            .remove(KEY_ATTEMPTED_SOURCES_PREFIX + model.id)
            .apply()
        return startDownload(appContext, model, sourceIndex = 0, allowMetered = true)
    }

    fun downloadState(context: Context, model: WhisperModelProfile): WhisperModelDownloadState {
        initialize(context)
        val appContext = context.applicationContext
        val installed = storage(appContext).inspect(model)
        if (installed.installed) {
            cleanupCompletedDownload(appContext, model)
            return WhisperModelDownloadState(
                status = DownloadManager.STATUS_SUCCESSFUL,
                progress = 100,
                storageState = if (benchmarkingModels.contains(model.id)) {
                    WhisperModelStorageState.BENCHMARKING
                } else installed.state,
                bytesDownloaded = model.expectedSizeBytes,
                totalBytes = model.expectedSizeBytes,
                certification = installed.metadata?.certification
            )
        }
        if (inFlight.contains(model.id)) {
            return WhisperModelDownloadState(
                status = DownloadManager.STATUS_RUNNING,
                progress = 100,
                storageState = storedState(appContext, model),
                totalBytes = model.expectedSizeBytes
            )
        }
        if (model.bundled) {
            scheduleMigration(appContext, model)
            return WhisperModelDownloadState(
                status = DownloadManager.STATUS_RUNNING,
                storageState = storedState(appContext, model),
                totalBytes = model.expectedSizeBytes
            )
        }
        val raw = rawDownloadState(appContext, model)
        if (raw.status == DownloadManager.STATUS_SUCCESSFUL) {
            scheduleDownloadedInstall(appContext, model)
            return raw.copy(
                status = DownloadManager.STATUS_RUNNING,
                progress = 100,
                storageState = storedState(appContext, model)
                    .takeUnless { it == WhisperModelStorageState.NOT_INSTALLED }
                    ?: WhisperModelStorageState.VERIFYING_SIZE
            )
        }
        if (raw.status == DownloadManager.STATUS_FAILED) {
            if (retryNextSource(appContext, model)) {
                return rawDownloadState(appContext, model)
            }
            setState(appContext, model, WhisperModelStorageState.FAILED, raw.detail)
            return raw.copy(
                storageState = WhisperModelStorageState.FAILED,
                failure = storedFailure(appContext, model)
            )
        }
        return raw.copy(
            storageState = when (raw.status) {
                DownloadManager.STATUS_PENDING, DownloadManager.STATUS_RUNNING ->
                    WhisperModelStorageState.DOWNLOADING_PARTIAL
                DownloadManager.STATUS_PAUSED -> WhisperModelStorageState.PAUSED
                else -> storedState(appContext, model)
            },
            failure = storedFailure(appContext, model)
        )
    }

    @Synchronized
    fun cancel(context: Context, model: WhisperModelProfile, deleteInstalled: Boolean = false) {
        val appContext = context.applicationContext
        cancelledInstalls += model.id
        val id = downloadId(appContext, model)
        if (id > 0L) downloadManager(appContext).remove(id)
        downloadPartialFile(appContext, model).delete()
        preferences(appContext).edit()
            .remove(KEY_DOWNLOAD_PREFIX + model.id)
            .remove(KEY_SOURCE_URL_PREFIX + model.id)
            .remove(KEY_ATTEMPTED_SOURCES_PREFIX + model.id)
            .remove(KEY_METERED_PREFIX + model.id)
            .remove(KEY_STATE_PREFIX + model.id)
            .remove(KEY_ERROR_PREFIX + model.id)
            .apply()
        if (deleteInstalled) {
            storage(appContext).delete(model, loadedModels.contains(model.id))
            legacyCandidates(appContext, model).forEach(File::delete)
            nativeVerified.remove(model.id)
        }
    }

    fun delete(context: Context, model: WhisperModelProfile) {
        require(!model.bundled) { "The bundled model cannot be deleted" }
        cancel(context, model, deleteInstalled = true)
    }

    fun markLoaded(modelId: String) {
        loadedModels += WhisperModelCatalog.canonicalId(modelId)
    }

    fun markUnloaded(modelId: String?) {
        modelId?.let { loadedModels -= WhisperModelCatalog.canonicalId(it) }
    }

    fun markBenchmarking(modelId: String, running: Boolean) {
        val canonical = WhisperModelCatalog.canonicalId(modelId)
        if (running) benchmarkingModels += canonical else benchmarkingModels -= canonical
    }

    fun updateCertification(
        context: Context,
        model: WhisperModelProfile,
        certification: WhisperCertificationLevel
    ) {
        storage(context.applicationContext).updateCertification(model, certification)
    }

    fun resetCertification(context: Context, model: WhisperModelProfile) {
        val snapshot = storage(context.applicationContext).inspect(model)
        if (snapshot.installed && snapshot.metadata?.certification != WhisperCertificationLevel.UNTESTED) {
            storage(context.applicationContext).updateCertification(model, WhisperCertificationLevel.UNTESTED)
        }
    }

    private fun initialize(context: Context) {
        if (!initialized.compareAndSet(false, true)) return
        val appContext = context.applicationContext
        storage(appContext).cleanupStalePartials(STALE_PARTIAL_AGE_MS)
        cleanupOrphanedDownloadPartials(appContext)
        models.forEach { profile ->
            if (storage(appContext).inspect(profile).installed) {
                cleanupCompletedDownload(appContext, profile)
            } else if (profile.bundled || legacyCandidates(appContext, profile).any(File::isFile)) {
                scheduleMigration(appContext, profile)
            }
        }
    }

    private fun scheduleMigration(context: Context, model: WhisperModelProfile) {
        if (!inFlight.add(model.id)) return
        setState(context, model, WhisperModelStorageState.VERIFYING_SIZE)
        background.execute {
            try {
                migrateSynchronously(context, model)
            } catch (error: Throwable) {
                setFailure(context, model, error)
            } finally {
                inFlight.remove(model.id)
            }
        }
    }

    private fun migrateSynchronously(context: Context, model: WhisperModelProfile) =
        synchronized(modelLocks.getOrPut(model.id) { Any() }) {
            migrateSynchronouslyLocked(context, model)
        }

    private fun migrateSynchronouslyLocked(context: Context, model: WhisperModelProfile) {
        val modelStorage = storage(context)
        if (modelStorage.inspect(model).installed) return
        val migration = WhisperLegacyMigration.migrate(
            profile = model,
            candidates = legacyCandidates(context, model),
            storage = modelStorage,
            deleteMigratedSource = true
        )
        if (migration.state == WhisperLegacyMigrationState.MIGRATED ||
            migration.state == WhisperLegacyMigrationState.ALREADY_INSTALLED) {
            setState(context, model, WhisperModelStorageState.INSTALLED_UNCERTIFIED)
            return
        }
        if (!model.bundled) {
            if (migration.state == WhisperLegacyMigrationState.REJECTED) {
                throw WhisperModelInstallException(
                    migration.failure ?: WhisperModelInstallFailure.METADATA_INVALID,
                    migration.detail
                )
            }
            return
        }
        setState(context, model, WhisperModelStorageState.VERIFYING_SHA256)
        val importRoot = File(context.cacheDir, "whisper-model-import").apply { mkdirs() }
        val candidate = File(importRoot, "${model.id}-${model.fileName}.partial")
        candidate.delete()
        try {
            context.assets.open(model.fileName).use { input ->
                FileOutputStream(candidate).use { output ->
                    input.copyTo(output, 1024 * 1024)
                    output.fd.sync()
                }
            }
            setState(context, model, WhisperModelStorageState.ATOMIC_INSTALLING)
            modelStorage.install(candidate, model, "asset:${model.fileName}")
            setState(context, model, WhisperModelStorageState.INSTALLED_UNCERTIFIED)
        } finally {
            candidate.delete()
        }
    }

    private fun scheduleDownloadedInstall(context: Context, model: WhisperModelProfile) {
        if (!inFlight.add(model.id)) return
        background.execute {
            try {
                synchronized(modelLocks.getOrPut(model.id) { Any() }) {
                    val candidate = downloadPartialFile(context, model)
                    checkInstallNotCancelled(model)
                    setState(context, model, WhisperModelStorageState.VERIFYING_SIZE)
                    if (!candidate.isFile || candidate.length() != model.expectedSizeBytes) {
                        throw WhisperModelInstallException(
                            WhisperModelInstallFailure.SIZE_MISMATCH,
                            "Downloaded model size does not match the pinned profile"
                        )
                    }
                    setState(context, model, WhisperModelStorageState.VERIFYING_SHA256)
                    val verification = WhisperModelVerifier.verify(candidate, model)
                    if (!verification.valid) {
                        throw WhisperModelInstallException(
                            WhisperModelInstallFailure.SHA256_MISMATCH,
                            verification.detail.ifBlank { "Downloaded model SHA-256 does not match" }
                        )
                    }
                    checkInstallNotCancelled(model)
                    setState(context, model, WhisperModelStorageState.ATOMIC_INSTALLING)
                    storage(context).install(
                        sourceFile = candidate,
                        profile = model,
                        sourceLabel = currentSource(context, model),
                        beforeCommit = { checkInstallNotCancelled(model) }
                    )
                    checkInstallNotCancelled(model)
                    nativeVerified.remove(model.id)
                    val id = downloadId(context, model)
                    if (id > 0L) downloadManager(context).remove(id)
                    candidate.delete()
                    preferences(context).edit()
                        .remove(KEY_DOWNLOAD_PREFIX + model.id)
                        .remove(KEY_SOURCE_URL_PREFIX + model.id)
                        .remove(KEY_ATTEMPTED_SOURCES_PREFIX + model.id)
                        .remove(KEY_METERED_PREFIX + model.id)
                        .apply()
                    setState(context, model, WhisperModelStorageState.INSTALLED_UNCERTIFIED)
                }
            } catch (error: Throwable) {
                downloadPartialFile(context, model).delete()
                if (cancelledInstalls.remove(model.id)) {
                    storage(context).invalidate(model)
                    nativeVerified.remove(model.id)
                    setState(context, model, WhisperModelStorageState.NOT_INSTALLED)
                } else if (!retryNextSource(context, model)) {
                    setFailure(context, model, error)
                }
            } finally {
                inFlight.remove(model.id)
            }
        }
    }

    @Synchronized
    private fun retryNextSource(context: Context, model: WhisperModelProfile): Boolean {
        val preferences = preferences(context)
        val sources = orderedSources(context, model)
        val attempted = preferences.getStringSet(KEY_ATTEMPTED_SOURCES_PREFIX + model.id, emptySet()).orEmpty()
        val nextIndex = sources.indexOfFirst { it !in attempted }
        if (nextIndex < 0) return false
        val oldId = downloadId(context, model)
        if (oldId > 0L) downloadManager(context).remove(oldId)
        downloadPartialFile(context, model).delete()
        return runCatching {
            startDownload(
                context,
                model,
                nextIndex,
                preferences.getBoolean(KEY_METERED_PREFIX + model.id, false)
            )
            true
        }.getOrDefault(false)
    }

    @Synchronized
    private fun startDownload(
        context: Context,
        model: WhisperModelProfile,
        sourceIndex: Int,
        allowMetered: Boolean
    ): Long {
        val sources = orderedSources(context, model)
        val url = sources.getOrNull(sourceIndex) ?: error("No trusted download source remains")
        val partial = downloadPartialFile(context, model)
        partial.parentFile?.mkdirs()
        partial.delete()
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("GalaxySSI ASR - ${model.displayName}")
            .setDescription(model.fileName)
            .setAllowedOverMetered(allowMetered || !WhisperModelDownloadPolicy.requiresUnmetered(model))
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(
                context,
                Environment.DIRECTORY_DOWNLOADS,
                "$PARTIAL_ROOT/${model.id}/${model.fileName}.partial"
            )
        val id = downloadManager(context).enqueue(request)
        val attempted = preferences(context).getStringSet(KEY_ATTEMPTED_SOURCES_PREFIX + model.id, emptySet())
            .orEmpty()
            .toMutableSet()
            .apply { add(url) }
        preferences(context).edit()
            .putLong(KEY_DOWNLOAD_PREFIX + model.id, id)
            .putString(KEY_SOURCE_URL_PREFIX + model.id, url)
            .putStringSet(KEY_ATTEMPTED_SOURCES_PREFIX + model.id, attempted)
            .putBoolean(KEY_METERED_PREFIX + model.id, allowMetered)
            .putString(KEY_STATE_PREFIX + model.id, WhisperModelStorageState.DOWNLOADING_PARTIAL.name)
            .remove(KEY_ERROR_PREFIX + model.id)
            .apply()
        return id
    }

    private fun rawDownloadState(context: Context, model: WhisperModelProfile): WhisperModelDownloadState {
        val id = downloadId(context, model)
        if (id <= 0L) {
            return WhisperModelDownloadState(
                status = 0,
                storageState = storedState(context, model),
                failure = storedFailure(context, model),
                detail = storedError(context, model)
            )
        }
        return runCatching {
            downloadManager(context).query(DownloadManager.Query().setFilterById(id)).use { cursor ->
                if (!cursor.moveToFirst()) {
                    clearDownloadRegistration(context, model)
                    return@use WhisperModelDownloadState(0)
                }
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                val expectedTotal = total.takeIf { it > 0L } ?: model.expectedSizeBytes
                WhisperModelDownloadState(
                    status = status,
                    progress = if (expectedTotal > 0L) {
                        ((downloaded.coerceAtLeast(0L) * 100L) / expectedTotal).toInt().coerceIn(0, 100)
                    } else 0,
                    storageState = storedState(context, model),
                    bytesDownloaded = downloaded.coerceAtLeast(0L),
                    totalBytes = expectedTotal,
                    detail = if (status == DownloadManager.STATUS_FAILED) "DownloadManager reason $reason" else ""
                )
            }
        }.getOrElse { error ->
            WhisperModelDownloadState(
                status = 0,
                storageState = WhisperModelStorageState.FAILED,
                failure = WhisperModelInstallFailure.SOURCE_MISSING,
                detail = error.message.orEmpty()
            )
        }
    }

    private fun storage(context: Context): WhisperModelStorage = WhisperModelStorage(
        File(context.filesDir, "voice/whisper"),
        WhisperModelCatalog.CATALOG_VERSION,
        capacityProvider = WhisperStorageCapacity::availableBytes
    )

    private fun legacyCandidates(context: Context, model: WhisperModelProfile): List<File> = listOfNotNull(
        context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.let { File(it, "galaxyssi-asr/${model.fileName}") },
        File(context.filesDir, "galaxyssi-asr/${model.fileName}"),
        File(context.filesDir, model.fileName)
    )

    private fun downloadPartialFile(context: Context, model: WhisperModelProfile): File = File(
        context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir,
        "$PARTIAL_ROOT/${model.id}/${model.fileName}.partial"
    )

    private fun cleanupOrphanedDownloadPartials(context: Context) {
        val root = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir, PARTIAL_ROOT)
        root.walkTopDown().filter { it.isFile && it.name.endsWith(".partial") }.forEach { file ->
            val model = models.firstOrNull { file.parentFile?.name == it.id }
            if (model == null || downloadId(context, model) <= 0L) {
                if (System.currentTimeMillis() - file.lastModified() > STALE_PARTIAL_AGE_MS) file.delete()
            }
        }
    }

    private fun orderedSources(context: Context, model: WhisperModelProfile): List<String> =
        WhisperModelDownloadPolicy.orderedSources(model, context.resources.configuration.locales[0] ?: Locale.getDefault())

    private fun currentSource(context: Context, model: WhisperModelProfile): String {
        return preferences(context).getString(KEY_SOURCE_URL_PREFIX + model.id, "").orEmpty()
    }

    private fun networkClass(context: Context): WhisperNetworkClass {
        val manager = context.getSystemService(ConnectivityManager::class.java)
            ?: return WhisperNetworkClass.UNKNOWN
        val network = manager.activeNetwork ?: return WhisperNetworkClass.OFFLINE
        val capabilities = manager.getNetworkCapabilities(network) ?: return WhisperNetworkClass.UNKNOWN
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> WhisperNetworkClass.WIFI
            !manager.isActiveNetworkMetered -> WhisperNetworkClass.UNMETERED
            else -> WhisperNetworkClass.METERED
        }
    }

    private fun setFailure(context: Context, model: WhisperModelProfile, error: Throwable) {
        val failure = (error as? WhisperModelInstallException)?.failure ?: WhisperModelInstallFailure.COPY_FAILED
        preferences(context).edit()
            .putString(KEY_STATE_PREFIX + model.id, WhisperModelStorageState.FAILED.name)
            .putString(KEY_ERROR_PREFIX + model.id, "${failure.name}:${error.message.orEmpty().take(240)}")
            .apply()
    }

    private fun setState(
        context: Context,
        model: WhisperModelProfile,
        state: WhisperModelStorageState,
        detail: String = ""
    ) {
        preferences(context).edit()
            .putString(KEY_STATE_PREFIX + model.id, state.name)
            .apply {
                if (detail.isBlank()) remove(KEY_ERROR_PREFIX + model.id)
                else putString(KEY_ERROR_PREFIX + model.id, detail.take(240))
            }
            .apply()
    }

    private fun storedState(context: Context, model: WhisperModelProfile): WhisperModelStorageState = runCatching {
        enumValueOf<WhisperModelStorageState>(
            preferences(context).getString(KEY_STATE_PREFIX + model.id, null)
                ?: WhisperModelStorageState.NOT_INSTALLED.name
        )
    }.getOrDefault(WhisperModelStorageState.NOT_INSTALLED)

    private fun storedError(context: Context, model: WhisperModelProfile): String =
        preferences(context).getString(KEY_ERROR_PREFIX + model.id, "").orEmpty()

    private fun storedFailure(context: Context, model: WhisperModelProfile): WhisperModelInstallFailure? =
        storedError(context, model).substringBefore(':').takeIf(String::isNotBlank)?.let { name ->
            runCatching { enumValueOf<WhisperModelInstallFailure>(name) }.getOrNull()
        }

    private fun downloadId(context: Context, model: WhisperModelProfile): Long =
        preferences(context).getLong(KEY_DOWNLOAD_PREFIX + model.id, -1L)

    private fun cleanupCompletedDownload(context: Context, model: WhisperModelProfile) {
        val id = downloadId(context, model)
        if (id > 0L) downloadManager(context).remove(id)
        downloadPartialFile(context, model).delete()
        clearDownloadRegistration(context, model)
    }

    private fun clearDownloadRegistration(context: Context, model: WhisperModelProfile) {
        preferences(context).edit()
            .remove(KEY_DOWNLOAD_PREFIX + model.id)
            .remove(KEY_SOURCE_URL_PREFIX + model.id)
            .remove(KEY_ATTEMPTED_SOURCES_PREFIX + model.id)
            .remove(KEY_METERED_PREFIX + model.id)
            .apply()
    }

    private fun checkInstallNotCancelled(model: WhisperModelProfile) {
        if (cancelledInstalls.contains(model.id)) throw InterruptedException("Model installation was cancelled")
    }

    private fun preferences(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun downloadManager(context: Context): DownloadManager =
        context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private val activeDownloadStatuses = setOf(
        DownloadManager.STATUS_PENDING,
        DownloadManager.STATUS_RUNNING,
        DownloadManager.STATUS_PAUSED
    )
}
