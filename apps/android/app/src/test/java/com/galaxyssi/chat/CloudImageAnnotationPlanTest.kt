package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CloudImageAnnotationPlanTest {
    private fun arguments() = JSONObject().put("image_index", 0).put("marks", JSONArray().put(
        JSONObject().put("left", 0.1).put("top", 0.2).put("right", 0.8).put("bottom", 0.4)
            .put("verdict", "incorrect").put("note", "1 + 1 = 2")))

    @Test fun parsesCoordinatesAndCorrectionWithoutChangingThem() {
        val plan = CloudImageAnnotationPlan.parse(arguments(), 1)
        assertEquals(0, plan.imageIndex)
        assertEquals(0.2f, plan.marks.single().top)
        assertEquals("1 + 1 = 2", plan.marks.single().note)
    }

    @Test fun onlyCurrentRequestImagesAreAddressable() {
        for (index in listOf(-1, 1, 200, 0.5)) {
            assertTrue(runCatching { CloudImageAnnotationPlan.parse(arguments().put("image_index", index), 1) }.isFailure)
        }
        assertTrue(runCatching { CloudImageAnnotationPlan.parse(arguments(), 0) }.isFailure)
    }

    @Test fun rejectsOutOfBoundsInvertedAndZeroAreaRectangles() {
        listOf("left" to -0.1, "bottom" to 1.1, "right" to 0.1, "top" to 0.5).forEach { (key, value) ->
            val input = arguments()
            input.getJSONArray("marks").getJSONObject(0).put(key, value)
            assertTrue(runCatching { CloudImageAnnotationPlan.parse(input, 1) }.isFailure)
        }
    }

    @Test fun rejectsEmptyMarksUnknownVerdictAndExcessiveNotes() {
        assertTrue(runCatching { CloudImageAnnotationPlan.parse(arguments().put("marks", JSONArray()), 1) }.isFailure)
        for ((key, value) in listOf("verdict" to "guess", "note" to "", "note" to "x".repeat(161))) {
            val input = arguments()
            input.getJSONArray("marks").getJSONObject(0).put(key, value)
            assertTrue(runCatching { CloudImageAnnotationPlan.parse(input, 1) }.isFailure)
        }
    }

    @Test fun uncertainVerdictIsExplicitlySupported() {
        val input = arguments()
        input.getJSONArray("marks").getJSONObject(0).put("verdict", "uncertain")
        assertEquals("uncertain", CloudImageAnnotationPlan.parse(input, 1).marks.single().verdict)
        assertTrue(CloudImageAnnotationPlan.instruction(1).contains("Never infer unreadable handwriting"))
    }

    @Test fun noImagesMeansNoAnnotationToolOrExtraInstruction() {
        fun names(images: List<CloudImagePayload>) = CloudModelClient.conversationTools(images).let { tools ->
            (0 until tools.length()).map { tools.getJSONObject(it).getJSONObject("function").getString("name") }
        }
        assertFalse(names(emptyList()).contains(CloudImageAnnotationPlan.TOOL))
        assertEquals("", CloudImageAnnotationPlan.instruction(0))
        assertTrue(names(listOf(CloudImagePayload("image.png", "image/png", byteArrayOf(1))))
            .contains(CloudImageAnnotationPlan.TOOL))
    }

    @Test fun nativeSourceUriNeverEntersProviderPayload() {
        val image = CloudImagePayload("paper.png", "image/png", byteArrayOf(1, 2, 3), "content://private/input")
        val messages = JSONArray().put(JSONObject().put("role", "user").put("content", "Check"))
        CloudVisionPayloadEncoder.attachOpenAi(messages, listOf(image))
        assertFalse(messages.toString().contains("private"))
        assertTrue(messages.toString().contains("data:image/png;base64"))
    }

    @Test fun toolSchemaDoesNotAcceptArbitraryFilesOrScripts() {
        val schema = CloudImageAnnotationPlan.definition().getJSONObject("function").getJSONObject("parameters")
        assertFalse(schema.getBoolean("additionalProperties"))
        assertEquals(setOf("image_index", "marks"), schema.getJSONObject("properties").keys().asSequence().toSet())
    }

    @Test fun distinctRenderedImagesCountAsProgressButRepeatedResultsDoNot() {
        val progress = CloudWebToolLoopProgress()
        fun result(hash: String) = JSONObject().put("tool", CloudImageAnnotationPlan.TOOL)
            .put("status", "completed").put("image_saved", true).put("image_sha256", hash).toString()
        (1..4).forEach { assertFalse(progress.observeEvidenceBatch(listOf(result(it.toString().repeat(64))))) }
        assertFalse(progress.observeEvidenceBatch(listOf(result("4".repeat(64)))))
        assertFalse(progress.observeEvidenceBatch(listOf(result("4".repeat(64)))))
        assertTrue(progress.observeEvidenceBatch(listOf(result("4".repeat(64)))))
    }
}
