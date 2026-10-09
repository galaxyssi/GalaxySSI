package com.galaxyssi.chat

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvolutionProtocolTest {
    private fun strings(value: JSONArray) = (0 until value.length()).map(value::getString)

    @Test fun catalogIsAnAcyclicDirectoryNotAnExecutionPlan() {
        val catalog = CollaborationEvolutionProtocol.rules("catalog")
        val entries = catalog.getJSONArray("topics")
        val ids = (0 until entries.length()).map { entries.getJSONObject(it).getString("id") }
        assertEquals(12, ids.size)
        assertEquals(ids.size, ids.toSet().size)
        assertEquals(listOf("catalog", "all") + ids, CollaborationEvolutionProtocol.topicIds())
        assertFalse(catalog.getBoolean("grants_permissions"))
        assertFalse(catalog.getBoolean("required_execution_sequence"))
        assertFalse(catalog.has("contract"))
        val visited = mutableSetOf<String>()
        for (index in 0 until entries.length()) {
            val entry = entries.getJSONObject(index)
            assertTrue(entry.getString("purpose").isNotBlank())
            assertTrue(visited.containsAll(strings(entry.getJSONArray("prerequisites"))))
            visited += entry.getString("id")
        }
    }

    @Test fun completeReferenceRetainsEveryContractInItsOriginalOrder() {
        val topics = CollaborationEvolutionProtocol.topicIds().drop(2)
        val contracts = topics.map { CollaborationEvolutionProtocol.rules(it).getString("contract") }
        val all = CollaborationEvolutionProtocol.rules()
        assertEquals(setOf("format", "contract"), all.keys().asSequence().toSet())
        assertEquals("galaxyssi.collaborative-evolution.v1", all.getString("format"))
        assertEquals(contracts.joinToString("\n"), all.getString("contract"))
        assertEquals(all.toString(), CollaborationEvolutionProtocol.rules("all").toString())
        assertTrue(contracts.all { it.isNotBlank() })
    }

    @Test fun coordinationRetainsExactAdvancedContractsWithoutDuplicatingThemInline() {
        val original = listOf(CollaborationDataDependencies.instructions(), CollaborationReviewTargets.instructions(),
            CollaborationReviewRebinding.instructions(), CollaborationCandidateEvolution.instructions(),
            CollaborationTeamOrganizationContext.instructions(), CollaborationCoordinationProtocol.validatorExamples())
        val recalled = CollaborationEvolutionProtocol.rules("coordination").getString("contract")
        for (text in original) assertTrue(recalled.contains(text))
        for (inline in listOf(CollaborationGoalLoop.instructions(), CollaborationLiveGraph.instructions())) {
            assertTrue(inline.contains("topic=coordination"))
            assertTrue(inline.contains("SAME topic"))
            assertTrue(inline.contains("Independent review must retain a different known author"))
            assertTrue(inline.contains("Default depends_on edges require producer completion"))
            for (text in original) assertFalse(inline.contains(text))
        }
        assertTrue(recalled.contains("producer_work_ids"))
    }

    @Test fun individualTopicsReturnExactExistingSchemasWithoutUnrelatedContracts() {
        val originals = mapOf(
            "learning" to CollaborationLearningAgenda.rules(), "procedures" to CollaborationProceduralMemory.rules(),
            "transfer" to CollaborationTransferStudy.rules(), "innovation" to CollaborationInnovationProtocol.rules(),
            "team_invention" to CollaborationTeamInventionProtocol.rules(), "prediction" to CollaborationPredictionProtocol.rules(),
            "tools" to CollaborationToolProtocol.rules(), "workflows" to CollaborationWorkflowProtocol.rules(),
            "retention" to CollaborationRetentionProtocol.rules(), "self_research" to CollaborationSelfResearchProtocol.rules())
        originals.forEach { (topic, original) ->
            val selected = CollaborationEvolutionProtocol.rules(topic)
            assertEquals(topic, selected.getString("topic"))
            assertTrue(selected.getString("contract").endsWith(original))
            assertTrue(strings(selected.getJSONArray("prerequisites")).contains("foundation"))
        }
        assertFalse(CollaborationEvolutionProtocol.rules("workflows").getString("contract").contains("learning_agenda:"))
    }

    @Test fun onDemandTopicsRetainAllGuidanceRemovedFromTheInlinePrompt() {
        val guidance = mapOf("learning" to CollaborationLearningAgenda.instructions(),
            "procedures" to CollaborationProceduralMemory.instructions(), "transfer" to CollaborationTransferStudy.instructions(),
            "innovation" to CollaborationInnovationProtocol.instructions(), "team_invention" to CollaborationTeamInventionProtocol.instructions(),
            "prediction" to CollaborationPredictionProtocol.instructions(), "tools" to CollaborationToolProtocol.instructions(),
            "workflows" to CollaborationWorkflowProtocol.instructions(), "retention" to CollaborationRetentionProtocol.instructions(),
            "self_research" to CollaborationSelfResearchProtocol.instructions())
        val inline = CollaborationEvolutionProtocol.instructions()
        guidance.forEach { (topic, text) ->
            assertFalse(inline.contains(text))
            assertTrue(CollaborationEvolutionProtocol.rules(topic).getString("contract").startsWith(text + "\n"))
        }
        println("Evolution inline characters: before=${inline.length + guidance.values.sumOf { it.length + 1 }} after=${inline.length}")
    }

    @Test fun invalidTopicsGiveAnActionableDiagnosticWithoutFallingBack() {
        for (topic in listOf("", " ", "../all", "unknown", "WORKFLOWS", "workflows ", "all\u0000")) {
            val error = runCatching { CollaborationEvolutionProtocol.rules(topic) }.exceptionOrNull()
            assertTrue(error is IllegalArgumentException)
            assertTrue(error!!.message.orEmpty().contains("topic=catalog"))
        }
    }

    @Test fun selectedSchemasReduceReadVolumeWithoutClaimingQualityOrModelSpeedup() {
        fun length(topic: String) = CollaborationEvolutionProtocol.rules(topic).toString().length
        val all = length("all")
        val workflowRead = length("catalog") + length("foundation") + length("workflows")
        assertTrue(workflowRead < all)
        assertTrue(length("catalog") <= 8_000)
        println("Evolution rule JSON characters: all=$all catalog=${length("catalog")} foundation=${length("foundation")} workflows=${length("workflows")} selected_path=$workflowRead")
        assertTrue(CollaborationEvolutionProtocol.instructions().contains("not a required sequence"))
        assertTrue(CollaborationEvolutionProtocol.instructions().contains("SAME topic"))
    }
}
