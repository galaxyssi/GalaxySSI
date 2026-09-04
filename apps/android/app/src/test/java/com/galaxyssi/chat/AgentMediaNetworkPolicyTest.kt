package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentMediaNetworkPolicyTest {
    @Test
    fun unmeteredValidatedNetworkKeepsNormalQuality() {
        val profile = AgentMediaNetworkPolicy.evaluate(probe())

        assertEquals(AgentMediaNetworkState.NORMAL, profile.state)
        assertEquals(100_000, profile.imageTargetBytes)
        assertEquals(44_100, profile.audioSampleRateHz)
        assertFalse(profile.deferMediaUpload)
    }

    @Test
    fun meteredNetworkUsesCompactMedia() {
        val profile = AgentMediaNetworkPolicy.evaluate(probe(metered = true))

        assertEquals(AgentMediaNetworkState.CONSTRAINED, profile.state)
        assertEquals(64 * 1024, profile.imageTargetBytes)
        assertEquals(16_000, profile.audioSampleRateHz)
        assertEquals(32_000, profile.audioBitRateBps)
    }

    @Test
    fun cellularNetworkIsConstrainedEvenWhenCarrierMarksItUnmetered() {
        val profile = AgentMediaNetworkPolicy.evaluate(probe(cellular = true))

        assertEquals(AgentMediaNetworkState.CONSTRAINED, profile.state)
    }

    @Test
    fun lowKnownUplinkUsesCompactMedia() {
        val profile = AgentMediaNetworkPolicy.evaluate(probe(upstreamKbps = 128))

        assertEquals(AgentMediaNetworkState.CONSTRAINED, profile.state)
    }

    @Test
    fun unknownBandwidthDoesNotInventAWeakNetwork() {
        val profile = AgentMediaNetworkPolicy.evaluate(
            probe(downstreamKbps = 0, upstreamKbps = 0)
        )

        assertEquals(AgentMediaNetworkState.NORMAL, profile.state)
    }

    @Test
    fun unvalidatedNetworkDefersMediaUntilRecovery() {
        val profile = AgentMediaNetworkPolicy.evaluate(probe(validated = false))

        assertEquals(AgentMediaNetworkState.OFFLINE, profile.state)
        assertEquals(48 * 1024, profile.imageTargetBytes)
        assertTrue(profile.deferMediaUpload)
        assertFalse(profile.canUploadDeferredMedia)
    }

    private fun probe(
        networkPresent: Boolean = true,
        internetCapable: Boolean = true,
        validated: Boolean = true,
        metered: Boolean = false,
        roaming: Boolean = false,
        restricted: Boolean = false,
        congested: Boolean = false,
        cellular: Boolean = false,
        downstreamKbps: Int = 20_000,
        upstreamKbps: Int = 5_000
    ) = AgentMediaNetworkProbe(
        networkPresent = networkPresent,
        internetCapable = internetCapable,
        validated = validated,
        metered = metered,
        roaming = roaming,
        restricted = restricted,
        congested = congested,
        cellular = cellular,
        downstreamKbps = downstreamKbps,
        upstreamKbps = upstreamKbps
    )
}
