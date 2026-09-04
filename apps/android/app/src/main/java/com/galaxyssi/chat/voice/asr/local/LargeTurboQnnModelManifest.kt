package com.galaxyssi.chat.voice.asr.local

import java.net.URI

data class QnnContextArchiveEntry(
    val archivePath: String,
    val installedName: String,
    val compressedSizeBytes: Long,
    val uncompressedSizeBytes: Long,
    val crc32: Long
) {
    init {
        require(archivePath.isNotBlank() && !archivePath.startsWith('/') && ".." !in archivePath.split('/'))
        require(installedName.matches(FILE_NAME_PATTERN))
        require(compressedSizeBytes >= 0L)
        require(uncompressedSizeBytes > 0L)
        require(crc32 in 0L..0xffff_ffffL)
    }
}

data class QnnContextSupportAsset(
    val installedName: String,
    val sourceUrl: String,
    val downloadSizeBytes: Long,
    val installedSizeBytes: Long = downloadSizeBytes,
    val sha256: String,
    val transform: QnnContextSupportTransform = QnnContextSupportTransform.NONE
) {
    init {
        require(installedName.matches(FILE_NAME_PATTERN))
        requireHttps(sourceUrl)
        require(downloadSizeBytes > 0L && installedSizeBytes > 0L)
        require(sha256.matches(SHA256_PATTERN))
    }
}

enum class QnnContextSupportTransform {
    NONE,
    MEL_80_NPY_TO_FLOAT32,
    MEL_128_NPY_TO_FLOAT32
}

data class QnnContextArchive(
    val sourceUrl: String,
    val sizeBytes: Long,
    val etag: String,
    val crc64NvmeBase64: String,
    val sha256: String? = null,
    val entries: List<QnnContextArchiveEntry>
) {
    init {
        requireHttps(sourceUrl)
        require(sizeBytes > 0L)
        require(etag.isNotBlank())
        require(crc64NvmeBase64.isNotBlank())
        require(sha256 == null || sha256.matches(SHA256_PATTERN))
        require(entries.isNotEmpty())
        require(entries.map(QnnContextArchiveEntry::archivePath).distinct().size == entries.size)
        require(entries.map(QnnContextArchiveEntry::installedName).distinct().size == entries.size)
    }

    val installedSizeBytes: Long
        get() = entries.sumOf(QnnContextArchiveEntry::uncompressedSizeBytes)
}

data class LargeTurboQnnModelManifest(
    val modelId: String,
    val displayName: String,
    val releaseVersion: String,
    val qairtVersion: String,
    val targetChipset: String,
    val targetAliases: Set<String>,
    val htpVersion: Int,
    val socModel: Int,
    val sampleRateHz: Int,
    val melBins: Int,
    val melFrames: Int,
    val maxAudioSeconds: Int,
    val decoderLayers: Int,
    val decoderHeads: Int,
    val decoderHeadSize: Int,
    val maxDecoderTokens: Int,
    val vocabularySize: Int,
    val archive: QnnContextArchive,
    val supportAssets: List<QnnContextSupportAsset>,
    val metadataModelId: String = "whisper_large_v3_turbo",
    val precision: String = "float"
) {
    init {
        require(modelId.matches(ID_PATTERN))
        require(displayName.isNotBlank())
        require(releaseVersion.matches(VERSION_PATTERN))
        require(qairtVersion.isNotBlank())
        require(targetChipset.isNotBlank() && targetAliases.isNotEmpty())
        require(htpVersion > 0 && socModel > 0)
        require(sampleRateHz == 16_000)
        require(melBins in setOf(80, 128) && melFrames == 3_000)
        require(maxAudioSeconds == 30)
        require(decoderLayers in 1..64 && decoderHeads in 1..64 && decoderHeadSize == 64)
        require(maxDecoderTokens in 1..200)
        require(vocabularySize in 51_865..51_866)
        require(metadataModelId.matches(Regex("[a-z0-9][a-z0-9_]{0,95}")))
        require(precision in setOf("float", "w8a16"))
        require(supportAssets.map(QnnContextSupportAsset::installedName).distinct().size == supportAssets.size)
    }

    val installDirectoryName: String
        get() = "$releaseVersion-$targetChipset"

    val totalInstalledSizeBytes: Long
        get() = archive.installedSizeBytes + supportAssets.sumOf(QnnContextSupportAsset::installedSizeBytes)
}

object LargeTurboQnnModelCatalog {
    const val MODEL_ID = "whisper-large-v3-turbo-qnn-s26u"
    const val MODEL_ROOT_NAME = "whisper-large-v3-turbo"
    const val DEVICE_ROOT_NAME = "s26u"

    val s26Ultra = LargeTurboQnnModelManifest(
        modelId = MODEL_ID,
        displayName = "Whisper Large v3 Turbo QNN",
        releaseVersion = "0.59.0",
        qairtVersion = "2.45.0.260326154327",
        targetChipset = "qualcomm-snapdragon-8-elite-gen5-for-galaxy",
        targetAliases = setOf(
            "qualcomm-snapdragon-8-elite-gen5-for-galaxy",
            "sm8850-ad",
            "sm8850"
        ),
        htpVersion = 81,
        socModel = 87,
        sampleRateHz = 16_000,
        melBins = 128,
        melFrames = 3_000,
        maxAudioSeconds = 30,
        decoderLayers = 4,
        decoderHeads = 20,
        decoderHeadSize = 64,
        maxDecoderTokens = 160,
        vocabularySize = 51_866,
        archive = QnnContextArchive(
            sourceUrl = "https://qaihub-public-assets.s3.us-west-2.amazonaws.com/" +
                "qai-hub-models/models/whisper_large_v3_turbo/releases/v0.59.0/" +
                "whisper_large_v3_turbo-qnn_context_binary-float-" +
                "qualcomm_snapdragon_8_elite_gen5_for_galaxy.zip",
            sizeBytes = 2_016_745_993L,
            etag = "\"8a89a6ab484fc0d2659e344baadd74f6-241\"",
            crc64NvmeBase64 = "rOuHIZmpck4=",
            entries = listOf(
                QnnContextArchiveEntry(
                    archivePath = "$ARCHIVE_ROOT/encoder.bin",
                    installedName = "encoder.bin",
                    compressedSizeBytes = 1_600_806_197L,
                    uncompressedSizeBytes = 1_753_608_192L,
                    crc32 = 0xe3a408e5L
                ),
                QnnContextArchiveEntry(
                    archivePath = "$ARCHIVE_ROOT/metadata.json",
                    installedName = "whisper_metadata.json",
                    compressedSizeBytes = 703L,
                    uncompressedSizeBytes = 10_438L,
                    crc32 = 0x9f129388L
                ),
                QnnContextArchiveEntry(
                    archivePath = "$ARCHIVE_ROOT/decoder.bin",
                    installedName = "decoder.bin",
                    compressedSizeBytes = 415_937_961L,
                    uncompressedSizeBytes = 452_882_432L,
                    crc32 = 0x2197bc95L
                )
            )
        ),
        supportAssets = listOf(
            QnnContextSupportAsset(
                installedName = "tokenizer.tiktoken",
                sourceUrl = "https://raw.githubusercontent.com/openai/whisper/" +
                    "5f86d1d86363843179951550570367b37c5d6f78/whisper/assets/multilingual.tiktoken",
                downloadSizeBytes = 816_730L,
                sha256 = "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"
            ),
            QnnContextSupportAsset(
                installedName = "mel_filters.bin",
                sourceUrl = "https://raw.githubusercontent.com/openai/whisper/" +
                    "5f86d1d86363843179951550570367b37c5d6f78/whisper/assets/mel_filters.npz",
                downloadSizeBytes = 4_271L,
                installedSizeBytes = 102_912L,
                sha256 = "7450ae70723a5ef9d341e3cee628c7cb0177f36ce42c44b7ed2bf3325f0f6d4c",
                transform = QnnContextSupportTransform.MEL_128_NPY_TO_FLOAT32
            ),
            QnnContextSupportAsset(
                installedName = "generation_config.json",
                sourceUrl = "https://huggingface.co/openai/whisper-large-v3-turbo/resolve/" +
                    "41f01f3fe87f28c78e2fbf8b568835947dd65ed9/generation_config.json",
                downloadSizeBytes = 3_772L,
                sha256 = "cce11bfe3aaa6ae9e072ea2637caaec8795e68d9b67e655a5af16ee509681a4c"
            )
        )
    )

    private const val ARCHIVE_ROOT =
        "whisper_large_v3_turbo-qnn_context_binary-float-" +
            "qualcomm_snapdragon_8_elite_gen5_for_galaxy"
}

private fun requireHttps(value: String) {
    val uri = runCatching { URI(value) }.getOrElse { throw IllegalArgumentException("Invalid model URL", it) }
    require(uri.scheme.equals("https", ignoreCase = true) && !uri.host.isNullOrBlank() && uri.userInfo == null) {
        "Model assets must use public HTTPS URLs"
    }
}

private val FILE_NAME_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
private val ID_PATTERN = Regex("[a-z0-9][a-z0-9-]{0,95}")
private val VERSION_PATTERN = Regex("[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][A-Za-z0-9._-]+)?")
private val SHA256_PATTERN = Regex("[a-f0-9]{64}")
