package com.galaxyssi.chat.voice.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class WhisperModelStorageTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun verifiedFileIsAtomicallyInstalledWithMetadata() {
        val source = temporaryFolder.newFile("source.bin").apply { writeBytes("verified-model".toByteArray()) }
        val profile = profileFor(source)
        val storage = storage()

        val metadata = storage.install(source, profile, "test", Long.MAX_VALUE)
        val snapshot = storage.inspect(profile)

        assertTrue(snapshot.installed)
        assertEquals(WhisperModelStorageState.INSTALLED_UNCERTIFIED, snapshot.state)
        assertEquals(profile.sha256, metadata.sha256)
        assertEquals(source.readBytes().toList(), storage.finalFile(profile).readBytes().toList())
        assertFalse(storage.stagingFile(profile).exists())
        assertTrue(storage.verifyForNativeLoad(profile).valid)
    }

    @Test
    fun truncatedAndCorruptFilesNeverReplaceVerifiedInstall() {
        val valid = temporaryFolder.newFile("valid.bin").apply { writeBytes("trusted-model".toByteArray()) }
        val profile = profileFor(valid)
        val storage = storage()
        storage.install(valid, profile, "valid", Long.MAX_VALUE)

        val truncated = temporaryFolder.newFile("truncated.bin").apply { writeBytes("bad".toByteArray()) }
        val sizeError = assertThrows(WhisperModelInstallException::class.java) {
            storage.install(truncated, profile, "truncated", Long.MAX_VALUE)
        }
        assertEquals(WhisperModelInstallFailure.SIZE_MISMATCH, sizeError.failure)
        assertTrue(storage.verifyForNativeLoad(profile).valid)

        val corrupt = temporaryFolder.newFile("corrupt.bin").apply { writeBytes("x".repeat(valid.length().toInt()).toByteArray()) }
        val hashError = assertThrows(WhisperModelInstallException::class.java) {
            storage.install(corrupt, profile, "corrupt", Long.MAX_VALUE)
        }
        assertEquals(WhisperModelInstallFailure.SHA256_MISMATCH, hashError.failure)
        assertTrue(storage.verifyForNativeLoad(profile).valid)
    }

    @Test
    fun cancellationBeforeCommitPreservesVerifiedInstall() {
        val original = temporaryFolder.newFile("original.bin").apply { writeBytes("trusted-model".toByteArray()) }
        val replacement = temporaryFolder.newFile("replacement.bin").apply { writeBytes(original.readBytes()) }
        val profile = profileFor(original)
        val storage = storage()
        storage.install(original, profile, "original", Long.MAX_VALUE)

        assertThrows(InterruptedException::class.java) {
            storage.install(
                replacement,
                profile,
                "replacement",
                Long.MAX_VALUE,
                beforeCommit = { throw InterruptedException("cancelled") }
            )
        }

        assertTrue(storage.verifyForNativeLoad(profile).valid)
        assertEquals("original", storage.inspect(profile).metadata?.source)
        assertFalse(storage.stagingFile(profile).exists())
    }

    @Test
    fun tamperingAfterInstallBlocksNativeLoad() {
        val source = temporaryFolder.newFile("model.bin").apply { writeBytes("original-data".toByteArray()) }
        val profile = profileFor(source)
        val storage = storage()
        storage.install(source, profile, "test", Long.MAX_VALUE)
        val installed = storage.finalFile(profile)
        val priorModified = installed.lastModified()
        installed.writeBytes("modified-data".toByteArray())
        installed.setLastModified(priorModified + 2_000L)

        assertFalse(storage.inspect(profile).installed)
        assertFalse(storage.verifyForNativeLoad(profile).valid)
    }

    @Test
    fun insufficientSpaceAndStalePartialAreHandled() {
        var now = 20_000L
        val source = temporaryFolder.newFile("space.bin").apply { writeBytes("12345678".toByteArray()) }
        val profile = profileFor(source, reserve = 20L)
        val storage = WhisperModelStorage(temporaryFolder.newFolder("models"), "test", clock = { now })
        val error = assertThrows(WhisperModelInstallException::class.java) {
            storage.install(source, profile, "test", availableBytes = 27L)
        }
        assertEquals(WhisperModelInstallFailure.INSUFFICIENT_SPACE, error.failure)

        val partial = storage.stagingFile(profile).apply {
            parentFile?.mkdirs()
            writeText("partial")
            setLastModified(1_000L)
        }
        now = 30_000L
        assertEquals(1, storage.cleanupStalePartials(maxAgeMillis = 10_000L))
        assertFalse(partial.exists())
    }

    @Test
    fun installUsesTheConfiguredCapacityProvider() {
        val source = temporaryFolder.newFile("capacity.bin").apply { writeBytes("12345678".toByteArray()) }
        val profile = profileFor(source, reserve = 20L)
        val storage = WhisperModelStorage(
            temporaryFolder.newFolder("capacity-models"),
            "test",
            capacityProvider = { 27L }
        )

        val error = assertThrows(WhisperModelInstallException::class.java) {
            storage.install(source, profile, "test")
        }

        assertEquals(WhisperModelInstallFailure.INSUFFICIENT_SPACE, error.failure)
    }

    @Test
    fun legacyMigrationSkipsCorruptCandidateAndMigratesVerifiedFile() {
        val valid = temporaryFolder.newFile("legacy-valid.bin").apply { writeBytes("legacy-model".toByteArray()) }
        val corrupt = temporaryFolder.newFile("legacy-corrupt.bin").apply { writeBytes("x".repeat(valid.length().toInt()).toByteArray()) }
        val profile = profileFor(valid)
        val storage = storage()

        val result = WhisperLegacyMigration.migrate(profile, listOf(corrupt, valid), storage)

        assertEquals(WhisperLegacyMigrationState.MIGRATED, result.state)
        assertEquals(valid.canonicalFile, result.source?.canonicalFile)
        assertTrue(storage.verifyForNativeLoad(profile).valid)
    }

    @Test
    fun unsupportedCertificationKeepsVerifiedModelInstalledWithoutMakingItRealtime() {
        val source = temporaryFolder.newFile("unsupported.bin").apply { writeBytes("verified-model".toByteArray()) }
        val profile = profileFor(source)
        val storage = storage()
        storage.install(source, profile, "test", Long.MAX_VALUE)

        storage.updateCertification(profile, WhisperCertificationLevel.UNSUPPORTED)
        val snapshot = storage.inspect(profile)

        assertTrue(snapshot.installed)
        assertEquals(WhisperModelStorageState.UNSUPPORTED, snapshot.state)
        assertEquals(WhisperCertificationLevel.UNSUPPORTED, snapshot.metadata?.certification)
        assertTrue(storage.verifyForNativeLoad(profile).valid)
    }

    @Test
    fun remoteRecommendationKeepsVerifiedModelInstalledWithoutMakingItRealtime() {
        val source = temporaryFolder.newFile("remote.bin").apply { writeBytes("verified-model".toByteArray()) }
        val profile = profileFor(source)
        val storage = storage()
        storage.install(source, profile, "test", Long.MAX_VALUE)

        storage.updateCertification(profile, WhisperCertificationLevel.REMOTE_RECOMMENDED)
        val snapshot = storage.inspect(profile)

        assertTrue(snapshot.installed)
        assertEquals(WhisperModelStorageState.UNSUPPORTED, snapshot.state)
        assertEquals(WhisperCertificationLevel.REMOTE_RECOMMENDED, snapshot.metadata?.certification)
        assertTrue(storage.verifyForNativeLoad(profile).valid)
    }

    private fun storage(): WhisperModelStorage =
        WhisperModelStorage(temporaryFolder.newFolder("storage-${System.nanoTime()}"), "test")

    private fun profileFor(file: File, reserve: Long = 0L): WhisperModelProfile = WhisperModelProfile(
        id = "test_model",
        family = WhisperModelFamily.TINY,
        displayName = "Test model",
        fileName = "ggml-test.bin",
        sourceUrls = listOf("https://example.com/ggml-test.bin"),
        expectedSizeBytes = file.length(),
        sha256 = WhisperModelVerifier.sha256(file),
        quantization = WhisperQuantization.F16,
        multilingual = true,
        recommendedMode = WhisperExecutionMode.FINAL_ONLY,
        minAvailableRamBytes = 0L,
        minFreeStorageBytes = reserve,
        defaultPartialIntervalMs = 1_000L,
        maxWindowMs = 8_000L,
        enabledByDefault = false,
        experimental = false,
        manifestVersion = WhisperModelCatalog.SCHEMA_VERSION
    )
}
