package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBusinessIntentTest {
    @Test fun businessRecordKeysDoNotRequestCodeExecution() {
        listOf(
            "Read this sales record, calculate the total. Do not execute real operations. " +
                "{\"code\":\"BIZ-001\",\"values\":[15,34,20]}",
            "\u8bfb\u53d6\u4e1a\u52a1\u8bb0\u5f55\u5e76\u8ba1\u7b97\u5408\u8ba1\uff0c\u4e0d\u8981\u6267\u884c\u771f\u5b9e\u4e1a\u52a1\u64cd\u4f5c\u3002" +
                "{\"code\" : \"BIZ-001\", \"program\":\"LOYALTY-2\",\"values\":[15,34,20]}",
            "Compare barcode ABC with postcode XYZ; do not execute anything.",
            "Read {'code': 'SALE-3'} and return the identifier."
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
            assertFalse(goal, AgentCapability.CODE in requirements.capabilities)
            assertFalse(goal, AgentCapability.TASK_EXECUTION in requirements.capabilities)
            assertNotEquals(goal, AgentTaskIntent.CODE, AgentTaskIntentClassifier.classify(goal).intent)
            assertFalse(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
    }

    @Test fun actualCodeRequestsRemainExecutableBesideBusinessData() {
        listOf(
            "Write Python code to total {\"code\":\"BIZ-001\",\"values\":[15,34,20]}",
            "Implement the parser for {\"code\":\"BIZ-001\"} in this repository.",
            "Run this code example and verify the result.",
            "\u7f16\u5199\u7a0b\u5e8f\u8bfb\u53d6 {\"code\":\"BIZ-001\"} \u5e76\u8fd0\u884c\u6d4b\u8bd5\u3002"
        ).forEach { goal ->
            assertTrue(goal, AgentCapability.CODE in AgentTaskRequirementAnalyzer.analyze(goal).capabilities)
            assertEquals(goal, AgentTaskIntent.CODE, AgentTaskIntentClassifier.classify(goal).intent)
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
    }

    @Test fun quotedConceptsAndInstructionValuesAreNotMistakenForFieldNames() {
        assertTrue(AgentCodeKeywordPolicy.contains("explain 'code' to me", "code"))
        assertTrue(AgentCodeKeywordPolicy.contains("{\"task\":\"write code\"}", "code"))
        assertTrue(AgentCodeKeywordPolicy.contains("{\"code\":1} write code", "code"))
        assertFalse(AgentCodeKeywordPolicy.contains("barcode code_value postcode", "code"))
        assertFalse(AgentCodeKeywordPolicy.contains("{\"code\"\n :1}", "code"))
    }
}
