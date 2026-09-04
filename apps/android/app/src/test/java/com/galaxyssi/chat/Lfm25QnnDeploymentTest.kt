package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class Lfm25QnnDeploymentTest {
    @Test
    fun manifest_requires_precompiled_w4a8_with_bounded_context_and_peak() {
        val manifest = manifest()

        assertEquals("W4A8", manifest.precision)
        assertEquals(2_048, manifest.defaultContextTokens)
        assertEquals(4_096, manifest.maximumContextTokens)
        assertTrue(manifest.profiledPeakBytes < Lfm25QnnDeploymentManifest.MAX_PROCESS_BYTES)
        assertEquals(LocalModelSourceTrust.SIGNED_DEPLOYMENT, manifest.toRuntimeProfile().sourceTrust)
    }

    @Test
    fun built_in_profile_is_a_downloadable_qnn_npu_model() {
        val profile = LocalModelRuntimeProfiles.LFM_2_5_2_6B_QAIRT

        assertEquals(Lfm25QnnDeploymentManifest.MODEL_ID, profile.id)
        assertEquals(LocalModelArtifactFormat.QAIRT, profile.artifactFormat)
        assertEquals(LocalModelAcceleratorKind.VENDOR_SDK, profile.preferredAccelerator)
        assertEquals("W4A8", profile.quantizationLabel)
        assertEquals("SM8850", profile.targetChipset)
        assertTrue(profile.downloadable)
        assertTrue(LocalModelRuntimeProfiles.all.any { it.id == profile.id })
    }

    @Test
    fun qnn_download_sources_use_the_signed_archive_and_prefer_china_mirrors() {
        val china = Lfm25QnnDownloadCatalog.sourceUrls(preferChinaMirror = true)
        val global = Lfm25QnnDownloadCatalog.sourceUrls(preferChinaMirror = false)

        assertTrue(china.first().startsWith("https://modelscope.cn/"))
        assertTrue(global.first().startsWith("https://huggingface.co/"))
        assertEquals(4, china.distinct().size)
        (china + global).forEach { url ->
            assertTrue(url.startsWith("https://"))
            assertTrue(url.contains(Lfm25QnnDownloadCatalog.ARCHIVE_FILE_NAME))
        }
    }

    @Test
    fun qnn_download_total_supports_resumed_content_ranges() {
        val total = Lfm25QnnDownloadCatalog.responseTotalBytes(
            requestedOffset = 1_000L,
            responseContentLength = 2_000L,
            contentRange = "bytes 1000-2999/9000",
            fallbackBytes = 4_000L
        )

        assertEquals(9_000L, total)
        assertTrue(runCatching {
            Lfm25QnnDownloadCatalog.responseTotalBytes(
                requestedOffset = 0L,
                responseContentLength = Lfm25QnnDownloadCatalog.MAX_ARCHIVE_BYTES + 1L,
                contentRange = null,
                fallbackBytes = 1L
            )
        }.isFailure)
    }

    @Test
    fun manifest_rejects_profiled_peak_without_safety_headroom() {
        val invalid = manifestJson().put(
            "profiled_peak_bytes",
            Lfm25QnnDeploymentManifest.MAX_PROCESS_BYTES
        )

        assertTrue(runCatching {
            Lfm25QnnDeploymentManifest.parse(invalid.toString())
        }.isFailure)
    }

    @Test
    fun signed_package_is_verified_committed_and_resolved() {
        val root = temporaryDirectory("lfm-qnn-install")
        val manifest = manifest()
        val store = Lfm25QnnDeploymentStore.forTesting(root) { true }

        val profile = store.install(packageBytes(manifest).inputStream())
        val artifact = store.runtimeArtifact(profile)

        assertTrue(store.isInstalled(profile))
        assertTrue(File(artifact.modelPath).isFile)
        assertTrue(File(artifact.tokenizerPath).isFile)
        assertEquals(manifest.profiledPeakBytes, artifact.manifest.profiledPeakBytes)
        store.delete()
        assertFalse(store.isInstalled(profile))
    }

    @Test
    fun partial_qnn_download_is_private_and_removed_with_the_model() {
        val root = temporaryDirectory("lfm-qnn-partial")
        val store = Lfm25QnnDeploymentStore.forTesting(root) { true }
        val partial = store.partialDownloadFile()
        partial.writeBytes(byteArrayOf(1, 2, 3))

        assertEquals(3L, store.partialDownloadBytes())
        store.delete()
        assertFalse(partial.exists())
    }

    @Test
    fun signed_package_rejects_untrusted_signature() {
        val root = temporaryDirectory("lfm-qnn-untrusted")
        val store = Lfm25QnnDeploymentStore.forTesting(root) { false }

        assertTrue(runCatching {
            store.install(packageBytes(manifest()).inputStream())
        }.isFailure)
    }

    @Test
    fun memory_policy_isolated_to_lfm_and_caps_context() {
        val lfm = manifest().toRuntimeProfile()
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT

        assertEquals(4_096, LocalModelQnnMemoryPolicy.effectiveContextTokens(lfm, 32_768))
        assertEquals(4_096, LocalModelQnnMemoryPolicy.effectiveContextTokens(qwen, 4_096))
        assertFalse(LocalModelQnnMemoryPolicy.appliesTo(qwen))
        assertTrue(LocalModelQnnMemoryPolicy.appliesTo(lfm))
    }

    @Test
    fun admission_requires_device_headroom_without_changing_other_models() {
        val manifest = manifest()
        val lfm = manifest.toRuntimeProfile()
        val denied = LocalModelQnnMemoryPolicy.admission(
            lfm,
            manifest,
            requestedContextTokens = 32_768,
            availableBytes = manifest.profiledPeakBytes
        )
        val qwen = LocalModelQnnMemoryPolicy.admission(
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT,
            manifest,
            requestedContextTokens = 4_096,
            availableBytes = 1L
        )

        assertFalse(denied.allowed)
        assertEquals(4_096, denied.effectiveContextTokens)
        assertTrue(qwen.allowed)
    }

    @Test
    fun watchdog_runs_only_for_lfm_profile() {
        val callback = CountDownLatch(1)
        val guard = LocalModelRuntimeMemoryWatchdog.start(
            profile = manifest().toRuntimeProfile(),
            reader = LocalModelProcessMemoryReader { LocalModelQnnMemoryPolicy.WATCHDOG_LIMIT_BYTES },
            onLimit = { callback.countDown() }
        )
        try {
            assertTrue(callback.await(1, TimeUnit.SECONDS))
            assertTrue(guard.peakBytes.get() >= LocalModelQnnMemoryPolicy.WATCHDOG_LIMIT_BYTES)
        } finally {
            guard.close()
        }

        val unaffected = LocalModelRuntimeMemoryWatchdog.start(
            profile = LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT,
            reader = LocalModelProcessMemoryReader { Long.MAX_VALUE },
            onLimit = { throw AssertionError("Existing models must not use the LFM watchdog") }
        )
        unaffected.close()
        assertEquals(0L, unaffected.peakBytes.get())
    }

    private fun manifest(): Lfm25QnnDeploymentManifest =
        Lfm25QnnDeploymentManifest.parse(manifestJson().toString())

    private fun manifestJson(): JSONObject {
        val model = MODEL_BYTES
        val tokenizer = TOKENIZER_BYTES
        return JSONObject()
            .put("format_version", 1)
            .put("model_id", Lfm25QnnDeploymentManifest.MODEL_ID)
            .put("display_name", "LFM2.5 2.6B QNN")
            .put("target_chipset", "SM8850")
            .put("precision", "W4A8")
            .put("default_context_tokens", 2_048)
            .put("maximum_context_tokens", 4_096)
            .put("runtime_id", "qairt")
            .put("model_path", "model.bin")
            .put("tokenizer_path", "tokenizer.json")
            .put("profiled_peak_bytes", 2_500L * 1024L * 1024L)
            .put("spill_fill_buffer_bytes", 256L * 1024L * 1024L)
            .put("qairt_version", "2.45.0")
            .put("files", org.json.JSONArray()
                .put(fileJson("model.bin", model))
                .put(fileJson("tokenizer.json", tokenizer)))
            .put("signature_key_id", "0".repeat(64))
            .put("signature", "test-signature")
    }

    private fun fileJson(path: String, bytes: ByteArray): JSONObject = JSONObject()
        .put("path", path)
        .put("size_bytes", bytes.size)
        .put("sha256", sha256(bytes))

    private fun packageBytes(manifest: Lfm25QnnDeploymentManifest): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            mapOf(
                Lfm25QnnDeploymentManifest.MANIFEST_FILE_NAME to
                    Lfm25QnnDeploymentManifest.toJson(manifest).toString().toByteArray(),
                "model.bin" to MODEL_BYTES,
                "tokenizer.json" to TOKENIZER_BYTES
            ).forEach { (path, bytes) ->
                zip.putNextEntry(ZipEntry(path))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return output.toByteArray()
    }

    private fun temporaryDirectory(name: String): File = File(
        System.getProperty("java.io.tmpdir"),
        "$name-${System.nanoTime()}"
    ).apply {
        deleteRecursively()
        mkdirs()
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }

    companion object {
        private val MODEL_BYTES = "precompiled-qnn-context".toByteArray()
        private val TOKENIZER_BYTES = "{}".toByteArray()
    }
}
