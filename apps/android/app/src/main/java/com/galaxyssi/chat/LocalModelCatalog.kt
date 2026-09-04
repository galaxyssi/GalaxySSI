package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

object LocalModelCatalog {
    fun profiles(context: Context): List<LocalModelRuntimeProfile> =
        (LocalModelRuntimeProfiles.all + LocalModelProfileStore(context).list())
            .distinctBy(LocalModelRuntimeProfile::id)

    fun find(context: Context, id: String): LocalModelRuntimeProfile =
        profiles(context).firstOrNull { it.id == id } ?: LocalModelRuntimeProfiles.QWEN_3_8B_Q4_K_M

    fun addHubArtifact(context: Context, artifact: HuggingFaceGgufArtifact): LocalModelRuntimeProfile {
        val profile = artifact.toRuntimeProfile()
        LocalModelProfileStore(context).upsert(profile)
        return profile
    }

    fun addSignedDeployment(context: Context, profile: LocalModelRuntimeProfile) {
        require(profile.sourceTrust == LocalModelSourceTrust.SIGNED_DEPLOYMENT)
        LocalModelProfileStore(context).upsert(profile)
    }
}

class LocalModelProfileStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun list(): List<LocalModelRuntimeProfile> {
        val encoded = preferences.getString(KEY_PROFILES, "[]").orEmpty()
        val array = runCatching { JSONArray(encoded) }.getOrElse { JSONArray() }
        return buildList {
            for (index in 0 until array.length()) {
                array.optJSONObject(index)?.toProfile()?.let(::add)
            }
        }
    }

    fun upsert(profile: LocalModelRuntimeProfile) {
        require(profile.sourceTrust in setOf(
            LocalModelSourceTrust.HUB_VERIFIED,
            LocalModelSourceTrust.SIGNED_DEPLOYMENT
        ))
        require(profile.downloadable)
        val updated = (list().filterNot { it.id == profile.id } + profile)
            .sortedBy(LocalModelRuntimeProfile::displayName)
        preferences.edit().putString(
            KEY_PROFILES,
            JSONArray().apply { updated.forEach { put(it.toJson()) } }.toString()
        ).apply()
    }

    fun delete(profileId: String) {
        val updated = list().filterNot { it.id == profileId }
        preferences.edit().putString(
            KEY_PROFILES,
            JSONArray().apply { updated.forEach { put(it.toJson()) } }.toString()
        ).apply()
    }

    companion object {
        private const val PREFERENCES = "galaxyssi_local_model_catalog_v1"
        private const val KEY_PROFILES = "hub_profiles"
    }
}

private fun LocalModelRuntimeProfile.toJson(): JSONObject = JSONObject()
    .put("id", id)
    .put("display_name", displayName)
    .put("expected_bytes", expectedModelFileBytes)
    .put("layers", layerCount)
    .put("kv_heads", keyValueHeadCount)
    .put("head_dimension", headDimension)
    .put("default_context", defaultContextTokens)
    .put("maximum_context", maximumContextTokens)
    .put("quantization", quantizationLabel)
    .put("repository_id", repositoryId)
    .put("file_name", fileName)
    .put("sha256", sha256)
    .put("parameter_billions", parameterCountBillions)
    .put("default_no_think", defaultNoThink)
    .put("vision_capable", visionCapable)
    .put("preferred_accelerator", preferredAccelerator.name)
    .put("source_trust", sourceTrust.name)
    .put("source_hub", sourceHub.name)
    .put("artifact_format", artifactFormat.name)
    .put("target_chipset", targetChipset)

private fun JSONObject.toProfile(): LocalModelRuntimeProfile? = runCatching {
    val trust = enumValueOf<LocalModelSourceTrust>(getString("source_trust"))
    require(trust in setOf(
        LocalModelSourceTrust.HUB_VERIFIED,
        LocalModelSourceTrust.SIGNED_DEPLOYMENT
    ))
    LocalModelRuntimeProfile(
        id = getString("id"),
        displayName = getString("display_name"),
        expectedModelFileBytes = getLong("expected_bytes"),
        layerCount = getInt("layers"),
        keyValueHeadCount = getInt("kv_heads"),
        headDimension = getInt("head_dimension"),
        defaultContextTokens = getInt("default_context"),
        maximumContextTokens = getInt("maximum_context"),
        quantizationLabel = getString("quantization"),
        repositoryId = getString("repository_id"),
        fileName = getString("file_name"),
        sha256 = getString("sha256").lowercase(Locale.ROOT),
        parameterCountBillions = optDouble("parameter_billions", 0.0),
        defaultNoThink = optBoolean("default_no_think"),
        visionCapable = optBoolean("vision_capable"),
        preferredAccelerator = optAcceleratorKind("preferred_accelerator"),
        sourceTrust = trust,
        sourceHub = runCatching {
            enumValueOf<LocalModelHubSource>(optString("source_hub", LocalModelHubSource.HUGGING_FACE.name))
        }.getOrDefault(LocalModelHubSource.HUGGING_FACE),
        artifactFormat = runCatching {
            enumValueOf<LocalModelArtifactFormat>(
                optString("artifact_format", LocalModelArtifactFormat.GGUF.name)
            )
        }.getOrDefault(LocalModelArtifactFormat.GGUF),
        targetChipset = optString("target_chipset")
    ).also { require(it.downloadable) }
}.getOrNull()

private fun JSONObject.optAcceleratorKind(name: String): LocalModelAcceleratorKind =
    runCatching { enumValueOf<LocalModelAcceleratorKind>(optString(name, LocalModelAcceleratorKind.CPU.name)) }
        .getOrDefault(LocalModelAcceleratorKind.CPU)
