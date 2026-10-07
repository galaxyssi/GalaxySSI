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
        assertEquals(11, ids.size)
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
            assertEquals(original, selected.getString("contract"))
            assertTrue(strings(selected.getJSONArray("prerequisites")).contains("foundation"))
        }
        assertFalse(CollaborationEvolutionProtocol.rules("workflows").getString("contract").contains("learning_agenda:"))
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
