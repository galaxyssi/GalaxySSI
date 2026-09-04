package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.security.MessageDigest

class LocalModelStorageTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var storage: LocalModelStorage
    private val trustedBytes = "trusted-model".toByteArray()
    private val profile by lazy {
        LocalModelRuntimeProfile(
            id = "test-model",
            displayName = "Test model",
            expectedModelFileBytes = trustedBytes.size.toLong(),
            layerCount = 1,
            keyValueHeadCount = 1,
            headDimension = 1,
            defaultContextTokens = 512,
            maximumContextTokens = 512,
            quantizationLabel = "test",
            repositoryId = "galaxyssi/test-model",
            fileName = "test-model.gguf",
            sha256 = sha256(trustedBytes)
        )
    }

    @Before
    fun setUp() {
        storage = LocalModelStorage(temporaryFolder.newFolder("local-llm"))
    }

    @Test
    fun onlyVerifiedPartialCanBeCommittedAndLoaded() {
        storage.partialFile(profile).apply {
            parentFile?.mkdirs()
            writeBytes(trustedBytes)
        }

        assertTrue(storage.verifyPartial(profile))
        val installed = storage.commitVerifiedPartial(profile, "https://huggingface.co/galaxyssi/test-model")

        assertEquals(installed, storage.verifyForNativeLoad(profile))
        assertTrue(storage.inspect(profile).installed)
        assertFalse(storage.partialFile(profile).exists())
    }

    @Test
    fun changedInstalledFileInvalidatesVerificationCache() {
        storage.partialFile(profile).apply {
            parentFile?.mkdirs()
            writeBytes(trustedBytes)
        }
        storage.commitVerifiedPartial(profile, "https://huggingface.co/galaxyssi/test-model")
        val installed = storage.verifyForNativeLoad(profile)
        val previousModified = installed.lastModified()

        installed.writeBytes("tampered-data".toByteArray())
        assertTrue(installed.setLastModified(previousModified + 2_000L))

        assertThrows(IllegalStateException::class.java) {
            storage.verifyForNativeLoad(profile)
        }
    }

    @Test
    fun invalidPartialCannotBeCommitted() {
        storage.partialFile(profile).apply {
            parentFile?.mkdirs()
            writeBytes("tampered-data".toByteArray())
        }

        assertFalse(storage.verifyPartial(profile))
        assertThrows(IllegalArgumentException::class.java) {
            storage.commitVerifiedPartial(profile, "https://huggingface.co/galaxyssi/test-model")
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }
}
