package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationDataDependenciesTest {
    private fun item() = JSONObject().put("id", "consumer").put("member", "peer")
        .put("depends_on", JSONArray().put("producer"))
    private fun contract() = CollaborationDataDependencies.array(mapOf("producer" to "Measured data and method"))

    @Test fun declarationIsValidatedByWorkGraph() {
        val producer = JSONObject().put("id", "producer").put("member", "author")
        for (bad in listOf<Any>("not-array", JSONObject.NULL, JSONArray().put(JSONObject().put("work_id", "missing").put("requirement", "data")),
            contract().put(contract().getJSONObject(0)), JSONArray().put(JSONObject().put("work_id", "producer").put("requirement", "")),
            JSONArray().put(JSONObject().put("work_id", "producer").put("requirement", "data").put("permission", "all")))) {
            val plan = CollaborationWorkGraph.compile(listOf(producer, item().put(CollaborationDataDependencies.FIELD, bad)), emptySet())
            assertTrue("Rejected $bad", plan.error.isNotBlank())
        }
        assertEquals("", CollaborationWorkGraph.compile(listOf(producer, item().put(CollaborationDataDependencies.FIELD, contract())), emptySet()).error)
    }

    @Test fun explicitEmptyContractSurvivesRoundTripUnlikeAbsentContract() {
        val absent = CollaborationDataDependencies.context(item())
        assertTrue(absent.isEmpty())
        val empty = CollaborationDataDependencies.context(item().put(CollaborationDataDependencies.FIELD, JSONArray()))
        assertEquals("[]", empty[CollaborationDataDependencies.CONTEXT])
        val restored = CollaborationDataDependencies.restore(item(), empty)
        assertTrue(restored.has(CollaborationDataDependencies.FIELD))
        assertTrue(CollaborationDataDependencies.read(restored).isEmpty())
        val context = CollaborationDataDependencies.context(item().put(CollaborationDataDependencies.FIELD, contract()))
        assertEquals(mapOf("producer" to "Measured data and method"), CollaborationDataDependencies.read(CollaborationDataDependencies.restore(item(), context)))
    }

    @Test fun organizationSignatureIncludesDataRequirements() {
        val before = item()
        val typed = JSONObject(before.toString()).put(CollaborationDataDependencies.FIELD, contract())
        val changed = JSONObject(typed.toString()).put(CollaborationDataDependencies.FIELD,
            CollaborationDataDependencies.array(mapOf("producer" to "A different dataset")))
        assertNotEquals(CollaborationTeamOrganization.signature(before), CollaborationTeamOrganization.signature(typed))
        assertNotEquals(CollaborationTeamOrganization.signature(typed), CollaborationTeamOrganization.signature(changed))
    }
}
