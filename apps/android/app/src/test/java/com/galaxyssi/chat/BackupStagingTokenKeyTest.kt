package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class BackupStagingTokenKeyTest {
    @Test fun tokensAreStableWithinOneStageButUnlinkableAcrossStages() {
        BackupStagingTokenKey().use { first -> BackupStagingTokenKey().use { second ->
            val expected = first.token("identity", "private fixture")
            repeat(100) { assertEquals(expected, first.token("identity", "private fixture")) }
            assertNotEquals(expected, second.token("identity", "private fixture"))
            assertNotEquals(expected, first.token("fingerprint", "private fixture"))
            assertFalse(expected.contains("private fixture"))
            assertEquals(43, expected.length)
        } }
    }

    @Test fun domainFramingIsUnambiguousAndClosedKeysCannotBeUsed() {
        val key = BackupStagingTokenKey()
        assertNotEquals(key.token("a:b", "c"), key.token("a", "b:c"))
        key.close()
        assertNotNull(runCatching { key.token("a", "b") }.exceptionOrNull())
    }
}
