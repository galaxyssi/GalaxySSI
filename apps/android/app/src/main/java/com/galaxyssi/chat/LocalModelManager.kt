package com.galaxyssi.chat

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import kotlinx.coroutines.runBlocking
import java.io.File
import java.io.InputStream
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
    ): Set<String> = updatedProfiles(currentProfileIds, installedProfileId, enabled = true)

    fun updatedProfiles(
        currentProfileIds: Set<String>,
        profileId: String,
        enabled: Boolean
    ): Set<String> {
        require(profileId.isNotBlank()) { "Local-model profile ID is required" }
        return if (enabled) currentProfileIds + profileId else currentProfileIds - profileId
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
    private const val PREFERENCES = "galaxyssi_local_model_downloads_v1"
    private const val KEY_STATE = "state_"
    private const val KEY_BYTES = "bytes_"
    private const val KEY_TOTAL = "total_"
    private const val KEY_SOURCE_INDEX = "source_index_"
    private const val KEY_DETAIL = "detail_"

    fun profiles(context: Context): List<LocalModelRuntimeProfile> = LocalModelCatalog.profiles(context)

    fun profile(context: Context, id: String): LocalModelRuntimeProfile = LocalModelCatalog.find(context, id)

    fun storage(context: Context): LocalModelStorage = LocalModelStorage(context.applicationContext)

    fun isInstalled(context: Context, profile: LocalModelRuntimeProfile): Boolean =
        if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            Lfm25QnnDeploymentStore(context).isInstalled(profile) &&
                GenieXQairtModelManager.supportsDevice(profile)
        } else if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
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
            val installedBytes = if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
                Lfm25QnnDeploymentStore(context).installedManifest()?.installedSizeBytes
            } else {
                null
            } ?: profile.expectedModelFileBytes
            return LocalModelDownloadState(
                state = LocalModelInstallState.READY,
                bytesDownloaded = installedBytes,
                totalBytes = installedBytes
            )
        }
        val prefs = preferences(context)
        val saved = savedInstallState(context, profile)
        if (LocalModelQnnMemoryPolicy.appliesTo(profile) && saved == LocalModelInstallState.READY) {
            return LocalModelDownloadState(
                state = LocalModelInstallState.FAILED,
                totalBytes = profile.expectedModelFileBytes
            )
        }
        val partialBytes = when {
            LocalModelQnnMemoryPolicy.appliesTo(profile) ->
                Lfm25QnnDeploymentStore(context).partialDownloadBytes()
            profile.artifactFormat == LocalModelArtifactFormat.GGUF ->
                storage(context).partialFile(profile).length()
            else -> prefs.getLong(KEY_BYTES + profile.id, 0L)
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

    fun start(
        context: Context,
        profile: LocalModelRuntimeProfile,
        @Suppress("UNUSED_PARAMETER") allowMetered: Boolean = false
    ) {
        require(profile.downloadable) { "The selected local-model artifact has no verified download metadata" }
        require(GenieXQairtModelManager.supportsDevice(profile)) {
            "${profile.displayName} is compiled for ${profile.targetChipset}"
        }
        if (isInstalled(context, profile)) return
        val storage = storage(context)
        val lfmStore = Lfm25QnnDeploymentStore(context)
        val required = if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            lfmStore.requiredDownloadBytes(profile.expectedModelFileBytes)
        } else {
            storage.requiredDownloadBytes(profile)
        }
        val available = if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            lfmStore.availableBytes()
        } else {
            storage.availableBytes()
        }
        if (available in 0 until required) throw LocalModelInsufficientStorage(required, available)
        record(
            context,
            profile,
            LocalModelDownloadState(
                state = LocalModelInstallState.QUEUED,
                bytesDownloaded = if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
                    lfmStore.partialDownloadBytes()
                } else {
                    storage.partialFile(profile).length()
                },
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
        if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            Lfm25QnnDeploymentStore(context).delete()
        } else if (profile.artifactFormat == LocalModelArtifactFormat.QAIRT) {
            runBlocking { GenieXQairtModelManager.remove(context.applicationContext, profile) }
        } else {
            storage(context).delete(profile, modelLoaded = LocalModelInferenceRuntime.loadedProfileId() == profile.id)
        }
        clearState(context, profile)
        if (profile.sourceTrust in setOf(
            LocalModelSourceTrust.HUB_VERIFIED,
            LocalModelSourceTrust.SIGNED_DEPLOYMENT
        )) {
            LocalModelProfileStore(context).delete(profile.id)
        }
        LocalModelRuntimeSettings.removeProfile(context, profile)
    }

    fun importSignedQnnDeployment(
        context: Context,
        input: InputStream,
        onBytesCopied: (Long) -> Unit = {}
    ): LocalModelRuntimeProfile {
        val store = Lfm25QnnDeploymentStore(context)
        val profile = store.install(input, onBytesCopied)
        if (!GenieXQairtModelManager.supportsDevice(profile)) {
            store.delete()
            error("${profile.displayName} is compiled for ${profile.targetChipset}")
        }
        LocalModelCatalog.addSignedDeployment(context, profile)
        record(
            context,
            profile,
            LocalModelDownloadState(
                state = LocalModelInstallState.READY,
                bytesDownloaded = profile.expectedModelFileBytes,
                totalBytes = profile.expectedModelFileBytes
            )
        )
        LocalModelRuntimeSettings.registerInstalledProfile(context, profile)
        return profile
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
