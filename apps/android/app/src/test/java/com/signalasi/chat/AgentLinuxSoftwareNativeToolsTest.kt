package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentLinuxSoftwareNativeToolsTest {
    @Test
    fun parsesBoundedLinuxPackageSearchRecords() {
        val records = AgentLinuxSoftwareNativeTools.parsePackageRecords(
            "git\t2.47.0\tinstalled\tfast version control\n" +
                "curl\t8.10.1\tno\tcommand line URL transfer\n" +
                "bad package\t1\tno\trejected\n" +
                "git\tolder\tno\tduplicate\n"
        )

        assertEquals(listOf("git", "curl"), records.map(AgentLinuxSoftwareRecord::id))
        assertTrue(records.first().installed)
        assertEquals("8.10.1", records.last().version)
    }

    @Test
    fun exposesEverySoftwareOperationToThePhoneAgentPlanner() {
        AgentLinuxSoftwareNativeTools.toolIds.forEach { toolId ->
            assertTrue(toolId in AgentPhoneNativeToolCatalog.defaultToolIds)
            assertTrue(AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(toolId))
        }
    }

    @Test
    fun allowsAColdPackageIndexRefreshToFinish() {
        assertEquals(10 * 60_000L, AgentLinuxSoftwareNativeTools.PACKAGE_SEARCH_TIMEOUT_MILLIS)
    }
}
