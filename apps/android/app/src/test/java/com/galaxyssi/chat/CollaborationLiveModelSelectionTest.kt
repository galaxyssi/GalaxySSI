package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationLiveModelSelectionTest {
    private val selection = CollaborationLiveModelSelection.from("gpt-6-astra", "xhigh")
    private fun target(id: String, model: String, adapter: String = "codex-app-server-or-cli") = AgentCallableTarget(
        id, id, if (adapter == "cloud-model-api") AgentConnectorKind.MODEL else AgentConnectorKind.AGENT,
        AgentConnectorStatus.AVAILABLE, emptyList(), adapterType = adapter,
        invocationProfile = AgentInvocationProfile(defaultModelId = "old-default",
            models = listOf(AgentModelOption("old-default"), AgentModelOption(model)),
            reasoningEfforts = listOf(AgentModelReasoningEffort.MEDIUM, AgentModelReasoningEffort.XHIGH)))
    private fun members() = selection.members(target("desktop:codex", selection.modelId))

    @Test fun sameModelOverridesMutableDefaultsForEveryDistinctMemberAndAssignment() {
        val people = members()
        assertEquals(listOf("gpt-6-astra", "gpt-6-astra"), people.map { it.modelId })
        assertEquals(listOf("desktop:codex", "desktop:codex"), people.map { it.agentId })
        assertEquals(2, people.map { it.id }.toSet().size)
        for (person in people) for (stage in listOf("EXECUTE", "RECHECK", "DELIVER")) {
            val context = selection.context(person, "isolated-group", stage)
            assertEquals(person.modelId, context["collaboration_model_id"])
            assertEquals("xhigh", context[CollaborationReasoningSelection.KEY])
            assertEquals(person.id, context[CollaborationResearchWorkflow.PERSON])
            assertEquals(stage, context[CollaborationResearchWorkflow.STAGE])
            assertEquals("isolated-group", context["collaboration_group_id"])
        }
        assertTrue(people.last().independentReview)
        assertEquals(people.first().modelId, people.first().requested("g").modelId)
    }

    @Test fun omittedAutomaticOrMalformedSelectionFailsBeforeAnyFixtureStarts() {
        for (bad in listOf(null, "", " ", "auto", "default", "latest", "AUTO", " gpt-6-astra", "x\ny", "x".repeat(257))) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationLiveModelSelection.from(bad, "xhigh") }
        }
    }

    @Test fun unavailableOrUnadvertisedModelDoesNotNormalizeToDefault() {
        val available = target("desktop:codex", selection.modelId)
        for (changed in listOf(available.copy(status = AgentConnectorStatus.DISCONNECTED),
            available.copy(invocationProfile = AgentInvocationProfile("old-default", listOf(AgentModelOption("old-default")))))) {
            assertThrows(IllegalArgumentException::class.java) {
                CollaborationLiveModelSelection.requireAvailable(changed, selection.modelId, selection.reasoningEffort)
            }
        }
        for (adapter in listOf("cloud-model-api", "local-model-api", "claude-code-cli", "")) {
            assertThrows(IllegalArgumentException::class.java) { selection.members(available.copy(adapterType = adapter)) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationLiveModelSelection.requireAvailable(available.copy(kind = AgentConnectorKind.DEVICE), selection.modelId, selection.reasoningEffort)
        }
        assertThrows(IllegalArgumentException::class.java) {
            selection.members(target("cloud:openai", selection.modelId, "cloud-model-api"))
        }
    }

    @Test fun missingOrUnadvertisedEffortCannotFallBackToDesktopDefaults() {
        for (effort in listOf(null, "", "auto", "XHIGH", "max", " xhigh", "unknown")) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationLiveModelSelection.from("gpt-6-astra", effort) }
        }
        val available = target("desktop:codex", selection.modelId)
        assertThrows(IllegalArgumentException::class.java) {
            selection.members(available.copy(invocationProfile = available.invocationProfile.copy(
                reasoningEfforts = listOf(AgentModelReasoningEffort.MEDIUM))))
        }
    }

    @Test fun missingMemberModelCannotSilentlyReenterDefaultRouting() {
        assertThrows(IllegalArgumentException::class.java) { selection.context(members().first().copy(modelId = ""), "g", "EXECUTE") }
        assertThrows(IllegalArgumentException::class.java) { selection.context(members().last().copy(modelId = "old-default"), "g", "RECHECK") }
    }

    @Test fun requestedModelsNeverMasqueradeAsActualProviderObservations() {
        val record = selection.json()
        assertEquals("gpt-6-astra", record.getString("requested_model"))
        assertEquals("android_desktop_codex_openai", record.getString("execution_route"))
        assertTrue(record.getBoolean("same_model_all_members"))
        assertTrue(record.isNull("served_model"))
        assertEquals("xhigh", record.getString("requested_reasoning_effort"))
        assertTrue(record.isNull("served_reasoning_effort"))
        assertEquals("not_verified_by_this_record", record.getString("availability"))
    }
}
