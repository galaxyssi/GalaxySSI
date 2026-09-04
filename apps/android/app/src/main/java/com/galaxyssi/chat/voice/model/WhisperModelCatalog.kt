package com.galaxyssi.chat.voice.model

object WhisperModelCatalog {
    const val SCHEMA_VERSION = 2
    const val CATALOG_VERSION = "2026.08.01"

    val profiles: List<WhisperModelProfile> = listOf(
        profile(
            id = "tiny",
            family = WhisperModelFamily.TINY,
            displayName = "Tiny",
            fileName = "ggml-tiny.bin",
            size = 77_691_713L,
            sha = "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            quantization = WhisperQuantization.F16,
            mode = WhisperExecutionMode.REALTIME_PARTIAL,
            ram = 512L * MIB,
            reserve = 256L * MIB,
            partialMs = 750L,
            windowMs = 8_000L,
            enabled = true,
            bundled = true
        ),
        profile(
            id = "tiny_q5_1",
            family = WhisperModelFamily.TINY,
            displayName = "Tiny Q5_1",
            fileName = "ggml-tiny-q5_1.bin",
            size = 32_152_673L,
            sha = "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7",
            quantization = WhisperQuantization.Q5_1,
            mode = WhisperExecutionMode.REALTIME_PARTIAL,
            ram = 384L * MIB,
            reserve = 192L * MIB,
            partialMs = 650L,
            windowMs = 8_000L
        ),
        profile(
            id = "base",
            family = WhisperModelFamily.BASE,
            displayName = "Base",
            fileName = "ggml-base.bin",
            size = 147_951_465L,
            sha = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            quantization = WhisperQuantization.F16,
            mode = WhisperExecutionMode.REALTIME_PARTIAL,
            ram = 768L * MIB,
            reserve = 384L * MIB,
            partialMs = 1_100L,
            windowMs = 10_000L
        ),
        profile(
            id = "base_q5_1",
            family = WhisperModelFamily.BASE,
            displayName = "Base Q5_1",
            fileName = "ggml-base-q5_1.bin",
            size = 59_707_625L,
            sha = "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898",
            quantization = WhisperQuantization.Q5_1,
            mode = WhisperExecutionMode.REALTIME_PARTIAL,
            ram = 512L * MIB,
            reserve = 256L * MIB,
            partialMs = 950L,
            windowMs = 10_000L
        ),
        profile(
            id = "small",
            family = WhisperModelFamily.SMALL,
            displayName = "Small",
            fileName = "ggml-small.bin",
            size = 487_601_967L,
            sha = "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
            quantization = WhisperQuantization.F16,
            mode = WhisperExecutionMode.FINAL_ONLY,
            ram = 1_340L * MIB,
            reserve = 768L * MIB,
            partialMs = 2_200L,
            windowMs = 12_000L
        ),
        profile(
            id = "small_q5_1",
            family = WhisperModelFamily.SMALL,
            displayName = "Small Q5_1",
            fileName = "ggml-small-q5_1.bin",
            size = 190_085_487L,
            sha = "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
            quantization = WhisperQuantization.Q5_1,
            mode = WhisperExecutionMode.FINAL_ONLY,
            ram = 900L * MIB,
            reserve = 512L * MIB,
            partialMs = 1_800L,
            windowMs = 12_000L
        ),
        profile(
            id = "medium",
            family = WhisperModelFamily.MEDIUM,
            displayName = "Medium",
            fileName = "ggml-medium.bin",
            size = 1_533_763_059L,
            sha = "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
            quantization = WhisperQuantization.F16,
            mode = WhisperExecutionMode.SECOND_PASS,
            ram = 3_000L * MIB,
            reserve = 2_000L * MIB,
            partialMs = 4_500L,
            windowMs = 16_000L,
            experimental = true
        ),
        profile(
            id = "medium_q5_0",
            family = WhisperModelFamily.MEDIUM,
            displayName = "Medium Q5_0",
            fileName = "ggml-medium-q5_0.bin",
            size = 539_212_467L,
            sha = "19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f",
            quantization = WhisperQuantization.Q5_0,
            mode = WhisperExecutionMode.SECOND_PASS,
            ram = 1_700L * MIB,
            reserve = 1_000L * MIB,
            partialMs = 3_500L,
            windowMs = 16_000L,
            experimental = true
        ),
        profile(
            id = "large",
            family = WhisperModelFamily.LARGE_V3,
            displayName = "Large v3",
            fileName = "ggml-large-v3.bin",
            size = 3_095_033_483L,
            sha = "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2",
            quantization = WhisperQuantization.F16,
            mode = WhisperExecutionMode.SECOND_PASS,
            ram = 0L,
            reserve = 4_000L * MIB,
            partialMs = 7_500L,
            windowMs = 20_000L,
            experimental = true,
            legacyIds = setOf("large_v3")
        ),
        profile(
            id = "large_v3_q5_0",
            family = WhisperModelFamily.LARGE_V3,
            displayName = "Large v3 Q5_0",
            fileName = "ggml-large-v3-q5_0.bin",
            size = 1_081_140_203L,
            sha = "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1",
            quantization = WhisperQuantization.Q5_0,
            mode = WhisperExecutionMode.SECOND_PASS,
            ram = 2_600L * MIB,
            reserve = 2_000L * MIB,
            partialMs = 6_000L,
            windowMs = 20_000L,
            experimental = true
        ),
        profile(
            id = "large_v3_turbo",
            family = WhisperModelFamily.LARGE_V3_TURBO,
            displayName = "Large v3 Turbo",
            fileName = "ggml-large-v3-turbo.bin",
            size = 1_624_555_275L,
            sha = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
            quantization = WhisperQuantization.F16,
            mode = WhisperExecutionMode.SECOND_PASS,
            ram = 3_200L * MIB,
            reserve = 2_000L * MIB,
            partialMs = 2_800L,
            windowMs = 16_000L,
            experimental = true
        ),
        profile(
            id = "large_v3_turbo_q5_0",
            family = WhisperModelFamily.LARGE_V3_TURBO,
            displayName = "Large v3 Turbo Q5_0",
            fileName = "ggml-large-v3-turbo-q5_0.bin",
            size = 574_041_195L,
            sha = "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            quantization = WhisperQuantization.Q5_0,
            mode = WhisperExecutionMode.SECOND_PASS,
            ram = 1_800L * MIB,
            reserve = 1_000L * MIB,
            partialMs = 2_200L,
            windowMs = 16_000L,
            experimental = true
        )
    )

    val manifest: WhisperModelManifest = WhisperModelManifest(
        schemaVersion = SCHEMA_VERSION,
        catalogVersion = CATALOG_VERSION,
        models = profiles,
        trust = WhisperManifestTrust.APP_PINNED
    )

    private val byId = profiles.associateBy(WhisperModelProfile::id)
    private val aliases = buildMap {
        profiles.forEach { profile ->
            profile.legacyIds.forEach { alias -> put(alias, profile.id) }
        }
        put("large-v3", "large")
    }

    fun canonicalId(id: String): String = aliases[id.trim().lowercase()] ?: id.trim().lowercase()

    fun find(id: String): WhisperModelProfile? = byId[canonicalId(id)]

    fun require(id: String): WhisperModelProfile = requireNotNull(find(id)) { "Unknown Whisper model profile" }

    private fun profile(
        id: String,
        family: WhisperModelFamily,
        displayName: String,
        fileName: String,
        size: Long,
        sha: String,
        quantization: WhisperQuantization,
        mode: WhisperExecutionMode,
        ram: Long,
        reserve: Long,
        partialMs: Long,
        windowMs: Long,
        enabled: Boolean = false,
        bundled: Boolean = false,
        experimental: Boolean = false,
        legacyIds: Set<String> = emptySet()
    ) = WhisperModelProfile(
        id = id,
        family = family,
        displayName = displayName,
        fileName = fileName,
        sourceUrls = sourceUrls(fileName),
        expectedSizeBytes = size,
        sha256 = sha,
        quantization = quantization,
        multilingual = true,
        recommendedMode = mode,
        minAvailableRamBytes = ram,
        minFreeStorageBytes = reserve,
        defaultPartialIntervalMs = partialMs,
        maxWindowMs = windowMs,
        enabledByDefault = enabled,
        experimental = experimental,
        manifestVersion = SCHEMA_VERSION,
        bundledAsset = bundled,
        legacyIds = legacyIds
    )

    private fun sourceUrls(fileName: String): List<String> = listOf(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName",
        "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/$fileName"
    )

    private const val MIB = 1_048_576L
}
