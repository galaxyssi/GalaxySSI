package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class WatchDiscoveryCatalogTest {
    private fun key(name: String, network: String = "wifi") = WatchDiscoveryCatalog.Key(name, "_galaxyssi-watch._tcp", network)
    @Test fun multipleWatchesRemainSeparate() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("Watch5 Pro EV1W"), "watch5")
        catalog.put(key("Watch6 JQKL"), "watch6")
        assertEquals(listOf("watch5", "watch6"), catalog.values)
    }
    @Test fun rediscoveryUpdatesOnlyMatchingRow() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("A"), "a1"); catalog.put(key("B"), "b")
        catalog.put(key("A"), "a2")
        assertEquals(listOf("a2", "b"), catalog.values)
    }
    @Test fun identicalLabelsOnDifferentNetworksDoNotOverwriteEachOther() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("Watch", "network1"), "one")
        catalog.put(key("Watch", "network2"), "two")
        assertEquals(2, catalog.values.size)
    }
    @Test fun selectingOneWatchRejectsConcurrentSelectionOfAnother() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("A"), "a"); catalog.put(key("B"), "b")
        assertTrue(catalog.select(key("B")))
        assertFalse(catalog.select(key("A")))
        assertEquals(key("B"), catalog.selected)
        catalog.remove(key("A"))
        assertEquals(key("B"), catalog.selected)
    }
    @Test fun losingSelectedWatchInvalidatesPendingResolution() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("A"), "a"); catalog.put(key("B"), "b")
        catalog.select(key("A"))
        assertTrue(catalog.remove(key("A")))
        assertNull(catalog.selected)
        assertEquals(listOf("b"), catalog.values)
        assertFalse(catalog.select(key("A")))
        assertTrue(catalog.select(key("B")))
    }
    @Test fun refreshClearsRowsAndOldSelection() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("A"), "a"); catalog.select(key("A"))
        catalog.clear()
        assertTrue(catalog.isEmpty()); assertNull(catalog.selected)
    }
    @Test fun rediscoveringSameWatchCannotReusePreviousResolveCallback() {
        val catalog = WatchDiscoveryCatalog<String>()
        catalog.put(key("A"), "a"); catalog.select(key("A"))
        val oldRevision = catalog.selectionRevision
        catalog.remove(key("A")); catalog.put(key("A"), "new-a"); catalog.select(key("A"))
        assertEquals(key("A"), catalog.selected)
        assertNotEquals(oldRevision, catalog.selectionRevision)
    }
}
