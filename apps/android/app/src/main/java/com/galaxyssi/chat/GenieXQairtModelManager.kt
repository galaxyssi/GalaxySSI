package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import com.geniex.sdk.GenieXSdk
import com.geniex.sdk.ModelManagerWrapper
import com.geniex.sdk.bean.HubSource
import com.geniex.sdk.bean.ModelPaths
import com.geniex.sdk.bean.ModelPullInput
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal data class GenieXQairtDownloadProgress(
    val downloadedBytes: Long,
    val totalBytes: Long
)

internal object GenieXQairtModelManager {
    fun supportsDevice(profile: LocalModelRuntimeProfile): Boolean {
        if (profile.artifactFormat != LocalModelArtifactFormat.QAIRT) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val deviceChipset = Build.SOC_MODEL.trim().uppercase()
        return deviceChipset.isNotBlank() && deviceChipset == profile.targetChipset.uppercase()
    }

    suspend fun pull(
        context: Context,
        profile: LocalModelRuntimeProfile,
        onProgress: (GenieXQairtDownloadProgress) -> Unit
    ): ModelPaths {
        require(profile.artifactFormat == LocalModelArtifactFormat.QAIRT)
        require(supportsDevice(profile)) {
            "${profile.displayName} requires ${profile.targetChipset}; this device reports ${Build.SOC_MODEL}"
        }
        initialize(context)
        var completed = false
        ModelManagerWrapper.pullFlow(
            ModelPullInput(
                model_name = profile.repositoryId,
                precision = profile.quantizationLabel.lowercase(),
                hub = HubSource.AIHUB,
                chipset = profile.targetChipset
            )
        ).collect { event ->
            when (event) {
                is ModelManagerWrapper.PullEvent.Progress -> {
                    onProgress(
                        GenieXQairtDownloadProgress(
                            downloadedBytes = event.files.sumOf { it.downloaded_bytes.coerceAtLeast(0L) },
                            totalBytes = event.files.sumOf { it.total_bytes.coerceAtLeast(0L) }
                        )
                    )
                }
                ModelManagerWrapper.PullEvent.Completed -> completed = true
                is ModelManagerWrapper.PullEvent.Error -> {
                    throw IllegalStateException(
                        "Qualcomm model download failed (${event.code}): ${event.message}"
                    )
                }
            }
        }
        check(completed) { "Qualcomm model download ended before completion" }
        return paths(context, profile)
            ?: throw IllegalStateException("Qualcomm model files were downloaded but not registered")
    }

    suspend fun paths(context: Context, profile: LocalModelRuntimeProfile): ModelPaths? {
        require(profile.artifactFormat == LocalModelArtifactFormat.QAIRT)
        initialize(context)
        return ModelManagerWrapper.getPaths(profile.repositoryId)
    }

    suspend fun remove(context: Context, profile: LocalModelRuntimeProfile) {
        if (profile.artifactFormat != LocalModelArtifactFormat.QAIRT) return
        initialize(context)
        ModelManagerWrapper.remove(profile.repositoryId)
    }

    private suspend fun initialize(context: Context) {
        suspendCancellableCoroutine { continuation ->
            GenieXSdk.getInstance().init(
                context.applicationContext,
                object : GenieXSdk.InitCallback {
                    override fun onSuccess() {
                        if (continuation.isActive) continuation.resume(Unit)
                    }

                    override fun onFailure(reason: String) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(
                                IllegalStateException("GenieX initialization failed: $reason")
                            )
                        }
                    }
                }
            )
        }
    }
}
