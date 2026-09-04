package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.security.MessageDigest

class WhisperQnnContextAssetInstallerTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun verifiedWrappersAreInstalledAndCorruptionIsAtomicallyRepaired() {
        val encoder = "encoder-wrapper".toByteArray()
        val decoder = "decoder-wrapper".toByteArray()
        val assets = listOf(asset("source/encoder", "encoder_context.onnx", encoder),
            asset("source/decoder", "decoder_context.onnx", decoder))
        val bytes = mapOf("source/encoder" to encoder, "source/decoder" to decoder)
        val installer = WhisperQnnContextAssetInstaller(
            source = QnnContextAssetSource { ByteArrayInputStream(bytes.getValue(it)) },
            assets = assets
        )
        val model = temporaryFolder.newFolder("model")

        val first = installer.ensureInstalled(model)
        assertArrayEquals(encoder, first.getValue("encoder_context.onnx").readBytes())
        first.getValue("encoder_context.onnx").writeText("corrupt")

        val repaired = installer.ensureInstalled(model)
        assertArrayEquals(encoder, repaired.getValue("encoder_context.onnx").readBytes())
        assertArrayEquals(decoder, repaired.getValue("decoder_context.onnx").readBytes())
        assertEquals(2, repaired.size)
    }

    private fun asset(path: String, name: String, bytes: ByteArray) = QnnContextWrapperAsset(
        assetPath = path,
        installedName = name,
        sizeBytes = bytes.size.toLong(),
        sha256 = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    )
}
