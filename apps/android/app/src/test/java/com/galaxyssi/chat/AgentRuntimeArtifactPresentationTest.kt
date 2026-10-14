package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeArtifactPresentationTest {
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
            assertEquals(rich, AgentRuntimeArtifactUi.mergeArtifactOutputs(rich, rich))
        }
    }
}
