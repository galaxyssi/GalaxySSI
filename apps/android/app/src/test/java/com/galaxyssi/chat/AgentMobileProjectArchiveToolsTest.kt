package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentMobileProjectArchiveToolsTest {
    @Test
    fun projectArchiveUsesConstantMemoryStreamingExtraction() {
        val script = AgentMobileProjectArchiveTools.PROJECT_IMPORT_SCRIPT

        assertTrue(script.contains("tarfile.open(archive, 'r|gz')"))
        assertFalse(script.contains("getmembers()"))
        assertTrue(script.contains("entries > 200000"))
        assertTrue(script.contains("Imported archive is not a Git repository"))
    }

    @Test
    fun gradleCacheUsesConstantMemoryStreamingExtraction() {
        val script = AgentMobileProjectArchiveTools.GRADLE_CACHE_IMPORT_SCRIPT

        assertTrue(script.contains("tarfile.open(archive, 'r|gz')"))
        assertFalse(script.contains("getmembers()"))
        assertTrue(script.contains("entries > 300000"))
        assertTrue(script.contains("Gradle cache expands beyond 8 GiB"))
    }
}
