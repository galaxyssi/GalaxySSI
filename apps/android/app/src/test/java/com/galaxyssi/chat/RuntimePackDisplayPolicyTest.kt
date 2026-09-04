package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimePackDisplayPolicyTest {
    @Test
    fun installedVersionIsShownWithoutDuplicateVersionPrefix() {
        assertEquals(
            "Linux 1.2.1",
            RuntimePackDisplayPolicy.installedTitle("Linux", "v1.2.1")
        )
    }

    @Test
    fun missingInstalledVersionLeavesTitleUnchanged() {
        assertEquals(
            "Linux",
            RuntimePackDisplayPolicy.installedTitle("Linux", null)
        )
    }
}
