package com.galaxyssi.chat

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class AgentArtifactEvidenceDeviceFixtureTest {
    @Test fun nativeFileReceiptsRequireFreshExportsAndPreserveOwnership() {
        val parent = Files.createTempDirectory("artifact-fixture-test-")
        try {
            val report = AgentArtifactEvidenceDeviceFixture.run(parent)
            assertTrue(report.toString(), report.getBoolean("passed"))
            assertEquals(6, report.getJSONArray("cases").length())
            assertEquals(0, report.getInt("model_calls"))
            Files.list(parent).use { assertEquals(0, it.count()) }
        } finally { Files.deleteIfExists(parent) }
    }
}
