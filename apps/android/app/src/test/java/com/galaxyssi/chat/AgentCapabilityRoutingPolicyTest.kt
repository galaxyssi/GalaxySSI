package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentCapabilityRoutingPolicyTest {
    private val codex = StaticAgentConnectorRegistry().availableTargets().first { it.id == "codex" }
    private val interpreter = setOf(AgentCapability.CHAT, AgentCapability.REASONING)

    @Test fun pdfExplanationDoesNotRequireAKnowledgeConnector() {
        val requirements = AgentTaskRequirementAnalyzer.analyze(
            "Don't open settings or select PDF. Just briefly explain what those two commands would do. Do not operate the phone."
        )
        assertTrue(AgentCapability.KNOWLEDGE_SEARCH in requirements.capabilities)
        assertFalse(AgentCapability.KNOWLEDGE_SEARCH in codex.capabilities)
        assertEquals(AgentCapabilityRequirementSource.INFERRED, requirements.capabilitySource)
        assertTrue(AgentCapabilityRoutingPolicy.missingRequired(requirements, codex.capabilities.toSet()).isEmpty())
        assertTrue(AgentCapabilityRoutingPolicy.fitScore(requirements, codex.capabilities.toSet()) >= 0)
    }

    @Test fun discussionTopicsDoNotExcludeAnInterpreter() {
        listOf(
            "Explain MCP and skills, without executing anything.",
            "What is knowledge retrieval from a document?",
            "Explain why you should not click an unknown link.",
            "Compare Python code with pseudocode.",
            "Explain the meaning of 'turn on light'; do not control any device.",
            "\u53ea\u89e3\u91ca\u77e5\u8bc6\u5e93\u3001\u6280\u80fd\u548c\u70b9\u51fb\u64cd\u4f5c\uff0c\u4e0d\u8981\u6267\u884c\u3002"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
            assertTrue(goal, AgentCapabilityRoutingPolicy.missingRequired(requirements, interpreter).isEmpty())
            assertTrue(goal, AgentCapabilityRoutingPolicy.fitScore(requirements, interpreter) >= 0)
        }
    }

    @Test fun manyInferredTopicsCannotAccumulateIntoACapabilityRejection() {
        val requirements = AgentTaskRequirementAnalyzer.analyze(
            "Explain code, PDF, knowledge, MCP, skills, click and turn on light. Do not execute anything."
        )
        assertTrue(requirements.capabilities.size >= 8)
        assertTrue(AgentCapabilityRoutingPolicy.missingRequired(requirements, interpreter).isEmpty())
        assertTrue(AgentCapabilityRoutingPolicy.fitScore(requirements, interpreter) >= 0)
    }

    @Test fun inferredCapabilitiesStillPreferRelevantSpecialists() {
        val requirements = AgentTaskRequirementAnalyzer.analyze("Explain PDF document retrieval")
        val specialist = interpreter + AgentCapability.KNOWLEDGE_SEARCH
        assertTrue(
            AgentCapabilityRoutingPolicy.fitScore(requirements, specialist) >
                AgentCapabilityRoutingPolicy.fitScore(requirements, interpreter)
        )
    }

    @Test fun declaredRequirementsKeepTheirHardGateByDefault() {
        val mandatory = setOf(
            AgentCapability.LIVE_DATA, AgentCapability.CODE, AgentCapability.DEVICE_CONTROL,
            AgentCapability.APP_NAVIGATION, AgentCapability.KNOWLEDGE_SEARCH,
            AgentCapability.MCP, AgentCapability.SKILL
        )
        mandatory.forEach { capability ->
            val requirements = AgentTaskRequirements(
                setOf(AgentCapability.CHAT, capability), AgentRoutingMode.BALANCED,
                false, false, false, 100
            )
            assertEquals(AgentCapabilityRequirementSource.DECLARED, requirements.capabilitySource)
            assertEquals(setOf(capability), AgentCapabilityRoutingPolicy.missingRequired(requirements, interpreter))
            assertTrue(AgentCapabilityRoutingPolicy.missingRequired(requirements, interpreter + capability).isEmpty())
        }
    }

    @Test fun confirmedRequirementsCanBePromotedWithoutLosingCapabilities() {
        val inferred = AgentTaskRequirementAnalyzer.analyze("Search this PDF document")
        val declared = inferred.copy(capabilitySource = AgentCapabilityRequirementSource.DECLARED)
        assertEquals(inferred.capabilities, declared.capabilities)
        assertEquals(
            setOf(AgentCapability.KNOWLEDGE_SEARCH),
            AgentCapabilityRoutingPolicy.missingRequired(declared, interpreter)
        )
    }

    @Test fun copyingCapabilitiesDoesNotRetainStaleMandatoryRequirements() {
        val declared = AgentTaskRequirementAnalyzer.analyze("Read this PDF")
            .copy(capabilitySource = AgentCapabilityRequirementSource.DECLARED)
        val reduced = declared.copy(capabilities = setOf(AgentCapability.CHAT))
        assertTrue(AgentCapabilityRoutingPolicy.missingRequired(reduced, interpreter).isEmpty())
        val inferred = declared.copy(capabilitySource = AgentCapabilityRequirementSource.INFERRED)
        assertEquals(AgentCapabilityRequirementSource.INFERRED, inferred.copy(capabilities = interpreter).capabilitySource)
    }

    @Test fun inferredCapabilitiesDoNotRelaxPrivacyClassification() {
        val restricted = AgentTaskRequirementAnalyzer.analyze("Keep this password document local only and offline")
        assertTrue(restricted.localOnly)
        assertEquals(AgentRoutingMode.PRIVATE, restricted.mode)
        assertEquals(AgentDataSensitivity.RESTRICTED, restricted.dataSensitivity)
        assertEquals(AgentCapabilityRequirementSource.INFERRED, restricted.capabilitySource)
    }

    @Test fun unavailableRouteCannotBeRevivedByInferredCapabilities() {
        val requirements = AgentTaskRequirementAnalyzer.analyze("Explain PDF")
        val decision = AgentRoutingDecision(requirements, null, emptyList())
        assertNull(AgentStableAutoRoutePolicy.select(listOf(codex), decision))
    }

    @Test fun declaredPartialMatchScoringIsUnchanged() {
        val requirements = AgentTaskRequirements(
            setOf(AgentCapability.CHAT, AgentCapability.TOOL_USE), AgentRoutingMode.BALANCED,
            false, false, false, 100
        )
        assertEquals(320, AgentCapabilityRoutingPolicy.fitScore(requirements, interpreter))
        assertEquals(500, AgentCapabilityRoutingPolicy.fitScore(requirements, interpreter + AgentCapability.TOOL_USE))
    }

    @Test fun inferredScoreDoesNotInflateQualityRoutingBaseline() {
        val requirements = AgentTaskRequirementAnalyzer.analyze("Explain PDF and MCP")
        assertEquals(500, AgentCapabilityRoutingPolicy.fitScore(requirements, requirements.capabilities))
        assertEquals(320, AgentCapabilityRoutingPolicy.fitScore(
            requirements, requirements.capabilities - AgentCapability.KNOWLEDGE_SEARCH
        ))
        assertEquals(0, AgentCapabilityRoutingPolicy.fitScore(requirements, emptySet()))
    }
}
