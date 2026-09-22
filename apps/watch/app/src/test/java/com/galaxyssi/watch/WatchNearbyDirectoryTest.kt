package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchNearbyDirectoryTest {
    @Test fun reopeningReplacesAddressWithoutAddingRows() {
        val directory = WatchNearbyDirectory<String>()
        repeat(10) { index -> directory.update("stable-watch", "address-$index", "Galaxy Watch6 · JQKL", "device-$index", index * 100L) }
        assertEquals(1, directory.values().size)
        assertEquals("device-9", directory.values().single().device)
        directory.update("other-watch", "another-address", "Galaxy Watch6 · JQKL", "other-device", 1000)
        assertEquals("Different stable identities must not merge just because names match", 2, directory.values().size)
        directory.prune(21_001)
        assertTrue(directory.values().isEmpty())
    }
    @Test fun scanResponseUpgradesProvisionalRowAndLegacySuffixIsStable() {
        val directory = WatchNearbyDirectory<String>()
        directory.update(null, "A", "Galaxy Watch6 (JQKL)", "old", 0)
        directory.update(null, "B", "Galaxy Watch6 (JQKL)", "new", 1)
        assertEquals(1, directory.values().size)
        directory.update("id", "B", "Galaxy Watch6 · JQKL", "latest", 2)
        assertEquals(1, directory.values().size)
        assertEquals("latest", directory.values().single().device)
        directory.update(null, "B", "", "latest-advertisement", 3)
        assertEquals("id:id", directory.values().single().key)
        assertEquals("Galaxy Watch6 · JQKL", directory.values().single().name)
    }
    @Test fun compactIdentityFitsLegacyAdvertisementAndSurvivesRename() {
        val first = WatchNearbyIdentity.encode("galaxyssi:1234", "Galaxy Watch5 Pro · EV1W")
        assertTrue(18 + first.size <= 31)
        assertEquals("Galaxy Watch5 Pro · EV1W", WatchNearbyIdentity.decode(first)?.second)
        assertEquals(WatchNearbyIdentity.decode(first)?.first,
            WatchNearbyIdentity.decode(WatchNearbyIdentity.encode("galaxyssi:1234", "Changed name · ABCD"))?.first)
        assertNull(WatchNearbyIdentity.decode(byteArrayOf(1, 2)))
    }
}
