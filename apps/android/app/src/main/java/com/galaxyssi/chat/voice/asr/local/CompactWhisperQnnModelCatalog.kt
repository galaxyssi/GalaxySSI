package com.galaxyssi.chat.voice.asr.local

internal object CompactWhisperQnnModelCatalog {
    const val DEVICE_ROOT_NAME = "s26u"

    val tinyFloat = manifest(
        modelId = "whisper-tiny-qnn-float-s26u",
        displayName = "Whisper Tiny QNN Float",
        metadataModelId = "whisper_tiny",
        modelRootName = "whisper-tiny-qnn-float",
        profileId = "tiny",
        precision = "float",
        archiveName = "whisper_tiny-qnn_context_binary-float-$ASSET_CHIPSET",
        archiveUrlModel = "whisper_tiny",
        archiveSize = 105_910_421L,
        archiveEtag = "\"62df896b12ecb49b396af68abf16a117-13\"",
        archiveCrc64 = "6qtLRg6Gik4=",
        encoderCompressed = 17_638_554L,
        encoderSize = 20_029_440L,
        encoderCrc32 = 0x146bb9dfL,
        metadataCompressed = 688L,
        metadataSize = 10_385L,
        metadataCrc32 = 0x161af391L,
        decoderCompressed = 88_270_127L,
        decoderSize = 97_619_968L,
        decoderCrc32 = 0x1dc77f8eL,
        decoderLayers = 4,
        decoderHeads = 6,
        generation = GenerationAsset(
            repository = "openai/whisper-tiny",
            revision = "169d4a4341b33bc18d8881c4b69c2e104e1cc0af",
            sizeBytes = 3_747L,
            sha256 = "a5d5325911f16e74001a72fa13d6e208eee51548f994646de1f4b4cc8b35b512"
        )
    )

    val baseFloat = manifest(
        modelId = "whisper-base-qnn-float-s26u",
        displayName = "Whisper Base QNN Float",
        metadataModelId = "whisper_base",
        modelRootName = "whisper-base-qnn-float",
        profileId = "base",
        precision = "float",
        archiveName = "whisper_base-qnn_context_binary-float-$ASSET_CHIPSET",
        archiveUrlModel = "whisper_base",
        archiveSize = 180_939_859L,
        archiveEtag = "\"9856a8f66b1736a1c944ee1001311bf6-22\"",
        archiveCrc64 = "ugHDISaoqEk=",
        encoderCompressed = 44_546_018L,
        encoderSize = 49_831_936L,
        encoderCrc32 = 0x11f928f4L,
        metadataCompressed = 755L,
        metadataSize = 14_557L,
        metadataCrc32 = 0x19b7ef21L,
        decoderCompressed = 136_392_034L,
        decoderSize = 152_379_392L,
        decoderCrc32 = 0x2a59f7b1L,
        decoderLayers = 6,
        decoderHeads = 8,
        generation = GenerationAsset(
            repository = "openai/whisper-base",
            revision = "e37978b90ca9030d5170a5c07aadb050351a65bb",
            sizeBytes = 3_807L,
            sha256 = "444b3f636d2fff89dd9ecf549e2a085b61f7ff0fa0246d4628bac6a3b8cc9ba4"
        )
    )

    val smallW8A16 = manifest(
        modelId = "whisper-small-qnn-w8a16-s26u",
        displayName = "Whisper Small QNN W8A16",
        metadataModelId = "whisper_small_quantized",
        modelRootName = "whisper-small-qnn-w8a16",
        profileId = "small",
        precision = "w8a16",
        archiveName = "whisper_small_quantized-qnn_context_binary-w8a16-$ASSET_CHIPSET",
        archiveUrlModel = "whisper_small_quantized",
        archiveSize = 293_970_633L,
        archiveEtag = "\"e9be3436637e984605a933fe5440bfcd-36\"",
        archiveCrc64 = "Nl/GQsJZD8A=",
        encoderCompressed = 102_199_188L,
        encoderSize = 133_701_632L,
        encoderCrc32 = 0x27f047b1L,
        metadataCompressed = 1_996L,
        metadataSize = 43_657L,
        metadataCrc32 = 0x26adac3dL,
        decoderCompressed = 191_768_309L,
        decoderSize = 225_411_072L,
        decoderCrc32 = 0xbf3a755cL,
        decoderLayers = 12,
        decoderHeads = 12,
        generation = GenerationAsset(
            repository = "openai/whisper-small",
            revision = "973afd24965f72e36ca33b3055d56a652f456b4d",
            sizeBytes = 3_868L,
            sha256 = "71565b8ef50d0bf7a1193ed4bbed195b94e70c18894d81bba2f1233dcec3ab53"
        )
    )

    val smallFloat = manifest(
        modelId = "whisper-small-qnn-float-s26u",
        displayName = "Whisper Small QNN Float",
        metadataModelId = "whisper_small",
        modelRootName = "whisper-small-qnn-float",
        profileId = "small",
        precision = "float",
        archiveName = "whisper_small-qnn_context_binary-float-$ASSET_CHIPSET",
        archiveUrlModel = "whisper_small",
        archiveSize = 573_246_593L,
        archiveEtag = "\"94ccf87c7364b75d1c4dff79d39bc992-69\"",
        archiveCrc64 = "MNmR/qCbHpE=",
        encoderCompressed = 244_463_047L,
        encoderSize = 268_107_776L,
        encoderCrc32 = 0xbea0139cL,
        metadataCompressed = 942L,
        metadataSize = 27_187L,
        metadataCrc32 = 0x3f10bd7eL,
        decoderCompressed = 328_781_544L,
        decoderSize = 362_221_568L,
        decoderCrc32 = 0x05238881L,
        decoderLayers = 12,
        decoderHeads = 12,
        generation = GenerationAsset(
            repository = "openai/whisper-small",
            revision = "973afd24965f72e36ca33b3055d56a652f456b4d",
            sizeBytes = 3_868L,
            sha256 = "71565b8ef50d0bf7a1193ed4bbed195b94e70c18894d81bba2f1233dcec3ab53"
        )
    )

    val all = listOf(tinyFloat, baseFloat, smallW8A16, smallFloat)

    private fun manifest(
        modelId: String,
        displayName: String,
        metadataModelId: String,
        modelRootName: String,
        profileId: String,
        precision: String,
        archiveName: String,
        archiveUrlModel: String,
        archiveSize: Long,
        archiveEtag: String,
        archiveCrc64: String,
        encoderCompressed: Long,
        encoderSize: Long,
        encoderCrc32: Long,
        metadataCompressed: Long,
        metadataSize: Long,
        metadataCrc32: Long,
        decoderCompressed: Long,
        decoderSize: Long,
        decoderCrc32: Long,
        decoderLayers: Int,
        decoderHeads: Int,
        generation: GenerationAsset
    ) = CompactWhisperQnnManifest(
        profileId = profileId,
        modelRootName = modelRootName,
        manifest = LargeTurboQnnModelManifest(
            modelId = modelId,
            displayName = displayName,
            releaseVersion = RELEASE_VERSION,
            qairtVersion = QAIRT_VERSION,
            targetChipset = TARGET_CHIPSET,
            targetAliases = setOf(TARGET_CHIPSET, "sm8850-ad", "sm8850"),
            htpVersion = 81,
            socModel = 87,
            sampleRateHz = 16_000,
            melBins = 80,
            melFrames = 3_000,
            maxAudioSeconds = 30,
            decoderLayers = decoderLayers,
            decoderHeads = decoderHeads,
            decoderHeadSize = 64,
            maxDecoderTokens = 160,
            vocabularySize = 51_865,
            metadataModelId = metadataModelId,
            precision = precision,
            archive = QnnContextArchive(
                sourceUrl = "$PUBLIC_ASSETS/$archiveUrlModel/releases/v$RELEASE_VERSION/$archiveName.zip",
                sizeBytes = archiveSize,
                etag = archiveEtag,
                crc64NvmeBase64 = archiveCrc64,
                entries = listOf(
                    QnnContextArchiveEntry(
                        archivePath = "$archiveName/encoder.bin",
                        installedName = "encoder.bin",
                        compressedSizeBytes = encoderCompressed,
                        uncompressedSizeBytes = encoderSize,
                        crc32 = encoderCrc32
                    ),
                    QnnContextArchiveEntry(
                        archivePath = "$archiveName/metadata.json",
                        installedName = "whisper_metadata.json",
                        compressedSizeBytes = metadataCompressed,
                        uncompressedSizeBytes = metadataSize,
                        crc32 = metadataCrc32
                    ),
                    QnnContextArchiveEntry(
                        archivePath = "$archiveName/decoder.bin",
                        installedName = "decoder.bin",
                        compressedSizeBytes = decoderCompressed,
                        uncompressedSizeBytes = decoderSize,
                        crc32 = decoderCrc32
                    )
                )
            ),
            supportAssets = supportAssets(generation)
        )
    )

    private fun supportAssets(generation: GenerationAsset) = listOf(
        QnnContextSupportAsset(
            installedName = "tokenizer.tiktoken",
            sourceUrl = "$WHISPER_ASSETS/multilingual.tiktoken",
            downloadSizeBytes = 816_730L,
            sha256 = "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"
        ),
        QnnContextSupportAsset(
            installedName = "mel_filters.bin",
            sourceUrl = "$WHISPER_ASSETS/mel_filters.npz",
            downloadSizeBytes = 4_271L,
            installedSizeBytes = 80L * 201L * Float.SIZE_BYTES,
            sha256 = "7450ae70723a5ef9d341e3cee628c7cb0177f36ce42c44b7ed2bf3325f0f6d4c",
            transform = QnnContextSupportTransform.MEL_80_NPY_TO_FLOAT32
        ),
        QnnContextSupportAsset(
            installedName = "generation_config.json",
            sourceUrl = "https://huggingface.co/${generation.repository}/resolve/" +
                "${generation.revision}/generation_config.json",
            downloadSizeBytes = generation.sizeBytes,
            sha256 = generation.sha256
        )
    )

    private data class GenerationAsset(
        val repository: String,
        val revision: String,
        val sizeBytes: Long,
        val sha256: String
    )

    private const val RELEASE_VERSION = "0.59.0"
    private const val QAIRT_VERSION = "2.45.0.260326154327"
    private const val TARGET_CHIPSET = "qualcomm-snapdragon-8-elite-gen5-for-galaxy"
    private const val ASSET_CHIPSET = "qualcomm_snapdragon_8_elite_gen5_for_galaxy"
    private const val PUBLIC_ASSETS =
        "https://qaihub-public-assets.s3.us-west-2.amazonaws.com/qai-hub-models/models"
    private const val WHISPER_ASSETS =
        "https://raw.githubusercontent.com/openai/whisper/" +
            "5f86d1d86363843179951550570367b37c5d6f78/whisper/assets"
}

internal data class CompactWhisperQnnManifest(
    val profileId: String,
    val modelRootName: String,
    val manifest: LargeTurboQnnModelManifest
)
