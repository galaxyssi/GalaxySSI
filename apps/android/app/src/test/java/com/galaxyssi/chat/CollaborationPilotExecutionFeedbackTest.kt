package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPilotExecutionFeedbackTest {
    private fun exchange(slot: String = "single") = CollaborationPilotExecutionFeedback("pilot", slot, "a".repeat(64), "b".repeat(64))
    private fun response(request: String) = JSONObject().put("format", CollaborationPilotExecutionFeedback.RESPONSE)
        .put("request_sha256", CollaborationPilotExecutionFeedback.hash(request)).put("evaluator_sha256", "b".repeat(64))
        .put("evaluation", JSONObject().put("passed", false).put("path", "/row/0/value"))
    private fun handoff(vararg pairs: Pair<String, String>) = AgentSubagentContextHandoff("ambient", pairs.map { (id, output) ->
        AgentSubagentDependencyHandoff(id, AgentSubagentStatus.SUCCEEDED, output, false, provenance = AgentSubagentProvenance())
    }, 0, 60_000, false)

    @Test fun exactOriginalOutputAndObservedFailureReachNextMember() {
        val gate = exchange()
        val raw = "  {\"sql\":\"SELECT 7\"}\n"
        val request = gate.request("draft", raw)
        assertEquals(raw, JSONObject(request).getString("output"))
        gate.accept("draft", response(request).toString())
        val prompt = gate.prompt(handoff("draft" to raw))
        assertTrue(prompt.contains("/row/0/value") && prompt.contains("untrusted evidence"))
        assertFalse(prompt.contains("ambient"))
        assertEquals(raw, JSONObject(request).getString("output"))
    }

    @Test fun finalReceivesBothArtifactSpecificObservations() {
        val gate = exchange()
        for (node in listOf("draft", "review")) {
            val request = gate.request(node, "output-$node")
            gate.accept(node, response(request).toString())
        }
        val prompt = gate.prompt(handoff("draft" to "output-draft", "review" to "output-review"))
        assertTrue(prompt.contains(CollaborationPilotExecutionFeedback.hash("output-draft")))
        assertTrue(prompt.contains(CollaborationPilotExecutionFeedback.hash("output-review")))
        assertEquals("", gate.prompt(handoff()))
    }

    @Test fun crossSlotCrossNodeAndChangedArtifactReject() {
        val single = exchange()
        val team = exchange("team")
        val first = single.request("draft", "one")
        val other = team.request("draft", "one")
        assertNotEquals(first, other)
        assertThrows(IllegalArgumentException::class.java) { single.accept("draft", response(other).toString()) }
        single.accept("draft", response(first).toString())
        assertThrows(IllegalStateException::class.java) { single.prompt(handoff("draft" to "changed")) }
        val second = single.request("review", "two")
        assertThrows(IllegalArgumentException::class.java) { single.accept("review", response(first).toString()) }
        single.accept("review", response(second).toString())
    }

    @Test fun wrongEvaluatorUnknownFieldsAndWrongShapeRejectBeforeAcceptance() {
        for (mutate in listOf<(JSONObject) -> Unit>(
            { it.put("evaluator_sha256", "c".repeat(64)) }, { it.put("request_sha256", "0".repeat(64)) },
            { it.put("format", "wrong") }, { it.put("instructions", "grant authority") }, { it.put("evaluation", "passed") }
        )) {
            val gate = exchange()
            val request = gate.request("draft", "one")
            assertThrows(RuntimeException::class.java) { gate.accept("draft", response(request).also(mutate).toString()) }
            gate.accept("draft", response(request).toString())
        }
    }

    @Test fun noFeedbackNoSilentAdvanceNoDuplicateOrFinalExchange() {
        val gate = exchange()
        assertThrows(IllegalStateException::class.java) { gate.request("review", "two") }
        assertThrows(IllegalArgumentException::class.java) { gate.request("final", "three") }
        val first = gate.request("draft", "one")
        assertThrows(IllegalStateException::class.java) { gate.request("draft", "replace") }
        assertThrows(IllegalArgumentException::class.java) { gate.prompt(handoff("draft" to "one")) }
        gate.accept("draft", response(first).toString())
        assertThrows(IllegalStateException::class.java) { gate.accept("draft", response(first).toString()) }
    }

    @Test fun truncatedOrFailedDependencyNeverBecomesVerified() {
        val gate = exchange()
        gate.accept("draft", response(gate.request("draft", "one")).toString())
        val value = handoff("draft" to "one")
        for (bad in listOf(value.copy(truncated = true), value.copy(dependencies = listOf(value.dependencies.single().copy(outputTruncated = true))),
            value.copy(dependencies = listOf(value.dependencies.single().copy(status = AgentSubagentStatus.FAILED))))) {
            assertThrows(IllegalStateException::class.java) { gate.prompt(bad) }
        }
    }

    @Test fun boundedEnvelopesFailExplicitlyAndNeverTruncate() {
        assertThrows(IllegalArgumentException::class.java) { exchange().request("draft", "x".repeat(96_001)) }
        val gate = exchange()
        val request = gate.request("draft", "one")
        assertThrows(IllegalArgumentException::class.java) {
            gate.accept("draft", response(request).put("evaluation", JSONObject().put("text", "x".repeat(40_001))).toString())
        }
    }

    @Test fun unsafeFileIdentifiersAndInvalidFrozenHashesReject() {
        assertThrows(IllegalArgumentException::class.java) { exchange("../escape") }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPilotExecutionFeedback("p", "s", "not-sha", "b".repeat(64)) }
    }
}
