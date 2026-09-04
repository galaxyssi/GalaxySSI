package com.galaxyssi.chat.voice.asr.local

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import kotlin.concurrent.thread

class LargeTurboQnnModelLifecycleTest {
    private lateinit var root: File
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        root = Files.createTempDirectory("galaxyssi-qnn-large-turbo").toFile()
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
        root.deleteRecursively()
    }

    @Test
    fun `pinned S26U manifest matches official QNN context metadata`() {
        val manifest = LargeTurboQnnModelCatalog.s26Ultra

        assertEquals("0.59.0", manifest.releaseVersion)
        assertEquals("2.45.0.260326154327", manifest.qairtVersion)
        assertEquals(81, manifest.htpVersion)
        assertEquals(87, manifest.socModel)
        assertEquals(2_016_745_993L, manifest.archive.sizeBytes)
        assertEquals(2_206_501_062L, manifest.archive.installedSizeBytes)
        assertEquals(listOf("encoder.bin", "whisper_metadata.json", "decoder.bin"),
            manifest.archive.entries.map(QnnContextArchiveEntry::installedName))
        assertEquals(1_753_608_192L, manifest.archive.entries[0].uncompressedSizeBytes)
        assertEquals(452_882_432L, manifest.archive.entries[2].uncompressedSizeBytes)
        assertEquals(102_912L,
            manifest.supportAssets.single { it.installedName == "mel_filters.bin" }.installedSizeBytes)
        val store = LargeTurboQnnModelStore(root)
        val reserve = 512L * 1024L * 1024L
        assertEquals(
            manifest.archive.sizeBytes + manifest.totalInstalledSizeBytes + reserve,
            store.requiredFreeBytes(manifest)
        )
        assertEquals(
            manifest.totalInstalledSizeBytes + reserve,
            store.requiredInstallFreeBytes(manifest)
        )
    }

    @Test
    fun `deleting every model release leaves the store ready for a new download`() {
        val store = LargeTurboQnnModelStore(root)
        val previousDownload = File(store.downloadDirectory(), "partial-model").apply {
            writeText("partial", Charsets.UTF_8)
        }

        store.deleteAll()

        assertFalse(previousDownload.exists())
        assertTrue(store.downloadDirectory().isDirectory)
        assertEquals(
            QnnContextModelState.NOT_INSTALLED,
            store.inspectActive(LargeTurboQnnModelCatalog.s26Ultra).state
        )
    }

    @Test
    fun `download resumes an interrupted archive then verifies all SHA256 digests`() {
        val archiveBytes = ByteArray(768 * 1024) { index -> (index % 251).toByte() }
        val supportBytes = ByteArray(32 * 1024) { index -> (index % 199).toByte() }
        val cancelled = AtomicBoolean(false)
        val manifest = downloadManifest(archiveBytes, supportBytes)
        val downloadRoot = File(root, "downloads")
        val downloader = LargeTurboQnnModelDownloader(
            root = downloadRoot,
            networkGate = QnnModelDownloadNetworkGate { true },
            sourceUrlResolver = loopbackResolver(manifest),
            allowInsecureLoopbackForTests = true
        )
        server.enqueue(MockResponse()
            .setResponseCode(200)
            .setHeader("ETag", "\"archive-v1\"")
            .setBody(Buffer().write(archiveBytes)))

        assertThrows(QnnModelDownloadCancelledException::class.java) {
            downloader.download(
                manifest,
                QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK,
                QnnModelDownloadCancellation(cancelled::get)
            ) { progress ->
                if (progress.phase == QnnModelDownloadPhase.ARCHIVE && progress.downloadedBytes >= 128 * 1024L) {
                    cancelled.set(true)
                }
            }
        }
        val firstRequest = server.takeRequest()
        assertEquals(null, firstRequest.getHeader("Range"))
        val partial = downloadRoot.listFiles().orEmpty().single { it.name.endsWith(".partial") }
        val resumeOffset = partial.length()
        assertTrue(resumeOffset in 1 until archiveBytes.size.toLong())

        cancelled.set(false)
        server.enqueue(MockResponse()
            .setResponseCode(206)
            .setHeader("ETag", "\"archive-v1\"")
            .setHeader("Content-Range", "bytes $resumeOffset-${archiveBytes.lastIndex}/${archiveBytes.size}")
            .setBody(Buffer().write(archiveBytes, resumeOffset.toInt(), archiveBytes.size - resumeOffset.toInt())))
        server.enqueue(MockResponse().setResponseCode(200).setBody(Buffer().write(supportBytes)))

        val result = downloader.download(manifest, QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK)
        val resumeRequest = server.takeRequest()
        server.takeRequest()

        assertEquals("bytes=$resumeOffset-", resumeRequest.getHeader("Range"))
        assertEquals("\"archive-v1\"", resumeRequest.getHeader("If-Range"))
        assertTrue(result.resumed)
        assertEquals(sha256(archiveBytes), result.archiveSha256)
        assertArrayEquals(archiveBytes, result.archive.readBytes())
        assertArrayEquals(supportBytes, result.supportAssets.getValue("tokenizer.tiktoken").readBytes())
        assertFalse(downloadRoot.listFiles().orEmpty().any { it.name.endsWith(".partial") })
    }

    @Test
    fun `download rejects changed archive identity and blocked WiFi policy`() {
        val archiveBytes = ByteArray(2_048) { 7 }
        val supportBytes = ByteArray(128) { 3 }
        val manifest = downloadManifest(archiveBytes, supportBytes)
        val downloader = LargeTurboQnnModelDownloader(
            root = File(root, "downloads"),
            networkGate = QnnModelDownloadNetworkGate { policy ->
                policy != QnnModelDownloadNetworkPolicy.WIFI_ONLY
            },
            sourceUrlResolver = loopbackResolver(manifest),
            allowInsecureLoopbackForTests = true
        )

        assertThrows(QnnModelDownloadException::class.java) {
            downloader.download(manifest, QnnModelDownloadNetworkPolicy.WIFI_ONLY)
        }

        server.enqueue(MockResponse()
            .setResponseCode(200)
            .setHeader("ETag", "\"unexpected-v2\"")
            .setBody(Buffer().write(archiveBytes)))
        val error = assertThrows(QnnModelDownloadException::class.java) {
            downloader.download(manifest, QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK)
        }
        assertTrue(error.message.orEmpty().contains("changed"))
    }

    @Test
    fun `foreground pause cancels a blocked network read without losing resumable data`() {
        val archiveBytes = ByteArray(64 * 1024) { index -> (index % 251).toByte() }
        val supportBytes = ByteArray(128) { 3 }
        val manifest = downloadManifest(archiveBytes, supportBytes)
        val downloader = LargeTurboQnnModelDownloader(
            root = File(root, "cancel-downloads"),
            networkGate = QnnModelDownloadNetworkGate { true },
            sourceUrlResolver = loopbackResolver(manifest),
            allowInsecureLoopbackForTests = true
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("ETag", "\"archive-v1\"")
                .setBody(Buffer().write(archiveBytes))
                .throttleBody(1, 5, TimeUnit.SECONDS)
        )
        val failure = AtomicReference<Throwable?>()
        val worker = thread(name = "qnn-download-cancel-test") {
            failure.set(runCatching {
                downloader.download(manifest, QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK)
            }.exceptionOrNull())
        }

        assertTrue(server.takeRequest(2, TimeUnit.SECONDS) != null)
        Thread.sleep(150L)
        downloader.cancelActiveDownload()
        worker.join(2_000L)

        assertFalse(worker.isAlive)
        assertTrue(failure.get() != null)
        assertTrue(
            File(root, "cancel-downloads").listFiles().orEmpty()
                .any { it.name.endsWith(".partial") && it.length() > 0L }
        )
    }

    @Test
    fun `store validates archive metadata atomically activates and rolls back releases`() {
        val first = createInstallFixture("0.59.0", encoder = "encoder-one", decoder = "decoder-one")
        val second = createInstallFixture("0.60.0", encoder = "encoder-two", decoder = "decoder-two")
        val store = LargeTurboQnnModelStore(File(root, "files"), usableSpace = { Long.MAX_VALUE })

        val installedFirst = store.install(
            first.manifest,
            first.archive,
            sha256(first.archive),
            first.supportFiles
        )
        assertEquals(QnnContextModelState.INSTALLED, store.inspectActive(first.manifest).state)
        assertEquals("encoder-one", File(installedFirst.directory, "encoder.bin").readText())

        val installedSecond = store.install(
            second.manifest,
            second.archive,
            sha256(second.archive),
            second.supportFiles
        )
        assertEquals(QnnContextModelState.INSTALLED, store.inspectActive(second.manifest).state)
        assertEquals(installedFirst.directory.canonicalFile, installedSecond.replacedDirectory?.canonicalFile)
        assertEquals("encoder-two", File(installedSecond.directory, "encoder.bin").readText())

        val rolledBack = store.rollback(first.manifest)
        assertEquals(QnnContextModelState.INSTALLED, rolledBack.state)
        assertEquals(installedFirst.directory.canonicalFile, rolledBack.directory?.canonicalFile)
    }

    @Test
    fun `failed active release is quarantined and atomically rolls back to verified previous release`() {
        val first = createInstallFixture("0.59.0", encoder = "encoder-one", decoder = "decoder-one")
        val second = createInstallFixture("0.60.0", encoder = "encoder-two", decoder = "decoder-two")
        val store = LargeTurboQnnModelStore(File(root, "recovery-files"), usableSpace = { Long.MAX_VALUE })
        val installedFirst = store.install(first.manifest, first.archive, sha256(first.archive), first.supportFiles)
        val installedSecond = store.install(second.manifest, second.archive, sha256(second.archive), second.supportFiles)

        val recovery = store.quarantineActiveAndRollback(
            second.manifest,
            "qnn_model_corrupt",
            "decoder context failed verification"
        )

        assertTrue(recovery.rolledBack)
        assertEquals(installedSecond.directory.canonicalFile, recovery.quarantinedDirectory?.canonicalFile)
        assertTrue(File(installedSecond.directory, ".quarantined.json").isFile)
        assertEquals(installedFirst.directory.canonicalFile, recovery.active.directory?.canonicalFile)
        assertEquals(QnnContextModelState.INSTALLED, store.inspectActive(first.manifest).state)
        assertEquals(QnnContextModelState.INVALID, store.rollback(second.manifest).state)
    }

    @Test
    fun `store rejects a tampered archive digest receipt`() {
        val fixture = createInstallFixture("0.59.0")
        val store = LargeTurboQnnModelStore(File(root, "digest-files"), usableSpace = { Long.MAX_VALUE })
        val installed = store.install(
            fixture.manifest,
            fixture.archive,
            sha256(fixture.archive),
            fixture.supportFiles
        )

        File(installed.directory, "model.sha256").writeText("f".repeat(64), Charsets.US_ASCII)

        val snapshot = store.inspectActive(fixture.manifest)
        assertEquals(QnnContextModelState.INVALID, snapshot.state)
        assertTrue(snapshot.detail.contains("digest receipt"))
    }

    @Test
    fun `quarantined release without rollback remains invalid until replaced`() {
        val fixture = createInstallFixture("0.59.0")
        val store = LargeTurboQnnModelStore(File(root, "quarantine-files"), usableSpace = { Long.MAX_VALUE })
        store.install(fixture.manifest, fixture.archive, sha256(fixture.archive), fixture.supportFiles)

        val recovery = store.quarantineActiveAndRollback(
            fixture.manifest,
            "qnn_model_corrupt",
            "encoder context is invalid"
        )

        assertFalse(recovery.rolledBack)
        assertEquals(QnnContextModelState.INVALID, store.inspectActive(fixture.manifest).state)
        assertTrue(store.inspectActive(fixture.manifest).detail.contains("qnn_model_corrupt"))
    }

    @Test
    fun `store rejects unexpected archive entries and incompatible chipset metadata`() {
        val fixture = createInstallFixture("0.59.0", extraEntry = "unexpected.txt" to "bad".toByteArray())
        val store = LargeTurboQnnModelStore(File(root, "files"), usableSpace = { Long.MAX_VALUE })

        assertThrows(QnnContextModelInstallException::class.java) {
            store.install(fixture.manifest, fixture.archive, sha256(fixture.archive), fixture.supportFiles)
        }

        val wrongChipset = createInstallFixture("0.59.1", metadataChipset = "other-chipset")
        assertThrows(QnnContextModelInstallException::class.java) {
            store.install(
                wrongChipset.manifest,
                wrongChipset.archive,
                sha256(wrongChipset.archive),
                wrongChipset.supportFiles
            )
        }
    }

    private fun downloadManifest(archiveBytes: ByteArray, supportBytes: ByteArray): LargeTurboQnnModelManifest {
        val archiveUrl = LargeTurboQnnModelCatalog.s26Ultra.archive.sourceUrl
        val supportUrl = LargeTurboQnnModelCatalog.s26Ultra.supportAssets
            .single { it.installedName == "tokenizer.tiktoken" }
            .sourceUrl
        return LargeTurboQnnModelCatalog.s26Ultra.copy(
            releaseVersion = "9.9.9",
            archive = QnnContextArchive(
                sourceUrl = archiveUrl,
                sizeBytes = archiveBytes.size.toLong(),
                etag = "\"archive-v1\"",
                crc64NvmeBase64 = "test",
                sha256 = sha256(archiveBytes),
                entries = listOf(QnnContextArchiveEntry("model/encoder.bin", "encoder.bin", 1, 1, 1))
            ),
            supportAssets = listOf(QnnContextSupportAsset(
                installedName = "tokenizer.tiktoken",
                sourceUrl = supportUrl,
                downloadSizeBytes = supportBytes.size.toLong(),
                sha256 = sha256(supportBytes)
            ))
        )
    }

    private fun loopbackResolver(manifest: LargeTurboQnnModelManifest): (String) -> String = { sourceUrl ->
        when (sourceUrl) {
            manifest.archive.sourceUrl -> server.url("/model.zip").toString()
            manifest.supportAssets.single().sourceUrl -> server.url("/tokenizer.tiktoken").toString()
            else -> sourceUrl
        }
    }

    private fun createInstallFixture(
        version: String,
        encoder: String = "encoder",
        decoder: String = "decoder",
        metadataChipset: String = "qualcomm-snapdragon-8-elite-gen5-for-galaxy",
        extraEntry: Pair<String, ByteArray>? = null
    ): InstallFixture {
        val fixtureRoot = File(root, "fixture-${version}-${System.nanoTime()}").apply { mkdirs() }
        val archive = File(fixtureRoot, "model.zip")
        val metadata = metadata(metadataChipset).toByteArray()
        val payloads = linkedMapOf(
            "model/encoder.bin" to encoder.toByteArray(),
            "model/metadata.json" to metadata,
            "model/decoder.bin" to decoder.toByteArray()
        ).apply { extraEntry?.let { put(it.first, it.second) } }
        ZipOutputStream(archive.outputStream().buffered()).use { zip ->
            payloads.forEach { (name, bytes) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        val archiveEntries = ZipFile(archive).use { zip ->
            listOf("model/encoder.bin", "model/metadata.json", "model/decoder.bin").mapIndexed { index, name ->
                val value = zip.getEntry(name)
                QnnContextArchiveEntry(
                    archivePath = name,
                    installedName = listOf("encoder.bin", "whisper_metadata.json", "decoder.bin")[index],
                    compressedSizeBytes = value.compressedSize,
                    uncompressedSizeBytes = value.size,
                    crc32 = value.crc
                )
            }
        }
        val support = File(fixtureRoot, "tokenizer.source").apply { writeText("tokenizer-$version") }
        val manifest = LargeTurboQnnModelCatalog.s26Ultra.copy(
            releaseVersion = version,
            archive = QnnContextArchive(
                sourceUrl = "https://example.com/model.zip",
                sizeBytes = archive.length(),
                etag = "\"fixture\"",
                crc64NvmeBase64 = "fixture",
                sha256 = sha256(archive),
                entries = archiveEntries
            ),
            supportAssets = listOf(QnnContextSupportAsset(
                installedName = "tokenizer.tiktoken",
                sourceUrl = "https://example.com/tokenizer.tiktoken",
                downloadSizeBytes = support.length(),
                sha256 = sha256(support)
            ))
        )
        return InstallFixture(manifest, archive, mapOf("tokenizer.tiktoken" to support))
    }

    private fun metadata(chipset: String): String {
        val shape = JSONArray(listOf(1, 128, 3_000))
        val logits = JSONArray(listOf(1, 51_866, 1, 1))
        return JSONObject()
            .put("model_id", "whisper_large_v3_turbo")
            .put("runtime", "qnn_context_binary")
            .put("precision", "float")
            .put("tool_versions", JSONObject().put("qairt", "2.45.0.260326154327"))
            .put("model_files", JSONObject()
                .put("encoder.bin", JSONObject().put("inputs", JSONObject()
                    .put("input_features", JSONObject().put("shape", shape))))
                .put("decoder.bin", JSONObject().put("outputs", JSONObject()
                    .put("logits", JSONObject().put("shape", logits)))))
            .put("chipset_attributes", JSONObject()
                .put("aliases", JSONArray(listOf(chipset)))
                .put("htp_version", 81)
                .put("soc_model", 87))
            .toString()
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun sha256(file: File): String = sha256(file.readBytes())

    private data class InstallFixture(
        val manifest: LargeTurboQnnModelManifest,
        val archive: File,
        val supportFiles: Map<String, File>
    )
}
