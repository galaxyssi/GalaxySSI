package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CloudEvidenceCitationsTest {
    private val pack = AgentWebEvidencePack.build("test", "completed", listOf(mapOf(
        "url" to "https://example.com/report_(revision)?key=one&x=two",
        "title" to "A source", "content" to "The observed result is preliminary.",
        "content_sha256" to "a".repeat(64)
    )), emptyList(), emptyList(), 1L)
    private val evidence = listOf("web_search" to AgentNativeJsonCodec.stringify(mapOf("evidence_pack" to pack)))
    private val source = AgentWebEvidenceVerification.citationSources(evidence).single()
    private val marker get() = "[[cite:${source.id}]]"

    @Test fun compilesExactVerifiedUrlWithoutRewritingQueryOrParentheses() {
        val resolved = CloudEvidenceCitations.resolve("A result $marker", evidence)
        assertEquals("A result [1](<${source.url}>)", resolved.text)
        assertTrue(resolved.unresolved.isEmpty())
        assertTrue(AgentWebEvidenceVerification.validateAnswer(resolved.text, evidence).valid)
        val rendered = AgentInlineMarkdown.parse(resolved.text)
        assertEquals("A result 1", rendered.joinToString("") { it.text })
        assertEquals(source.url, rendered.single { it.style == AgentInlineStyle.LINK }.url)
    }

    @Test fun unknownIdsNeverBecomeSourcesOrPassValidation() {
        val answer = "Known $marker; unknown [[cite:${"b".repeat(24)}]]"
        assertEquals(listOf("b".repeat(24)), CloudEvidenceCitations.resolve(answer, evidence).unresolved)
        assertEquals("unresolved_citations", AgentWebEvidenceVerification.validateAnswer(answer, evidence).status)
        assertTrue(AgentWebEvidenceVerification.validateAnswer(answer, evidence).requiresRepair)
    }

    @Test fun tamperedEvidenceCannotResolveAnId() {
        val encoded = JSONObject(evidence.single().second)
        encoded.getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
            .put("citation_id", "b".repeat(24))
        val result = CloudEvidenceCitations.resolve("[[cite:${"b".repeat(24)}]]",
            listOf("web_search" to encoded.toString()))
        assertEquals(1, result.unresolved.size)
        assertFalse(result.text.contains("https://"))
    }

    @Test fun codeExamplesImagesAndLinkLabelsAreNotRewritten() {
        for (example in listOf("`$marker`", "```text\n$marker\n```", "    $marker",
            "![picture $marker](https://example.com/image.png)", "[label $marker](https://example.com/)")) {
            val resolved = CloudEvidenceCitations.resolve(example, evidence)
            assertEquals(example, resolved.text)
            assertTrue(resolved.unresolved.isEmpty())
        }
    }

    @Test fun previewAndFinalResolveToTheSameLinksAcrossDeltas() {
        val preview = CloudCitationPreview(evidence)
        assertNull(preview.append("A result [[cite:"))
        val shown = preview.append("${source.id}]]\n\n")
        assertEquals(CloudEvidenceCitations.resolve("A result $marker\n\n", evidence).text, shown)
    }

    @Test fun duplicateEvidenceHasOneDeterministicCitation() {
        val result = CloudEvidenceCitations.resolve("$marker $marker", evidence + evidence)
        assertEquals("[1](<${source.url}>) [1](<${source.url}>)", result.text)
    }

    @Test fun partialRepairIsBoundedAndNeverJustStripsLinks() {
        val progress = CloudWebToolLoopProgress()
        assertFalse(progress.requestPartialSynthesisRepair())
        assertTrue(progress.requestSynthesisCitationRepair())
        assertFalse(progress.requestSynthesisCitationRepair())
        assertTrue(progress.requestPartialSynthesisRepair())
        assertFalse(progress.requestPartialSynthesisRepair())
        val prompt = CloudEvidenceCitations.repairPrompt(evidence, true)
        assertTrue(prompt.contains("Remove unsupported claims"))
        assertTrue(prompt.contains("PARTIAL answer"))
        assertTrue(prompt.contains(source.id))
    }
}
