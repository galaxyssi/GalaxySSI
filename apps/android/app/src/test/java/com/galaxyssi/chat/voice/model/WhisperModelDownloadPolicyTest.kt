package com.galaxyssi.chat.voice.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class WhisperModelDownloadPolicyTest {
    @Test
    fun allModelsCanDownloadOnMeteredNetworksWithoutConfirmation() {
        val free = Long.MAX_VALUE
        assertEquals(
            WhisperDownloadDecision.ALLOW,
            WhisperModelDownloadPolicy.evaluate(
                WhisperModelCatalog.require("large_v3_turbo_q5_0"),
                WhisperNetworkClass.METERED,
                free
            ).decision
        )
        assertEquals(
            WhisperDownloadDecision.ALLOW,
            WhisperModelDownloadPolicy.evaluate(
                WhisperModelCatalog.require("large_v3_turbo_q5_0"),
                WhisperNetworkClass.METERED,
                free,
                meteredConfirmed = true
            ).decision
        )
        assertEquals(
            WhisperDownloadDecision.ALLOW,
            WhisperModelDownloadPolicy.evaluate(
                WhisperModelCatalog.require("tiny_q5_1"),
                WhisperNetworkClass.METERED,
                free
            ).decision
        )
    }

    @Test
    fun offlineAndInsufficientSpaceAreRejectedBeforeDownload() {
        val profile = WhisperModelCatalog.require("medium_q5_0")
        assertEquals(
            WhisperDownloadDecision.WAIT_FOR_NETWORK,
            WhisperModelDownloadPolicy.evaluate(profile, WhisperNetworkClass.OFFLINE, Long.MAX_VALUE).decision
        )
        val result = WhisperModelDownloadPolicy.evaluate(profile, WhisperNetworkClass.WIFI, 1L)
        assertEquals(WhisperDownloadDecision.INSUFFICIENT_SPACE, result.decision)
        assertTrue(result.requiredFreeBytes > profile.expectedSizeBytes)
    }

    @Test
    fun sourcePriorityFollowsInterfaceLanguageWithoutChangingTrustList() {
        val profile = WhisperModelCatalog.require("base")
        assertTrue(WhisperModelDownloadPolicy.orderedSources(profile, Locale.SIMPLIFIED_CHINESE).first().contains("hf-mirror.com"))
        assertTrue(WhisperModelDownloadPolicy.orderedSources(profile, Locale.ENGLISH).first().contains("huggingface.co"))
        assertEquals(profile.sourceUrls.toSet(), WhisperModelDownloadPolicy.orderedSources(profile, Locale.ENGLISH).toSet())
    }
}
