package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CompactWhisperQnnModelCatalogTest {
    @Test
    fun `catalog pins all four official S26U context packages`() {
        val models = CompactWhisperQnnModelCatalog.all

        assertEquals(
            listOf(
                "whisper-tiny-qnn-float-s26u",
                "whisper-base-qnn-float-s26u",
                "whisper-small-qnn-w8a16-s26u",
                "whisper-small-qnn-float-s26u"
            ),
            models.map { it.manifest.modelId }
        )
        assertEquals(
            listOf(105_910_421L, 180_939_859L, 293_970_633L, 573_246_593L),
            models.map { it.manifest.archive.sizeBytes }
        )
        assertEquals(
            listOf(
                "\"62df896b12ecb49b396af68abf16a117-13\"",
                "\"9856a8f66b1736a1c944ee1001311bf6-22\"",
                "\"e9be3436637e984605a933fe5440bfcd-36\"",
                "\"94ccf87c7364b75d1c4dff79d39bc992-69\""
            ),
            models.map { it.manifest.archive.etag }
        )
        assertEquals(
            listOf("6qtLRg6Gik4=", "ugHDISaoqEk=", "Nl/GQsJZD8A=", "MNmR/qCbHpE="),
            models.map { it.manifest.archive.crc64NvmeBase64 }
        )
        models.forEach { compact ->
            assertEquals("0.59.0", compact.manifest.releaseVersion)
            assertEquals("2.45.0.260326154327", compact.manifest.qairtVersion)
            assertEquals(81, compact.manifest.htpVersion)
            assertEquals(87, compact.manifest.socModel)
            assertEquals(80, compact.manifest.melBins)
            assertEquals(51_865, compact.manifest.vocabularySize)
            assertTrue(compact.manifest.archive.sourceUrl.startsWith(
                "https://qaihub-public-assets.s3.us-west-2.amazonaws.com/"
            ))
            assertTrue(compact.manifest.archive.sourceUrl.endsWith(
                "qualcomm_snapdragon_8_elite_gen5_for_galaxy.zip"
            ))
            assertEquals(
                "qualcomm-snapdragon-8-elite-gen5-for-galaxy",
                compact.manifest.targetChipset
            )
            compact.manifest.archive.entries.forEach { entry ->
                assertTrue(entry.archivePath.contains(
                    "qualcomm_snapdragon_8_elite_gen5_for_galaxy/"
                ))
            }
            assertFalse(compact.manifest.archive.sourceUrl.contains("whisper_large_v3_turbo"))
        }
    }

    @Test
    fun `small quantized and float packages remain distinct selectable installs`() {
        val quantized = CompactWhisperQnnModelCatalog.smallW8A16
        val floatingPoint = CompactWhisperQnnModelCatalog.smallFloat

        assertEquals("small", quantized.profileId)
        assertEquals("small", floatingPoint.profileId)
        assertEquals("w8a16", quantized.manifest.precision)
        assertEquals("float", floatingPoint.manifest.precision)
        assertFalse(quantized.modelRootName == floatingPoint.modelRootName)
        assertFalse(quantized.manifest.modelId == floatingPoint.manifest.modelId)
    }

    @Test
    fun `large turbo catalog and wrappers remain byte pinned and outside compact catalog`() {
        val large = LargeTurboQnnModelCatalog.s26Ultra

        assertEquals("whisper-large-v3-turbo-qnn-s26u", large.modelId)
        assertEquals(2_016_745_993L, large.archive.sizeBytes)
        assertEquals("\"8a89a6ab484fc0d2659e344baadd74f6-241\"", large.archive.etag)
        assertEquals("rOuHIZmpck4=", large.archive.crc64NvmeBase64)
        assertEquals(128, large.melBins)
        assertEquals(4, large.decoderLayers)
        assertEquals(20, large.decoderHeads)
        assertEquals(51_866, large.vocabularySize)
        assertEquals(866L, WhisperQnnContextAssets.encoder.sizeBytes)
        assertEquals(
            "77ca1586db42df9cbd116cfd9002bda12627f0804c81d8c92eddeb5027a3bf42",
            WhisperQnnContextAssets.encoder.sha256
        )
        assertEquals(2_051L, WhisperQnnContextAssets.decoder.sizeBytes)
        assertEquals(
            "0b9992323e509572783a4f014d88ac0d19629dde724c3b4c894591d44c167445",
            WhisperQnnContextAssets.decoder.sha256
        )
        assertFalse(CompactWhisperQnnModelCatalog.all.any { it.manifest.modelId == large.modelId })
    }
}
