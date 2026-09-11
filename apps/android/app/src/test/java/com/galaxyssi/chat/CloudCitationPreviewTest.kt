package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CloudCitationPreviewTest {
    private val result = "web_search" to AgentNativeJsonCodec.stringify(mapOf("evidence_pack" to
        AgentWebEvidencePack.build("test", "completed", listOf(mapOf(
            "url" to "https://source.example/report", "title" to "Source", "content" to "Observation.",
            "content_sha256" to "a".repeat(64)
        )), emptyList(), emptyList(), 1L)))

    @Test fun displaysCitedCompleteParagraphBeforeTheStreamEnds() {
        val preview = CloudCitationPreview(listOf(result))
        assertNull(preview.append("Observation [source](https://source.example/"))
        assertNull(preview.append("report)"))
        val text = preview.append("\n\nMore text not yet checked")
        assertEquals("Observation [source](https://source.example/report)\n\n", text)
    }

    @Test fun foreignLinksNeverEnterThePreview() {
        val preview = CloudCitationPreview(listOf(result))
        assertNull(preview.append("Wrong [source](https://foreign.example/)\n\n"))
        assertNull(preview.append("Valid [source](https://source.example/report)\n\n"))
    }

    @Test fun malformedLinksHtmlCodeAndInternalProtocolStayBuffered() {
        for (prefix in listOf("[unfinished", "<img src=\"https://foreign.example/x\">", "```text\ncode", "<tool_calls>")) {
            val preview = CloudCitationPreview(listOf(result))
            assertNull(preview.append("$prefix\n\n[source](https://source.example/report)\n\n"))
        }
    }

    @Test fun wholeAnswerStillRequiresRepairAfterASafePreview() {
        val safe = "[source](https://source.example/report)\n\n"
        val preview = CloudCitationPreview(listOf(result))
        assertEquals(safe, preview.append(safe))
        val invalid = "[invented](https://foreign.example/)\n\n"
        assertNull(preview.append(invalid))
        assertNotNull(CloudWebGrounding.citationRepairPrompt(safe + invalid, listOf(result)))
        assertNull(CloudWebGrounding.citationRepairPrompt(safe, listOf(result)))
    }
}
