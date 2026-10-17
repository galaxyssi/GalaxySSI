package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeArtifactPresentationTest {
    private fun artifact() = AgentRuntimeArtifactUi.artifactOutput(mapOf("artifacts" to listOf(mapOf(
        "relative_path" to "report.txt", "host_path" to "/private/report.txt", "size_bytes" to 15L,
        "sha256" to "a".repeat(64), "artifact_kind" to "file"
    ))), zh = true)

    @Test fun attachmentOnlyOutputPreservesTheFinalAnswer() {
        for (base in listOf("", artifact())) {
            val blocks = AgentRichContentCodec.decode(AgentRuntimeArtifactUi.mergeWithArtifactOutputs(
                base, artifact(), fallbackText = "The sum is 12."
            ))
            assertEquals(2, blocks.size)
            assertEquals("The sum is 12.", blocks.first().text)
            assertEquals(AgentRichBlockType.FILE, blocks.last().type)
        }
    }

    @Test fun existingRichAnswerIsNotDuplicated() {
        val base = AgentRichContentCodec.encode(AgentRichContentCodec.fromText("The sum is 12."))
        val blocks = AgentRichContentCodec.decode(AgentRuntimeArtifactUi.mergeWithArtifactOutputs(
            base, artifact(), fallbackText = "The sum is 12."
        ))
        assertEquals(2, blocks.size)
        assertEquals(1, blocks.count { it.type == AgentRichBlockType.TEXT })
    }

    @Test fun plainAnswersWithoutArtifactsKeepTheirExistingRenderingPath() {
        assertEquals("", AgentRuntimeArtifactUi.mergeWithArtifactOutputs("", fallbackText = "Plain answer"))
    }

    @Test fun delimitedDataHasItsOwnMimeTypeAndCanBePreviewed() {
        mapOf("csv" to "text/csv", "tsv" to "text/tab-separated-values").forEach { (extension, mime) ->
            val rich = artifact().replace("report.txt", "report.$extension")
            val original = AgentRichContentCodec.decode(rich).single()
            val output = AgentRuntimeArtifactUi.artifactOutput(mapOf("artifacts" to listOf(mapOf(
                "relative_path" to original.title, "host_path" to "/private/${original.title}",
                "size_bytes" to 15L, "sha256" to "a".repeat(64), "artifact_kind" to "file"
            ))), zh = true)
            val block = AgentRichContentCodec.decode(output).single()
            assertEquals(mime, block.mimeType)
            assertTrue(block.actions.any { it.verb == "preview_runtime_artifact" })
            val payload = AgentRuntimeArtifactActionPayload.decode(block.actions.single { it.id == "save" }.value)!!
            assertEquals(mime, payload.mimeType)
            assertEquals("report.$extension", payload.displayName)
        }
    }

    @Test fun imagesUseInlinePreviewWhileOtherOutputsKeepFileCards() {
        val formats = mapOf("png" to "image/png", "jpg" to "image/jpeg", "jpeg" to "image/jpeg",
            "webp" to "image/webp", "pdf" to "application/pdf", "zip" to "application/zip", "md" to "text/markdown")
        formats.forEach { (extension, mime) ->
            val rich = AgentRuntimeArtifactUi.artifactOutput(mapOf("artifacts" to listOf(mapOf(
                "relative_path" to "outputs/result.$extension", "host_path" to "/private/outputs/result.$extension",
                "size_bytes" to 123L, "sha256" to "a".repeat(64), "artifact_kind" to "file"
            ))), zh = true)
            val block = AgentRichContentCodec.decode(rich).single()
            assertEquals(mime, block.mimeType)
            assertEquals(if (mime.startsWith("image/")) AgentRichBlockType.IMAGE else AgentRichBlockType.FILE, block.type)
            assertTrue(block.actions.any { it.verb == "save_runtime_artifact" })
            assertEquals(listOf(block), AgentRichContentCodec.decode(AgentRuntimeArtifactUi.mergeArtifactOutputs(rich, rich)))
        }
    }
}
