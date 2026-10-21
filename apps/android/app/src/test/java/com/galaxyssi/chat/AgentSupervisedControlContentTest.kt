package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentSupervisedControlContentTest {
    private val dsml = "<\uFF5C\uFF5CDSML\uFF5C\uFF5C calls>\n" +
        "<\uFF5C\uFF5CDSML\uFF5C\uFF5C invoke name=\"galaxyssi.web.intelligence.search\">" +
        "<\uFF5C\uFF5CDSML\uFF5C\uFF5C parameter name=\"query\" string=\"true\">" +
        "\u73e0\u6d77 \u5cad\u5357\u4e16\u5bb6</\uFF5C\uFF5CDSML\uFF5C\uFF5C parameter>" +
        "</\uFF5C\uFF5CDSML\uFF5C\uFF5C invoke></\uFF5C\uFF5CDSML\uFF5C\uFF5C calls>"

    @Test fun providerInstructionsNeverBecomeDirectAnswers() {
        val examples = listOf(dsml, "Searching now\n$dsml", "```xml\n$dsml\n```",
            "<DSML", "<||DSML||", "<tool_calls>", "<invoke name=\"search\">",
            """{"tool_calls":[{"function":{"name":"search","arguments":"{}"}}]}""",
            """{"function_call":{"name":"search","arguments":"{}"}}""",
            """Here is the plan: {"execution_location":"phone","actions":[]}""",
            """[{"tool_calls":[]}]""")
        examples.forEach { raw ->
            assertTrue(raw, AgentSupervisedControlContent.isProtocol(raw))
            assertNull(raw, AgentSupervisedProjectDirectResponseCodec.parse(raw))
            assertEquals(raw, "", AgentSupervisedProjectControlPayload.visibleModelOutput(raw))
            assertTrue(AgentSupervisedProjectControlPayload.isTranscriptControlPayload(raw, ""))
        }
    }

    @Test fun responseEnvelopesCannotSmuggleCallsOrNonTextResults() {
        listOf<Any>(dsml, JSONObject().put("tool_calls", org.json.JSONArray())).forEach { answer ->
            val raw = JSONObject().put("disposition", "respond").put("final_response", answer).toString()
            assertNull(AgentSupervisedProjectDirectResponseCodec.parse(raw))
        }
        assertNull(AgentSupervisedProjectDirectResponseCodec.parse(
            """{"disposition":"respond","final_response":"Done","actions":[]}"""))
    }

    @Test fun normalAnswersAndStructuredCodexPlansRemainUnchanged() {
        listOf("Hello", "\u4f60\u597d", "DSML is a tool protocol.", "2 < 3", "<b>Title</b>",
            "Example config: {\"name\":\"example\",\"enabled\":true}",
            "![Photo](https://example.com/photo.png)").forEach { answer ->
            assertFalse(AgentSupervisedControlContent.isProtocol(answer))
            assertEquals(answer, AgentSupervisedProjectDirectResponseCodec.parse(answer))
            assertEquals(answer, AgentSupervisedProjectDirectResponseCodec.parse(JSONObject()
                .put("disposition", "respond").put("final_response", answer).toString()))
        }
        val plan = """{"execution_location":"phone","summary":"Search public sources","actions":[]}"""
        assertNull(AgentSupervisedProjectDirectResponseCodec.parse(plan))
        assertEquals("Search public sources", AgentSupervisedProjectControlPayload.visibleModelOutput(plan))
        assertEquals(plan, AgentSupervisedProjectControlPayload.normalize(plan))
    }

    @Test fun summariesAndActionDescriptionsDoNotPublishProtocol() {
        assertEquals("", AgentSupervisedProjectControlPayload.visibleModelOutput(
            JSONObject().put("summary", dsml).toString()))
        assertEquals("", AgentSupervisedProjectControlPayload.visibleModelOutput(
            JSONObject().put("actions", org.json.JSONArray().put(JSONObject().put("description", dsml))).toString()))
    }

    @Test fun userMessagesQuotingTheBrokenOutputAreNeverHiddenOrDeleted() {
        val entry = AgentTranscriptEntry("quoted", AgentTranscriptRole.USER, dsml, 1L)
        assertFalse(AgentSupervisedProjectControlPayload.isTranscriptControlPayload(entry))
        assertTrue(AgentSupervisedProjectControlPayload.isTranscriptControlPayload(
            entry.copy(role = AgentTranscriptRole.ASSISTANT)))
    }
}
