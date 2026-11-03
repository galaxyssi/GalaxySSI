package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentVisualOutputContractTest {
    private val html = "<!doctype html><html><body><canvas></canvas><script>requestAnimationFrame(()=>{});</script></body></html>"
    private fun rich(text: String = html) = JSONObject().put("version", 1).put("blocks", JSONArray().put(
        JSONObject().put("type", "html").put("title", "Animation").put("text", text).put("fallback_text", "A moving diagram")))
    private fun answer(text: String) = JSONObject().put("disposition", "respond").put("final_response", text)

    @Test fun declaredRichOutputSurvivesTheDirectResponseEnvelope() {
        val raw = answer("A moving diagram").put("rich_output", rich()).toString()
        assertNull(AgentVisualOutputContract.rejection(raw))
        val plan = JSONObject(AgentSupervisedProjectDirectResponseCodec.completionPlan(raw)!!)
        val text = plan.getJSONArray("actions").getJSONObject(0).getString("description")
        val blocks = AgentRichContentCodec.fromText(text)
        assertTrue(blocks.any { it.type == AgentRichBlockType.HTML && it.text == html })
        assertTrue(blocks.any { it.type == AgentRichBlockType.TEXT && it.text == "A moving diagram" })
        val richOnly = JSONObject().put("disposition", "respond").put("rich_output", rich()).toString()
        val delivered = AgentSupervisedProjectDirectResponseCodec.parse(richOnly)!!
        assertTrue(delivered.startsWith("A moving diagram\n"))
        assertFalse(delivered.startsWith("<!doctype"))
        val textOnly = JSONObject().put("version", 1).put("blocks", JSONArray().put(
            JSONObject().put("type", "text").put("text", "No animation")))
        assertNotNull(AgentVisualOutputContract.rejection(answer("Ready").put("presentation", "inline_html")
            .put("rich_output", textOnly).toString()))
    }

    @Test fun sourceNeedsAnExplicitModelPresentationDeclarationNotUserKeywords() {
        val source = "The animation is ready\n```html\n$html\n```"
        assertTrue(AgentVisualOutputContract.rejection(source)!!.contains("html_source_is_not_animation_delivery"))
        assertNotNull(AgentVisualOutputContract.rejection(answer(source).toString()))
        assertNotNull(AgentVisualOutputContract.rejection(answer(html).toString()))
        assertNull(AgentVisualOutputContract.rejection(answer(source).put("presentation", "source").toString()))
        assertNull(AgentVisualOutputContract.rejection(answer(html).put("presentation", "source").toString()))
        assertTrue(AgentRichContentCodec.fromText(source).any { it.type == AgentRichBlockType.CODE })
        assertNull(AgentVisualOutputContract.rejection("An HTML example:\n```html\n<p>Hello</p>\n```"))
    }

    @Test fun explicitHtmlFenceDeliversTheOriginalProgramWithoutJsonEscaping() {
        val response = "Playable diagram\n```galaxyssi-html\n$html\n```"
        assertNull(AgentVisualOutputContract.rejection(response))
        val normalized = AgentSupervisedProjectDirectResponseCodec.parse(response)!!
        assertEquals(html, AgentRichContentCodec.fromText(normalized).single { it.type == AgentRichBlockType.HTML }.text)
        assertTrue(AgentRichContentCodec.fromText(response).none { it.type == AgentRichBlockType.CODE })
    }

    @Test fun inlineExecutableDocumentsAreNeverSilentlyTruncated() {
        for (text in listOf("", html.removeSuffix("</html>"), html.replace("</script>", ""),
            "<html><body>" + "x".repeat(32_000) + "</body></html>")) {
            assertNotNull(AgentVisualOutputContract.rejection(answer("Preview").put("rich_output", rich(text)).toString()))
            assertTrue(AgentRichContentCodec.decode(rich(text).toString()).isEmpty())
        }
        assertNull(AgentVisualOutputContract.htmlIssue("<div>Preview</div><style>div{color:red}</style>"))
    }

    @Test fun finalAnswerCannotDropDeclaredArtifactOrVideoRequirements() {
        val requirements = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false,
            artifacts = listOf(AgentArtifactRequirement("output/video.mp4")))
        val raw = answer("Video is ready").put("completion_requirements", requirements.toJson()).toString()
        val plan = JSONObject(AgentSupervisedProjectDirectResponseCodec.completionPlan(raw)!!)
        assertEquals(requirements, AgentCompletionRequirements.parse(plan.getJSONObject("completion_requirements")))
        assertNull(AgentSupervisedProjectDirectResponseCodec.completionPlan(answer("Ready").put(
            "completion_requirements", JSONObject().put("publication", "invalid")).toString()))
        assertNull(AgentSupervisedProjectDirectResponseCodec.completionPlan(answer("Ready").put(
            "completion_requirements", "invalid").toString()))
        assertNotNull(AgentVisualOutputContract.rejection(answer("Ready").put("rich_output", JSONArray()).toString()))
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, emptyList()).isNotEmpty())
        assertNotNull(AgentVisualOutputContract.rejection(answer("Video is ready").put("presentation", "video").toString()))
        assertNull(AgentVisualOutputContract.rejection(answer("Video is ready").put("presentation", "video")
            .put("completion_requirements", requirements.toJson()).toString()))
    }

    @Test fun promptsDistinguishInlinePreviewSourceAndEncodedVideoWithoutForcingLinux() {
        val prompt = AgentVisualOutputContract.PROMPT
        for (item in listOf("rich_output", "galaxyssi-rich", "presentation=source", "actual MP4", "no Linux or Playwright", "starts on demand"))
            assertTrue(item, prompt.contains(item))
    }
}
