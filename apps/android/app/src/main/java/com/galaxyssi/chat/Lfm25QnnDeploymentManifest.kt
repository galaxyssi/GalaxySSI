package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

internal data class Lfm25QnnDeploymentFile(
    val path: String,
    val sizeBytes: Long,
    val sha256: String
) {
    init {
        require(isSafeRelativePath(path)) { "Unsafe QNN deployment path: $path" }
        require(sizeBytes > 0L) { "QNN deployment files must not be empty" }
        require(sha256.matches(SHA256_PATTERN)) { "Invalid QNN deployment SHA-256" }
    }
}

internal data class Lfm25QnnDeploymentManifest(
    val modelId: String,
    val displayName: String,
    val targetChipset: String,
    val precision: String,
    val defaultContextTokens: Int,
    val maximumContextTokens: Int,
    val runtimeId: String,
    val modelPath: String,
    val tokenizerPath: String,
    val profiledPeakBytes: Long,
    val spillFillBufferBytes: Long,
    val qairtVersion: String,
    val files: List<Lfm25QnnDeploymentFile>,
    val signatureKeyId: String,
    val signature: String,
    val formatVersion: Int = FORMAT_VERSION
) {
    init {
        require(formatVersion == FORMAT_VERSION) { "Unsupported QNN deployment format" }
        require(modelId == MODEL_ID) { "This package is not the supported LFM2.5 deployment" }
        require(displayName.isNotBlank())
        require(targetChipset.equals(TARGET_CHIPSET, ignoreCase = true)) {
            "The QNN deployment must target $TARGET_CHIPSET"
        }
        require(precision.equals(REQUIRED_PRECISION, ignoreCase = true)) {
            "LFM2.5 must use $REQUIRED_PRECISION to stay within its memory budget"
        }
        require(defaultContextTokens in MIN_CONTEXT_TOKENS..DEFAULT_CONTEXT_LIMIT)
        require(maximumContextTokens in defaultContextTokens..MAX_CONTEXT_LIMIT)
        require(runtimeId == QAIRT_RUNTIME_ID)
        require(isSafeRelativePath(modelPath))
        require(isSafeRelativePath(tokenizerPath))
        require(profiledPeakBytes in 1L..MAX_PROFILED_PEAK_BYTES) {
            "The profiled LFM2.5 process peak exceeds the deployment budget"
        }
        require(spillFillBufferBytes in 0L..profiledPeakBytes) {
            "Invalid QNN spill-fill buffer size"
        }
        require(qairtVersion.isNotBlank())
        require(files.isNotEmpty() && files.size <= MAX_FILES)
        require(files.map(Lfm25QnnDeploymentFile::path).distinct().size == files.size)
        require(files.any { it.path == modelPath || it.path.startsWith("$modelPath/") }) {
            "The declared model path is missing from the package"
        }
        require(files.any { it.path == tokenizerPath }) {
            "The declared tokenizer is missing from the package"
        }
        require(signatureKeyId.matches(SHA256_PATTERN))
        require(signature.isNotBlank())
        require(installedSizeBytes <= MAX_INSTALLED_BYTES) { "The QNN deployment package is too large" }
    }

    val installedSizeBytes: Long
        get() = files.sumOf(Lfm25QnnDeploymentFile::sizeBytes)

    fun signingPayload(): ByteArray = buildList {
        add(formatVersion.toString())
        add(modelId)
        add(displayName)
        add(targetChipset.uppercase(Locale.ROOT))
        add(precision.uppercase(Locale.ROOT))
        add(defaultContextTokens.toString())
        add(maximumContextTokens.toString())
        add(runtimeId)
        add(modelPath)
        add(tokenizerPath)
        add(profiledPeakBytes.toString())
        add(spillFillBufferBytes.toString())
        add(qairtVersion)
        files.sortedBy(Lfm25QnnDeploymentFile::path).forEach { file ->
            add(file.path)
            add(file.sizeBytes.toString())
            add(file.sha256)
        }
        add(signatureKeyId)
    }.joinToString("") { value ->
        "${value.toByteArray(Charsets.UTF_8).size}:$value"
    }.toByteArray(Charsets.UTF_8)

    fun toRuntimeProfile(): LocalModelRuntimeProfile = LocalModelRuntimeProfile(
        id = modelId,
        displayName = displayName,
        expectedModelFileBytes = installedSizeBytes,
        layerCount = 30,
        keyValueHeadCount = 8,
        headDimension = 64,
        defaultContextTokens = defaultContextTokens,
        maximumContextTokens = maximumContextTokens,
        quantizationLabel = REQUIRED_PRECISION,
        repositoryId = SOURCE_MODEL_ID,
        parameterCountBillions = 2.6,
        defaultNoThink = true,
        preferredAccelerator = LocalModelAcceleratorKind.VENDOR_SDK,
        sourceTrust = LocalModelSourceTrust.SIGNED_DEPLOYMENT,
        artifactFormat = LocalModelArtifactFormat.QAIRT,
        targetChipset = TARGET_CHIPSET
    )

    companion object {
        const val MODEL_ID = "lfm2-5-2-6b-qnn-w4a8-sm8850"
        const val SOURCE_MODEL_ID = "LiquidAI/LFM2.5-2.6B"
        const val TARGET_CHIPSET = "SM8850"
        const val REQUIRED_PRECISION = "W4A8"
        const val MANIFEST_FILE_NAME = "galaxyssi-qnn-deployment.json"
        const val QAIRT_RUNTIME_ID = "qairt"
        const val DEFAULT_CONTEXT_LIMIT = 2_048
        const val MAX_CONTEXT_LIMIT = 4_096
        const val MAX_PROCESS_BYTES = 3L * 1024L * 1024L * 1024L
        const val MAX_PROFILED_PEAK_BYTES = MAX_PROCESS_BYTES - 256L * 1024L * 1024L
        const val MAX_INSTALLED_BYTES = 3L * 1024L * 1024L * 1024L
        private const val MIN_CONTEXT_TOKENS = 512
        private const val MAX_FILES = 64
        private const val FORMAT_VERSION = 1

        fun parse(raw: String): Lfm25QnnDeploymentManifest {
            require(raw.toByteArray(Charsets.UTF_8).size <= MAX_MANIFEST_BYTES) {
                "The QNN deployment manifest is too large"
            }
            val root = JSONObject(raw)
            val fileValues = root.getJSONArray("files")
            val files = buildList {
                for (index in 0 until fileValues.length()) {
                    val value = fileValues.getJSONObject(index)
                    add(
                        Lfm25QnnDeploymentFile(
                            path = value.getString("path"),
                            sizeBytes = value.getLong("size_bytes"),
                            sha256 = value.getString("sha256").lowercase(Locale.ROOT)
                        )
                    )
                }
            }
            return Lfm25QnnDeploymentManifest(
                formatVersion = root.getInt("format_version"),
                modelId = root.getString("model_id"),
                displayName = root.getString("display_name"),
                targetChipset = root.getString("target_chipset"),
                precision = root.getString("precision"),
                defaultContextTokens = root.getInt("default_context_tokens"),
                maximumContextTokens = root.getInt("maximum_context_tokens"),
                runtimeId = root.getString("runtime_id"),
                modelPath = root.getString("model_path"),
                tokenizerPath = root.getString("tokenizer_path"),
                profiledPeakBytes = root.getLong("profiled_peak_bytes"),
                spillFillBufferBytes = root.getLong("spill_fill_buffer_bytes"),
                qairtVersion = root.getString("qairt_version"),
                files = files,
                signatureKeyId = root.getString("signature_key_id").lowercase(Locale.ROOT),
                signature = root.getString("signature")
            )
        }

        fun toJson(manifest: Lfm25QnnDeploymentManifest): JSONObject = JSONObject()
            .put("format_version", manifest.formatVersion)
            .put("model_id", manifest.modelId)
            .put("display_name", manifest.displayName)
            .put("target_chipset", manifest.targetChipset)
            .put("precision", manifest.precision)
            .put("default_context_tokens", manifest.defaultContextTokens)
            .put("maximum_context_tokens", manifest.maximumContextTokens)
            .put("runtime_id", manifest.runtimeId)
            .put("model_path", manifest.modelPath)
            .put("tokenizer_path", manifest.tokenizerPath)
            .put("profiled_peak_bytes", manifest.profiledPeakBytes)
            .put("spill_fill_buffer_bytes", manifest.spillFillBufferBytes)
            .put("qairt_version", manifest.qairtVersion)
            .put("files", JSONArray().apply {
                manifest.files.forEach { file ->
                    put(JSONObject()
                        .put("path", file.path)
                        .put("size_bytes", file.sizeBytes)
                        .put("sha256", file.sha256))
                }
            })
            .put("signature_key_id", manifest.signatureKeyId)
            .put("signature", manifest.signature)
    }
}

internal fun Lfm25QnnDeploymentManifest.resolveModelPath(root: File): File =
    resolveInside(root, modelPath)

internal fun Lfm25QnnDeploymentManifest.resolveTokenizerPath(root: File): File =
    resolveInside(root, tokenizerPath)

private fun resolveInside(root: File, relativePath: String): File {
    val canonicalRoot = root.canonicalFile
    val candidate = File(canonicalRoot, relativePath).canonicalFile
    require(candidate.path == canonicalRoot.path || candidate.path.startsWith(canonicalRoot.path + File.separator)) {
        "QNN deployment path escapes its installation directory"
    }
    return candidate
}

private fun isSafeRelativePath(value: String): Boolean = value.isNotBlank() &&
    value.matches(Regex("[A-Za-z0-9._/-]+")) &&
    !value.startsWith('/') && !value.startsWith('\\') && ':' !in value &&
    value.split('/', '\\').all { it.isNotBlank() && it != "." && it != ".." }

private const val MAX_MANIFEST_BYTES = 256 * 1024
private val SHA256_PATTERN = Regex("[a-f0-9]{64}")
