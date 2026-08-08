package com.signalasi.chat

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.Locale

data class LocalModelDownloadState(
    val state: LocalModelInstallState,
    val bytesDownloaded: Long = 0L,
    val totalBytes: Long = 0L,
    val sourceIndex: Int = 0,
    val detail: String = ""
) {
    val progressPercent: Int
        get() = if (totalBytes <= 0L) 0 else ((bytesDownloaded * 100L) / totalBytes).toInt().coerceIn(0, 100)
}

internal object LocalModelPostInstallSelection {
    fun enabledQnnProfiles(
        currentProfileIds: Set<String>,
        installedProfileId: String
    ): Set<String> {
        require(installedProfileId.isNotBlank()) { "Installed local-model profile ID is required" }
        return currentProfileIds + installedProfileId
    }
}

class LocalModelMeteredConfirmationRequired(
    val profile: LocalModelRuntimeProfile
) : IllegalStateException("Metered network confirmation is required")

class LocalModelInsufficientStorage(
    val requiredBytes: Long,
    val availableBytes: Long
) : IllegalStateException("Insufficient app-private storage for local model")

object LocalModelManager {
    private const val PREFERENCES = "signalasi_local_model_downloads_v1"
    private const val KEY_STATE = "state_"
    private const val KEY_BYTES = "bytes_"
    private const val KEY_TOTAL = "total_"
    private const val KEY_SOURCE_INDEX = "source_index_"
    private const val KEY_DETAIL = "detail_"

    fun profiles(context: Context): List<LocalModelRuntimeProfile> = LocalModelCatalog.profiles(context)

    fun profile(context: Context, id: String): LocalModelRuntimeProfile = LocalModelCatalog.find(context, id)

    fun storage(context: Context): LocalModelStorage = LocalModelStorage(context.applicationContext)

    fun isInstalled(context: Context, profile: LocalModelRuntimeProfile): Boolean =
        if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            savedInstallState(context, profile) == LocalModelInstallState.READY &&
                GenieXQairtModelManager.supportsDevice(profile)
        } else {
            storage(context).inspect(profile).installed
        }

    fun verifiedFile(context: Context, profile: LocalModelRuntimeProfile): File {
        require(profile.artifactFormat == LocalModelArtifactFormat.GGUF) {
            "QAIRT models are resolved through the Qualcomm model manager"
        }
        return storage(context).verifyForNativeLoad(profile)
    }

    fun state(context: Context, profile: LocalModelRuntimeProfile): LocalModelDownloadState {
        if (isInstalled(context, profile)) {
            return LocalModelDownloadState(
                state = LocalModelInstallState.READY,
                bytesDownloaded = profile.expectedModelFileBytes,
                totalBytes = profile.expectedModelFileBytes
            )
        }
        val prefs = preferences(context)
        val saved = savedInstallState(context, profile)
        val partialBytes = if (profile.artifactFormat == LocalModelArtifactFormat.GGUF) {
            storage(context).partialFile(profile).length()
        } else {
            prefs.getLong(KEY_BYTES + profile.id, 0L)
        }
        val effective = if (saved in setOf(LocalModelInstallState.DOWNLOADING, LocalModelInstallState.QUEUED) &&
            !LocalModelDownloadService.isActive(profile.id)
        ) {
            LocalModelInstallState.PAUSED
        } else saved
        return LocalModelDownloadState(
            state = effective,
            bytesDownloaded = maxOf(partialBytes, prefs.getLong(KEY_BYTES + profile.id, 0L))
                .coerceAtMost(profile.expectedModelFileBytes),
            totalBytes = prefs.getLong(KEY_TOTAL + profile.id, profile.expectedModelFileBytes)
                .takeIf { it > 0L } ?: profile.expectedModelFileBytes,
            sourceIndex = prefs.getInt(KEY_SOURCE_INDEX + profile.id, 0).coerceAtLeast(0),
            detail = prefs.getString(KEY_DETAIL + profile.id, "").orEmpty()
        )
    }

    fun start(context: Context, profile: LocalModelRuntimeProfile, allowMetered: Boolean = false) {
        require(profile.downloadable) { "The selected local-model artifact has no verified download metadata" }
        require(GenieXQairtModelManager.supportsDevice(profile)) {
            "${profile.displayName} is compiled for ${profile.targetChipset}"
        }
        if (isInstalled(context, profile)) return
        val storage = storage(context)
        val required = storage.requiredDownloadBytes(profile)
        val available = storage.availableBytes()
        if (available in 0 until required) throw LocalModelInsufficientStorage(required, available)
        if (isMetered(context) && !allowMetered) throw LocalModelMeteredConfirmationRequired(profile)
        record(
            context,
            profile,
            LocalModelDownloadState(
                state = LocalModelInstallState.QUEUED,
                bytesDownloaded = storage.partialFile(profile).length(),
                totalBytes = profile.expectedModelFileBytes,
                sourceIndex = state(context, profile).sourceIndex
            )
        )
        LocalModelDownloadService.start(context.applicationContext, profile.id)
    }

    fun pause(context: Context, profile: LocalModelRuntimeProfile) {
        LocalModelDownloadService.pause(context.applicationContext, profile.id)
    }

    fun cancel(context: Context, profile: LocalModelRuntimeProfile) {
        LocalModelDownloadService.cancel(context.applicationContext, profile.id)
    }

    fun delete(context: Context, profile: LocalModelRuntimeProfile) {
        LocalModelDownloadService.cancel(context.applicationContext, profile.id)
        LocalModelInferenceRuntime.unloadIfSelected(profile.id)
        if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            runBlocking { GenieXQairtModelManager.remove(context.applicationContext, profile) }
        } else {
            storage(context).delete(profile, modelLoaded = LocalModelInferenceRuntime.loadedProfileId() == profile.id)
        }
        clearState(context, profile)
        if (profile.sourceTrust == LocalModelSourceTrust.HUB_VERIFIED) {
            LocalModelProfileStore(context).delete(profile.id)
        }
        LocalModelRuntimeSettings.removeProfile(context, profile)
    }

    fun preferChinaMirror(context: Context): Boolean {
        val locale = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.resources.configuration.locales[0]
        } else {
            @Suppress("DEPRECATION")
            context.resources.configuration.locale
        }
        return locale.language.lowercase(Locale.ROOT) == "zh"
    }

    internal fun record(context: Context, profile: LocalModelRuntimeProfile, state: LocalModelDownloadState) {
        preferences(context).edit()
            .putString(KEY_STATE + profile.id, state.state.name)
            .putLong(KEY_BYTES + profile.id, state.bytesDownloaded.coerceAtLeast(0L))
            .putLong(KEY_TOTAL + profile.id, state.totalBytes.coerceAtLeast(0L))
            .putInt(KEY_SOURCE_INDEX + profile.id, state.sourceIndex.coerceAtLeast(0))
            .putString(KEY_DETAIL + profile.id, state.detail.take(512))
            .apply()
    }

    internal fun clearState(context: Context, profile: LocalModelRuntimeProfile) {
        preferences(context).edit()
            .remove(KEY_STATE + profile.id)
            .remove(KEY_BYTES + profile.id)
            .remove(KEY_TOTAL + profile.id)
            .remove(KEY_SOURCE_INDEX + profile.id)
            .remove(KEY_DETAIL + profile.id)
            .apply()
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun savedInstallState(
        context: Context,
        profile: LocalModelRuntimeProfile
    ): LocalModelInstallState = runCatching {
        enumValueOf<LocalModelInstallState>(
            preferences(context).getString(
                KEY_STATE + profile.id,
                LocalModelInstallState.NOT_INSTALLED.name
            ).orEmpty()
        )
    }.getOrDefault(LocalModelInstallState.NOT_INSTALLED)

    private fun isMetered(context: Context): Boolean {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return true
        val network = connectivity.activeNetwork ?: return true
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return true
        return !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }
}
