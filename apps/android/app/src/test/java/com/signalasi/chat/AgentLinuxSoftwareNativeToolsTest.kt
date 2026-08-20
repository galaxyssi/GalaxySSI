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

    @Test
    fun ranksAnExactPackageAheadOfSubstringMatches() {
        val ranked = AgentLinuxSoftwareNativeTools.rankPackageRecords(
            listOf(
                AgentLinuxSoftwareRecord("libjs-jquery", "1", false, "jQuery"),
                AgentLinuxSoftwareRecord("gojq", "2", false, "Go jq"),
                AgentLinuxSoftwareRecord("jq", "3", false, "JSON processor")
            ),
            query = "jq",
            limit = 2
        )

        assertEquals(listOf("jq", "gojq"), ranked.map(AgentLinuxSoftwareRecord::id))
    }
}
