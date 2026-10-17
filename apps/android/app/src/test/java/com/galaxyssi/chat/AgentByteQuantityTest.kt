package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentByteQuantityTest {
    @Test fun smallQuantitiesDoNotDisappearAsZeroMegabytes() {
        assertEquals("0 B", formatAgentBytes(0))
        assertEquals("512 B", formatAgentBytes(512))
        assertEquals("1.0 KiB", formatAgentBytes(1024))
        assertEquals("1.5 KiB", formatAgentBytes(1536))
    }

    @Test fun binaryDivisorsAlwaysCarryBinaryUnits() {
        assertEquals("1.0 MiB", formatAgentBytes(1024 * 1024))
        assertEquals("1.0 GiB", formatAgentBytes(1024 * 1024 * 1024))
        assertEquals("953.7 MiB", formatAgentBytes(1_000_000_000))
    }

    @Test fun observedStorageBytesAreNotMislabeledAsDecimalGigabytes() {
        assertEquals("172.9 GiB", formatAgentBytes(185_634_684_928))
    }
}
