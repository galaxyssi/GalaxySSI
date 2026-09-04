package com.galaxyssi.chat.voice.model

import org.json.JSONObject

enum class WhisperManifestTrust {
    APP_PINNED,
    SIGNED_REMOTE
}

data class WhisperModelManifest(
    val schemaVersion: Int,
    val catalogVersion: String,
    val models: List<WhisperModelProfile>,
    val trust: WhisperManifestTrust,
    val signature: String = ""
)

fun interface WhisperManifestSignatureVerifier {
    fun verify(canonicalPayload: String, signature: String): Boolean
}

object WhisperModelManifestParser {
    fun parseSigned(json: String, verifier: WhisperManifestSignatureVerifier): WhisperModelManifest {
        val root = JSONObject(json)
        val schemaVersion = root.getInt("schemaVersion")
        require(schemaVersion == WhisperModelCatalog.SCHEMA_VERSION) { "Unsupported Whisper manifest schema" }
        val catalogVersion = root.getString("catalogVersion")
        require(CATALOG_VERSION_PATTERN.matches(catalogVersion)) { "Invalid catalog version" }
        val signature = root.getString("signature")
        require(signature.isNotBlank()) { "Whisper manifest signature is required" }
        val modelsJson = root.getJSONArray("models")
        val models = buildList {
            repeat(modelsJson.length()) { index -> add(parseProfile(modelsJson.getJSONObject(index), schemaVersion)) }
        }
        require(models.isNotEmpty()) { "Whisper manifest is empty" }
        require(models.map { it.id }.distinct().size == models.size) { "Duplicate model profile id" }
        require(models.map { it.fileName }.distinct().size == models.size) { "Duplicate model file name" }
        val manifest = WhisperModelManifest(
            schemaVersion = schemaVersion,
            catalogVersion = catalogVersion,
            models = models,
            trust = WhisperManifestTrust.SIGNED_REMOTE,
            signature = signature
        )
        require(verifier.verify(canonicalPayload(manifest), signature)) { "Whisper manifest signature is invalid" }
        return manifest
    }

    fun canonicalPayload(manifest: WhisperModelManifest): String = buildString {
        appendField(manifest.schemaVersion.toString())
        appendField(manifest.catalogVersion)
        manifest.models.sortedBy(WhisperModelProfile::id).forEach { model ->
            appendField(model.id)
            appendField(model.family.name)
            appendField(model.displayName)
            appendField(model.fileName)
            appendField(model.sourceUrls.size.toString())
            model.sourceUrls.forEach { source -> appendField(source) }
            appendField(model.expectedSizeBytes.toString())
            appendField(model.sha256)
            appendField(model.quantization.name)
            appendField(model.multilingual.toString())
            appendField(model.recommendedMode.name)
            appendField(model.minAvailableRamBytes.toString())
            appendField(model.minFreeStorageBytes.toString())
            appendField(model.defaultPartialIntervalMs.toString())
            appendField(model.maxWindowMs.toString())
            appendField(model.enabledByDefault.toString())
            appendField(model.experimental.toString())
            appendField(model.manifestVersion.toString())
        }
    }

    private fun StringBuilder.appendField(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        append(bytes.size).append(':').append(value).append('\n')
    }

    private fun parseProfile(value: JSONObject, schemaVersion: Int): WhisperModelProfile {
        val urls = value.getJSONArray("sourceUrls")
        return WhisperModelProfile(
            id = value.getString("id"),
            family = enumValueOf(value.getString("family")),
            displayName = value.getString("displayName"),
            fileName = value.getString("fileName"),
            sourceUrls = buildList { repeat(urls.length()) { add(urls.getString(it)) } },
            expectedSizeBytes = value.getLong("expectedSizeBytes"),
            sha256 = value.getString("sha256").lowercase(),
            quantization = enumValueOf(value.getString("quantization")),
            multilingual = value.getBoolean("multilingual"),
            recommendedMode = enumValueOf(value.getString("recommendedMode")),
            minAvailableRamBytes = value.getLong("minAvailableRamBytes"),
            minFreeStorageBytes = value.getLong("minFreeStorageBytes"),
            defaultPartialIntervalMs = value.getLong("defaultPartialIntervalMs"),
            maxWindowMs = value.getLong("maxWindowMs"),
            enabledByDefault = value.optBoolean("enabledByDefault", false),
            experimental = value.optBoolean("experimental", false),
            manifestVersion = value.optInt("manifestVersion", schemaVersion).also {
                require(it == schemaVersion) { "Model manifest version does not match its schema" }
            },
            bundledAsset = false
        )
    }

    private val CATALOG_VERSION_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
}
